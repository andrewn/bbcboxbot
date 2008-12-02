# Get the latest post for the user's 
# timeline in the account credentials
# given.
#
def get_latest_post_from_twitter(un, pw)
  # Create the twitter object
  twit = Twitter::Base.new(un, pw)

  # What's the last message posted to the box's timeline?
  timeline = twit.timeline(:user)

  if timeline.empty? 
    return nil
  else
    return timeline.first
  end
end

def post_box_update(un, pw, msg)
  if not DEBUG 
    @logger.log "LIVE: Post message to twitter (#{un})"
    @logger.log msg
    @logger.log 
    
    twit = Twitter::Base.new(un, pw)
    twit.update(msg)
  else
    @logger.debug "DEBUG: #{msg}"
  end
end

# Create a twitter message
# with the given lat, lon, time
# to the twitter account given.
#
def create_box_update(opts)
  
  ok = check_options_exist_in_obj(opts, :lat, :lon, :time)  
    
  if opts[:msg_length].nil?
    max_msg_length = DEFAULT_MAX_MSG_LENGTH
  else
    max_msg_length = opts[:msg_length]
  end
  
  @logger.error "Not enough data to create an update..." unless ok
  
  if ok
    lat  = opts[:lat].to_s
    lon  = opts[:lon].to_s
    time = opts[:time].to_s

    machine_location  = "L:#{lat},#{lon}:"
    machine_time      = "#{time}"
    
    relative_time   = convert_to_relative_time_string(time) + " ago"
    loc             = fetch_descriptive_location(lat,lon)
    
    descriptive_location_with_country_name = nil
        
    if loc[:place] and loc[:country]
      @logger.info "Create message: using place and country"
      descriptive_location_with_country_name = "near #{loc[:place]}, #{loc[:country]}"
    end
    
    if loc[:place] and loc[:country_code]
      @logger.info "Create message: using place and country code"
      descriptive_location_with_country_code = "near #{loc[:place]}, #{loc[:country_code]}"
    end
        
    if descriptive_location_with_country_name.nil? and descriptive_location_with_country_code.nil?
      @logger.info "Create message: using lat,lon"
      descriptive_location_with_country_name = descriptive_location_with_country_code = "near coordinates #{lat},#{lon}"
    end
    
    msg_short   = "BBC Box spotted near #{machine_location} at #{machine_time}"
    msg_medium  = "BBC Box spotted #{descriptive_location_with_country_code} (#{machine_location} #{machine_time})"
    msg_long    = "BBC Box spotted #{descriptive_location_with_country_name} (#{machine_location} #{machine_time})"
    
    msg = msg_long
    
    # Calculate how long message will be 
    #  with full descriptive location
    if msg.length > max_msg_length
      msg = msg_medium
    end
    
    if msg.length > max_msg_length
      msg = msg_short
    end
    
    if msg.length > max_msg_length
      @logger.fatal "Shortest message is longer than #{max_msg_length}. Quitting"
      Kernel.exit
    end
    
    return msg
  end
end

require 'actionpack'
require 'action_controller'
def convert_to_relative_time_string(time)
  helper_proxy = ActionController::Base.helpers
  return helper_proxy.time_ago_in_words(time)
  #return distance_of_time_in_words(time)
end

require 'net/http'
require 'uri'

def fetch_descriptive_location(lat, lon)
  
  location = {  :country        => nil, 
                :country_code   => nil, 
                :place          => nil }
  
  # This returns XML --- boring!
  reverse_geocode_url = "http://ws.geonames.org/findNearbyPlaceName?lat=#{lat}&lng=#{lon}"
  raw_data = Net::HTTP.get URI.parse(reverse_geocode_url)
  
  @logger.info "Finding from... #{reverse_geocode_url}"
  
  place_name_pattern    = /<name>(.+)<\/name>/i
  country_name_pattern  = /<countryName>(.+)<\/countryName>/i
  country_code_pattern  = /<countryCode>(.+)<\/countryCode>/i
  
  country = raw_data.match(country_name_pattern)
  place   = raw_data.match(place_name_pattern)
  code    = raw_data.match(country_code_pattern)
  
  if DEBUG
    @logger.debug "Cty: " + country[1] if country
    @logger.debug "(Code:) " + code[1] if code
    @logger.debug "Plc: " + place[1] if place
  end
  
  location[:country]      = country[1]  if country and country[1]
  location[:place]        = place[1]    if place and place[1]
  location[:country_code] = code[1]     if code and code[1]
  
  return location
