#!/usr/bin/env ruby

require 'rubygems'
require 'osx/cocoa'
include OSX
OSX.require_framework '/System/Library/Frameworks/ScriptingBridge.framework'

require 'log'

require 'readability' # See https://github.com/iterationlabs/ruby-readability.
      # Note: Also requires nokogiri. See Readme about installing it.
require 'open-uri'  # TODO? Where?

class Devonthink_helper
  def initialize(database)
    @log = Log.new(__FILE__)  # Logs are kept in ~/Library/Logs/Ruby/DevonThink_helper
    sleep(1)  # Console has trouble when new logs are created to quickly. TODO Move to 'log' module.
    @created_deleted_log = Log.new("Created & deleted items")
  end

end # class Devonthink_helper

if __FILE__ == $0 then
  dtd = Devonthink_helper.new('BokmarktPA04_TEST')
end