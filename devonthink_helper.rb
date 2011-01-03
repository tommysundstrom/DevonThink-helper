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
    begin # logs
      @log = Log.new(__FILE__)  # Logs are kept in ~/Library/Logs/Ruby/DevonThink_helper
      sleep(1)  # Console has trouble when new logs are created to quickly. TODO Move to 'log' module.
      @created_deleted_log = Log.new("Created & deleted items")
      sleep(1)
      @walker_log = Log.new('Walker') # Follows the walk of the iterators

    end
    begin # DevonThink items
      @devonthink = SBApplication.applicationWithBundleIdentifier_('com.devon-technologies.thinkpro2')
      @db = @devonthink.databases.select{|db| db.name == database}[0].get
    end

    @textedit = SBApplication.applicationWithBundleIdentifier_('com.apple.TextEdit')

    begin # Tommys stuff. TODO Remove
      @ab = @db.root.children.select{|c| c.name == 'Användbarhetsboken'}[0].get
      @ab2 = @db.root.children.select{|c| c.name == 'Användbarhetsboken 2'}[0].get
      @tillf = @db.root.children.select{|c| c.name == 'tillf'}[0].get
    end
  end

  begin # Help-functions
    begin # Iterators

      # Main iterator
      # Will yield items from inbox and other user created groups, but not from Smart Groups, Trash etc.
      def each_normal_group_record(top, wide_deep = :deep, level=0)
        # wide_deep = :wide is not implemented yet
        level += 1
        top = top.get # I'm using a lot of .get, to avoid mysterious bugs (at the cost of a slower application)
        @walker_log.debug "  "*(level-1) + "'#{top.name}' (#{top.kind})"
        yield(top)
      end

      def each_safe_record

      end
    end

    begin
      # Takes a string/symbol that points at a group, and returns the group.
      #   An empty string will return root.
      def group_from_string(group_path)
        # Get the context group
        if group_path == '' or group_path == :root then
          group = @db.root
        elsif group_path == :inbox then
          group = @db.incomingGroup
        else
          group = @devonthink.getRecordAt_in_(group_path, @db)
        end
        raise "No group with path: #{group_path}" unless group

        return group
      end
    end
  end
end # class Devonthink_helper

if __FILE__ == $0 then
  dtdb = Devonthink_helper.new('BokmarktPA04_TEST')
  group = dtdb.group_from_string(group_path)
  dtdb.each_normal_group_record('')
end