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
      sleep(1)
      @unify_url_log = Log.new('Unify URL')  # TEST

    end
    begin # DevonThink items
      @devonthink = SBApplication.applicationWithBundleIdentifier_('com.devon-technologies.thinkpro2')
      @db = @devonthink.databases.select{|db| db.name == database}[0].get       # TODO safety check for several databases
    end

    @textedit = SBApplication.applicationWithBundleIdentifier_('com.apple.TextEdit')

    begin # Tommys stuff. TODO Remove
      @ab = @db.root.children.select{|c| c.name == 'Användbarhetsboken'}[0].get
      @ab2 = @db.root.children.select{|c| c.name == 'Användbarhetsboken 2'}[0].get
      @tillf = @db.root.children.select{|c| c.name == 'tillf'}[0].get
    end
  end

  # Takes a list of records, and makes them into replicas of each other.
  # TODO: Remove when there are several identical replicas under the same parent
  # Note: What record that is made into master is random
  def make_into_replicas(records)
    begin # Basic safety net, avoiding trouble
      records.each do |r|
        case
          when r.kind ==  'Group',
               r.kind ==  'Smart Group'
            raise "'make_into_replicas' has not implemented group handling yet"
        end
        # TODO Exclude records that are in Trash
      end
    end
    return false if records.size == 0    # TODO Is this a reasonable result?

    # Remove items from records that are already replicas
    records = remove_replicas(records)  # Note: This also getifies records, making them less prone
            # for bugs when removing stuff
    return true if records.size == 1  # Job done if array has only one item left

    master = records.pop

    begin # Safety net - will raise an error if the items are not reasonably similar
      # Needs to be the same: name, URL
      # Can be different: Kind, Date, Size etc.
      records.each do |r|
        case
          when master.name != r.name,      # Stuff that must be the same.
               master.URL  != r.URL
            raise "To dissimular to safely make into replicas"
        end
      end
    end

    # Delete records and replace them with replicas of master
    while records.size > 0
      r = records.pop
      rparents = r.parents.get
      rparents = remove_replicas(r.parents)  # (Also .get-ifys)
      rparents.each do |rparent|    # Record must be replaced in all its locations
        @devonthink.replicateRecord_to_(master, rparent)
        @created_deleted_log.info "Created: '#{master.name}' (#{master.kind})"
        @devonthink.deleteRecord_in_(r, rparent)
        @created_deleted_log.info "Deleted: '#{r.name}' (#{r.kind})"
        # TODO Check that tags also are preserved
      end
    end

  end

  # Ensures that there is only one item for each URL.
  # Note: Do not run on databases that contains different, historical, versions of a web page.
  # Note: While it will only look for URLs in group, items enywhere in the database with this URL will be affected.
  def unify_URLs(group)
    urls = all_URLs_with_several_instances(group)
    urls.each do |key,value|
      make_into_replicas(value)
    end
  end

  # Checks group and subgroups so that there is just one replica in each child-group
  def uniqify_replicas_of_group(group)
    each_normal_group_record(group) do |g|
      children = g.children.get
      children = getify_array(children)

      while children.size > 1 do
        r = children.pop
        if children.map{|c| c.uuid}.include?(r.uuid) then
          # There is a replica of r in children, so let's delete it
          @devonthink.moveRecord_to_from_(r, @db.trashGroup, g)
          #@devonthink.deleteRecord_in_(r, g)
          @created_deleted_log.info "Deleted: '#{r.name}' (#{r.kind}) in '#{g.name}'"
        end
      end
    end
  end



  begin # Help-functions

    # Moves record to trash.
    # If from is nil, all instances will be moved.
    def trash(from = nil)

    end

    begin # Iterators

      # Main iterator
      # Will yield items from inbox and other user created groups, but not from Smart Groups, Trash etc.
      def each_normal_group_record(top, safe_references = true, wide_deep = :deep, level=0, limit = :all)
        # wide_deep = :wide is not implemented yet
        # safe_references = false not implemented
        # limit not implemented
        level += 1
        indent = "  "*(level-1)

        case # For case syntax, see http://ilikestuffblog.com/2008/04/15/how-to-write-case-switch-statements-in-ruby/
          when top.name == "Web Browser.html",    # Web Browser.html is a hack in DevonThink, not a regular file
               top.kind == "Smart Group",         # Since content in smart groups are also in other places, I avoid them
               top.uuid == @db.trashGroup.uuid,             # Don't look in the Trash
               top.uuid == @db.syncGroup.uuid,              # Don't know what this group really does, so I avoid it for the time being
               top.uuid == @db.tagsGroup.uuid               # TODO: I think this should eventually be included
            @walker_log.debug indent + "SKIPPED: '#{top.name}'"
          else
            top = top.get # I'm using a lot of .get, to avoid mysterious bugs (at the cost of a slower application)
            @walker_log.debug indent + "'#{top.name}' (#{top.kind})"
            yield(top)
            # TODO Daycare
            top.children.each do |child|
              each_normal_group_record(child, safe_references, wide_deep, level){|newtop| yield(newtop)}
            end
        end
      end

      # Same as each_normal_group_record, but only yields groups
      def each_normal_group(top, safe_references = true, wide_deep = :deep, level=0, limit = :all)
        # wide_deep = :wide is not implemented yet
        # safe_references = false not implemented
        # limit not implemented
        level += 1
        indent = "  "*(level-1)

        case # For case syntax, see http://ilikestuffblog.com/2008/04/15/how-to-write-case-switch-statements-in-ruby/
          when top.kind != "Group",                         # Only interested in groups
               top.uuid == @db.trashGroup.uuid,             # Don't look in the Trash
               top.uuid == @db.syncGroup.uuid,              # Don't know what this group really does, so I avoid it for the time being
               top.uuid == @db.tagsGroup.uuid,              # TODO: I think this should eventually be included
               top.name == "Web Browser.html"               # Web Browser.html is a hack in DevonThink, not a regular file
            @walker_log.debug indent + "SKIPPED: '#{top.name}'"
          else
            top = top.get # I'm using a lot of .get, to avoid mysterious bugs (at the cost of a slower application)
            @walker_log.debug indent + "'#{top.name}' (#{top.kind})"
            yield(top)
            # TODO Daycare
            top.children.each do |child|
              each_normal_group(child, safe_references, wide_deep, level){|newtop| yield(newtop)}
            end
        end
      end

    end

    begin
      # Takes a string/symbol that points at a group, and returns the group.
      #   An empty string will return root.
      def group_from_string(group_path = :root)
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

      # .get on all items in the array
      def getify_array(array_of_records)
        return array_of_records.map{|r| r.get}
      end

      def remove_replicas(array_of_records)
        aor = getify_array(array_of_records)
        aorclone = aor.clone # (Shallow copy)

        notclones = []
        while aorclone.size > 0
          r = aorclone.pop
          unless aorclone.map{|cr| cr.uuid}.include?(r.uuid) then    # Based on the assumption that replicas has identical uuids
            notclones << r
          end
        end

        return notclones
      end

      # All urls of the group
      def all_URLs(group)
        urls = Hash.new()
        each_normal_group_record(group) do |item|
          if item.URL == '' then next end # Only interested in items that has an URL
          key = item.URL.to_s  # To avoid using NSStrings (not that it really matters)
          @unify_url_log.debug "<#{key}> url of '#{item.name}' "
          if urls.has_key?(key) then
            urls[key] << item.get
          else
            urls[key] = [item.get]
          end
        end
        return urls    # hash with URL - number of this URL
      end

      # All URLs with more than one instance in group
      def all_URLs_with_several_instances(group)
        urls = all_URLs(group)
        urls.delete_if{|key,value| value.size == 1}  # Keep only the urls that have several items
        return urls
      end
    end
  end
end # class Devonthink_helper

if __FILE__ == $0 then
  dtdb = Devonthink_helper.new('BokmarktPA04_TEST')

  #group = dtdb.group_from_string(:root)  # :root for root
  #group = dtdb.group_from_string('/Användbarhetsboken')
  #group = dtdb.group_from_string('/Topics')
  #group = dtdb.group_from_string('/Topics/instruktion')
  group = dtdb.group_from_string('/Topics/hus')

  #dtdb.each_normal_group_record(group){|record| puts record.name}
  #dtdb.each_normal_group(group){|record| puts record.name}
  #dtdb.all_URLs_with_several_instances(group)
  dtdb.unify_URLs(group)
  dtdb.uniqify_replicas_of_group(group)
end