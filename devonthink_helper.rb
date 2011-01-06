#!/usr/bin/env ruby

#
#  tommys_utilities.rb
#
#  Created by Tommy Sundström on 4 jan 2011.
#


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
      @created_deleted_log = Log.new("Created & deleted items")
      @walker_log = Log.new('Walker') # Follows the walk of the iterators
      @unify_url_log = Log.new('Unify URL')  # TEST
      @pdf_to_rtf_log = Log.new('PDF to RTF')  # TEST
      # Note: Console app sometimes has trouble recognizing logs when created this quickly. If not all shows,
      # restart Console.
    end
    begin # DevonThink items
      @devonthink = SBApplication.applicationWithBundleIdentifier_('com.devon-technologies.thinkpro2')
      @db = @devonthink.databases.select{|db| db.name == database}[0].get       # TODO safety check for several databases
    end

    @textedit = SBApplication.applicationWithBundleIdentifier_('com.apple.TextEdit')
  end



  # For all documents of kind PDF+Text that has an URL, fetches the document from the web, cleans it with Readability
  # and puts the result in a RTF (or RTFD) file, in the same locations.
  #
  # TODO:
  # * Attach applescript to each record, to also show the web page when record is selected
  # * Check if there is a headline, and if not, use the title
  # * Make a screendump of web page and put in top of document
  # * Fetch the favicon and use it
  # * Make applescript to switch back to PDF version
  def transform_pdfs_to_readabilitycleaned_rtf(group)
    pdf_documents = []

    # To safely be able to add/remove records, we need real references to the documents
    count = 0
    each_pdf_document(group) do |record|
      # TODO: Check for "Don't rtf me!"-tag
      pdf_documents << record.get
      @pdf_to_rtf_log.debug "Get: '#{record.name}' (#{record.kind})"
      count += 1
    end
    @pdf_to_rtf_log.debug "--- #{count} PDFs ---"

    pdf_documents.each do |record|
      transform_a_pdf_to_readabilitycleaned_rtf(record)
    end
  end

  def transform_a_pdf_to_readabilitycleaned_rtf(original_record)
    begin
      @pdf_to_rtf_log.debug "pdf->rtf: '#{original_record.name}' (#{original_record.kind})"

      readable_html = readability(original_record.URL) if original_record.URL
      if not readable_html then return :not_redabilityish end

      # Temporary files, used as temporary storage (I'm not using tempfile, since I need to the suffix)
      html_path = '/private/tmp/devonthinkhelper_source.html'
      rtf_path = '/private/tmp/devonthinkhelper_processed.rtfd' # rtfd = files capable of containing images
      #   Remove old temp files
      FileUtils.remove_file(html_path) if File.exist?(html_path)
      FileUtils.remove_file(rtf_path, true) if File.exist?(rtf_path) # true = force remove. I was not able
            # to remove rtfd-files any other way. (rtd files was no problem).
      #   Create new tempfiles
      File.open(html_path, 'w+') do |html_file|  # Creates a temporary file, neede to get the code into textedit
        html_file.puts readable_html
      end

      html_to_rtf_file(html_path, rtf_path)  # The resulting file is now in the file at rtf_path

      begin
        replacement_record = @devonthink.import_from_name_placeholders_to_type_(rtf_path, nil, original_record.name, nil, @db.incomingGroup, nil)
      rescue Exception => e
        @log.warn "Import failed with '#{original_record.name}', due to '#{e}'"
      end

      # Infuse some metainfo from the old record into the new
      replacement_record.URL = original_record.URL
      replacement_record.date = original_record.date
      replacement_record.comment = original_record.comment
      replacement_record.unread = original_record.unread

      begin # Place the new record at the same locations as the old
        parents = original_record.parents
        parents = remove_replicas(parents)

        # Move it to the first - and trash the original
        target_group = parents.pop
        @devonthink.moveRecord_to_from_(replacement_record, target_group, @db.incomingGroup)
        @created_deleted_log.info "Created: '#{replacement_record.name}' (#{replacement_record.kind}) in '#{target_group.name}'"
        trash(original_record, target_group)
        # TODO Check that tags also are preserved

        # Replicate to the rest (if any) - and trash originals
        parents.each do |parent|
          @devonthink.replicateRecord_to_(replacement_record, parent)
          @created_deleted_log.info "Created: '#{replacement_record.name}' (#{replacement_record.kind}) in '#{parent.name}'"
          trash(original_record, parent)
          # TODO Check that tags also are preserved
        end
      end

      # TODO: Ensure that it works for tags also.
    rescue Exception => e
      @log.error "Failed to handle '#{original_record.name}'. Error: '#{}'"
    end





  end

  # Takes a PDF+Text document and replaces the text with a readability-cleaned version.
  # This will (hopefully) result in better recomendation and searches.
  # For practical reason, the PDF is replaced with the current page on the url.
  # TODO: Remove html codes.
  # TODO: Special för mig: ta bort "Texten oven..."-texten.
  # TODO: Figure how to call this when the pdf is first imported.
  def readability(url)
    begin
      source = open(url).read   # An alternative (to load protected pages) here could be
            # @devonthink.downloadMarkupFrom_agent_encoding_password_post_referrer_user
    rescue
      @pdf_to_rtf_log.warn "WARNING - Unable to open url: #{url}"
      return nil
    end

    source = source.gsub('<img', '***IMG***<img')  # Workaround to compensate that Readability removes
                                                       # paragraphs consisting only of a img element (without text)
    m = /<title>(.*?)<\/title>/.match(source)
    title = m[1] if m
    processed = Readability::Document.new(source, {
        :tags => ['div', 'p', 'a', 'img', 'h1', 'h2', 'h3', 'h4', 'h5', 'ul', 'ol', 'li', 'dl', 'dd', 'dt',
                    'strong', 'b', 'em', 'i', 'blockquote', 'pre', 'code'],
        :attributes => ['href', 'src']
    } ).content
    processed = processed.gsub('***IMG***', '')
    processed = "<html>
      <head>
      <meta http-equiv='Content-Type' content='text/html; charset=utf-8' />
      <base href='#{url}'>
      <style type='text/css'>
        body {
          background-color: white;
        }
        a {
          color: darkBlue;
        }
        body, p, li, blockquote {
          font-family: Georgia;
          font-size: 18px;
          line-height: 1.6;
        }
        img {
          border: 1px solid #333;
        }
      </style>
      </head>

      <body>" + "<h2>#{title}</h2>" + processed + "
      </body>
      </html>"
    return processed
  end

  # Uses TextEdit to convert html pages into rtf (with the purpose of later importing them into Devon)
  # Note: Result is written to rtf_file, not returned.
  def html_to_rtf_file(html_path, rtf_path)
    begin
      textedit_doc = @textedit.open(html_path)
    rescue Exception => e
      @log.warn "Unable to open document from '#{html_path}', due to '#{e}'."
    end
    begin
      textedit_doc.saveAs_in_(nil, OSX::NSURL::fileURLWithPath(rtf_path))
    rescue Exception => e
      @log.warn "Unable to save document from '#{html_path}' to '#{rtf_path}', due to '#{e}'."
    end
    begin
      textedit_doc.delete     # Important to close, since the file is force-deleted
    rescue Exception => e
      @log.warn "Unable to close codument at '#{rtf_path}', due to '#{e}'."
    end
  end



  # Takes a list of records, and makes them into replicas of each other.
  # Note: What record that is made into master is random
  def make_into_replicas(records)
    begin # Basic safety net, avoiding trouble
      safe_records = []
      records.each do |r|
        case
          when r.kind ==  'Group',
               r.kind ==  'Smart Group'
            @unify_url_log.warn "Group with URL: '#{r.name}' (#{r.kind}). Not handled, since 'make_into_replicas' does not handle groups."
            # TODO Exclude records that are in Trash
          else # (Normal case)
            safe_records << r
        end
      end
    end
    records = safe_records
    return false if records.size == 0    # TODO Is this a reasonable result?

    # Remove items from records that are already replicas
    records = remove_replicas(records)  # Note: This also getifies records, making them less prone
            # for bugs when removing stuff
    return true if records.size == 1  # Job done if array has only one item left

    master = records.pop

    begin # Safety net - will raise an error if the items are not reasonably similar
      # Needs to be the same: name, URL, comment
      # Can be different: Kind, Date, Size etc.
      safe_records = []
      records.each do |r|
        case
          when master.name != r.name,      # Stuff that must be the same.
               master.URL  != r.URL
            @unify_url_log.warn "WARNING To dissimular to safely make into replicas"
          when master.comment != r.comment
            @unify_url_log.warn "WARNING Comments differ - '#{r.name}' at '#{r.location}' will not replicated since I fear to loose unique comments."
          else # Normal case
            safe_records << r
        end
      end
      records = safe_records
    end

    # Delete records and replace them with replicas of master
    while records.size > 0
      r = records.pop
      rparents = r.parents.get
      rparents = remove_replicas(r.parents)  # (Also .get-ifys)
      rparents.each do |rparent|    # Record must be replaced in all its locations
        @devonthink.replicateRecord_to_(master, rparent)
        @created_deleted_log.info "Created: '#{master.name}' (#{master.kind})"
        trash(r, rparent)
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
      begin # Log
        @unify_url_log.debug   "Unifying: '#{key}}'"
        value.each do |r|
          @unify_url_log.debug "    '#{r.name}' (#{r.kind}) Location: #{r.location}"
        end
      end
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
          trash(r,g)
        end
      end
    end
  end

  # Attaches a script to every RTF document
  #   (Note: Changes in a script will usually not take effect until DevonThink is restarted)
  def attach_script_to_RTF_records_with_URL(group, script_filename, overwrite_existing_script = false)
    script_path = Pathname.new(File.expand_path(File.dirname(__FILE__))) + 'applescripts' + script_filename
    each_rtf_with_url_document(group) do |r|
      if r.attachedScript == '' then
          r.attachedScript = script_path.to_s
      elsif overwrite_existing_script or r.attachedScript == script_path then
        # Don't add a script
        @log.warn "Tried to attach script '#{script_path}' to '#{r.name}', but it already had one."
      end
    end
  end

  begin # Help-functions

    # Moves record to trash.
    # If from is nil, all instances will be moved.
    def trash(record, from = nil)
      @devonthink.moveRecord_to_from_(record, @db.trashGroup, from)
      @created_deleted_log.info "Deleted: '#{record.name}' (#{record.kind}) in '#{if from then from.name else '*everywhere*' end}'"
    end

    begin # Iterators

      # Main iterator
      # Will yield items from inbox and other user created groups, but not from Smart Groups, Trash etc.
      #
      # Note: These iterators use the ScriptingBridge way of refering to objects, 'Object 1 of...', meaning
      # that they additions and deletions in the group makes them unreliable. (As you can see in other
      # parts of the code, I frequently use .get, in order to transform the references into a more robust
      # form. But even so, this is a major source of confusion and bugs when working with ScriptingBridge.
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

      def each_pdf_document(top, safe_references = true, wide_deep = :deep, level=0, limit = :all)
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
            if top.kind == "PDF+Text" then
              @walker_log.debug indent + "'#{top.name}' (#{top.kind})"
              yield(top)
            end
            # TODO Daycare
            top.children.each do |child|
              each_pdf_document(child, safe_references, wide_deep, level){|newtop| yield(newtop)}
            end
        end
      end

      def each_rtf_with_url_document(top, safe_references = true, wide_deep = :deep, level=0, limit = :all)
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
            if (top.kind == "RTF" or top.kind == "RTFD") and top.URL != '' then
              @walker_log.debug indent + "'#{top.name}' (#{top.kind})"
              yield(top)
            end
            # TODO Daycare
            top.children.each do |child|
              each_rtf_with_url_document(child, safe_references, wide_deep, level){|newtop| yield(newtop)}
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
  group = dtdb.group_from_string('/Topics/3D')

  #dtdb.each_normal_group_record(group){|record| puts record.name}
  #dtdb.each_normal_group(group){|record| puts record.name}
  #dtdb.all_URLs_with_several_instances(group)

=begin   # Clean up my database
  dtdb.transform_pdfs_to_readabilitycleaned_rtf(group)
  dtdb.unify_URLs(group)
  dtdb.uniqify_replicas_of_group(group)
=end

  dtdb.attach_script_to_RTF_records_with_URL(group, 'trigger_open_URL_in_Safari.scpt')

end