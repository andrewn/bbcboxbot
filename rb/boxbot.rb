#!/usr/bin/env ruby

# Depends on twitter:
#  sudo gem install twitter
# Docs: http://twitter.rubyforge.org/rdoc/
# Works with identi.ca -- see Twitter::Base

# Depends on json:
#  sudo gem install json

# Depends on rails:
#  ActionController::Base.helpers.time_ago_in_words
#  sudo gem install rails

# Add the absolute path of this directory to 
# Ruby's search path to ensure require works 
#  correctly.
# 
$: << File.expand_path( File.dirname(__FILE__) )

require 'rubygems'
require 'twitter'
require 'twitter_helpers'
#require 'rb/date_helper'

DEBUG = false
DEFAULT_MAX_MSG_LENGTH = 140
LOG_FILE_PATH = File.expand_path( File.dirname(__FILE__) + "/../../shared" ) + "/messages.log"
  
if DEBUG
  @logger = Logger.new(STDOUT)
else
  @logger = Logger.new(LOG_FILE_PATH, 'monthly')
end

@logger.info "# Running " + Time.now.to_s 
@logger.info "DEBUG #{DEBUG}"

username              = "bbcbox"
password              = "fmtjcsd"
current_box_feed_url  = "http://news.bbc.co.uk/nol/shared/bsp/hi/have_your_say/maps/5200/5277/data/current_leg.js"

latest_twitter    = get_latest_post_from_twitter(username, password)
latest_box_update = get_latest_box_update_from_bbc(current_box_feed_url)

if latest_box_update.nil?
  @logger.fatal "Can't get data about box from BBC"
  Kernel.exit()
end

# Extract data from latest twitter
msg_parts = extract_box_data_from_message(latest_twitter.text) unless latest_twitter.nil?
@logger.info "Msg parts: #{msg_parts}"

if latest_twitter.nil? or msg_parts.nil?
  @logger.warn "There is no box update in twitter, creating"
  create_box_update(username, password,
                    {   :lat => latest_box_update[:lat], 
                        :lon => latest_box_update[:lon],
                        :time=> latest_box_update[:time]
                    })
  Kernel.exit(0)
end

@logger.info "Latest box update time: " + latest_box_update[:time].to_s  unless latest_box_update.nil?
@logger.info "Latest twitter message: " + latest_twitter.text.to_s       unless latest_twitter.nil?


# Compare with latest 
@logger.info "Twitter time: " +  msg_parts[:time].to_s
@logger.info "Box time: " + latest_box_update[:time].to_s
@logger.info ""

message = create_box_update({   :lat => latest_box_update[:lat], 
                                :lon => latest_box_update[:lon],
                                :time=> latest_box_update[:time]
                            })
                            
@logger.info "Created message: " + message if DEBUG
@logger.info ""

# If latest box location is after latest twitter then 
# post another one
if latest_box_update[:time] > msg_parts[:time]
  @logger.info "New Box location, should post to twitter"  
  post_box_update(username, password, message) unless msg.empty?
end