end

require 'net/http'
require 'uri'
require 'json'

def get_latest_box_update_from_bbc(url)
  
  @logger.info "Fetching data from BBC: #{url}"
  
  raw_data = Net::HTTP.get URI.parse(url)
  
  # Remove whitespace and other invalid nonsense
  raw_data = remove_invalid_json_nonsense(raw_data)  
  data = JSON.parse(raw_data)
    
  if data.nil? or data["points"].nil? then 
    @logger.warn "Data from BBC source is nil, can't process latest update (returning nil)"
    return nil 
  end
  
  @logger.info "Parsed JSON points " + data["points"].length.to_s
  
  sortable_data = parse_strings_in_array_to_datetime(data["points"], "time", "lat", "lon")
  @logger.info "Sortable data points " + sortable_data.length.to_s
    
  sortable_data.sort! do |a,b|
    if a["time"].nil? or b["time"].nil?
      0
    else 
      a["time"] <=> b["time"]
    end
  end

  latest = sortable_data.last #sortable_data[0]  
  return { :time => latest["time"], :lat => latest["lat"], :lon => latest["lon"] }
end

def parse_strings_in_array_to_datetime(array, time_ref, *other_refs)
  output = []

  array.each do |e|
    o = {}
    
    if[ e[time_ref] ]
      d = DateTime.parse( e[time_ref] )
      o[time_ref] = d
    
      other_refs.each do |ref|
        o[ref] = e[ref]
      end
      
      output.push(o)
    else 
      @logger.warn "Time not found in object: #{o}. Skipping."
    end
  end
  
  return output
end

def remove_invalid_json_nonsense(raw_data)
  # Tidy curly braces between objs
  raw_data.gsub!(/\s*\{\s*/m, "{")
  raw_data.gsub!(/\s*\}\s*,\s*/m, "},")   #  },
  raw_data.gsub!(/\s*\}\s*\}\s*/m, "} }")  #  } }
  raw_data.gsub!(/\s*\}\s*\]\s*/m, "} ]")
  
  # Sort out array square brackets
  raw_data.gsub!(/\s*\[\s*/m, "[")        # [
  raw_data.gsub!(/\s*\]\s*,\s*/m, "],")   # ],
  
  # Collapse properties
  raw_data.gsub!(/\s*,\s*/m, ",") 
    
  # Remove anything at start and end that's 
  # not an array or object identifier
  raw_data.slice!(0) unless raw_data.first == "[" or raw_data.first == "{"
  raw_data.slice!(raw_data.length - 1) unless raw_data.last == "]" or raw_data.last == "}"
    
  return raw_data
end

def extract_box_data_from_message(msg)
  obj = {}
  
  found_loc   = false
  found_time  = false 
  
  location_nanoformat_pattern = /L:([+-]?\d*(.?\d*)),([+-]?\d*(.?\d*)):/i
  time_nanoformat_pattern     = /(\d+-\d+-\d+T\d+:\d+:\d+[+-]?\d+:\d+)/i
  
  loc_match   = msg.match(location_nanoformat_pattern)
  time_match  = msg.match(time_nanoformat_pattern)
    
  unless loc_match.nil?
    obj[:lat]  = loc_match[1] 
    obj[:lon]  = loc_match[3]
    found_loc = true
  end
  
  unless time_match.nil?
    obj[:time] = DateTime.parse(time_match[0])
    found_time = true
  end
  
  if found_loc and found_time
    return obj
  else 
    return nil
  end
end

# Returns true if all keys exist
# as properties of object
# false if not.
def check_options_exist_in_obj(obj, *keys)  
  keys.each do |k|
    return false if obj[k].nil?
  end
  return true
end