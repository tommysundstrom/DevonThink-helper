#
#  Pathstring.rb
#  ItunesFeeder
#
#  Created by Tommy Sundström on 25/2-09.
#  Copyright (c) 2009 Helt Enkelt ab. All rights reserved.
#

require 'pathname'
require 'pp'
require 'osx/cocoa'


# Pathstring is a replacement for Pathname, that is a subclass to string. This way we get rid of the need
# to add to_s ever so often.
#
# Other differences:
#
# * It always expands ~-paths. 
# * Some extra utility classes.
#
class Pathstring < String
  def initialize(path)
    # I'm not 100% about these two, so for the moment they'll have to go
    # path = File.expand_path(path) if path[0].to_s == '~' # Auto-expand ~-paths
    # path = File.expand_path(path) if path[0].to_s == '.' # Auto-expand paths anchored in present working directory
    
    self.replace(path.to_s)     # to_s in case it is a Pathname
    @pathname = Pathname.new(path)
  end
  
  def method_missing(symbol, *args)
    result = @pathname.__send__(symbol, *args)      # BUG BUG BUG   Ibland ger pathname andra sorters svar, t.ex. sant/falsk eller en array
          # När det inte är en Pathname objekt jag får tillbaka, måste jag släppa vidare svaret som det är (typ)
          # Fast ev kolla på innehållet i arrayen (t.ex. när det är children, och Pathstringa dem.
    if result.class == Pathname then
      return Pathstring.new(result)
    elsif result.class == Array  then
      # If the members of the array is Pathnames, then they should be converted to Pathstrings
      return result.collect do |t|
        if t.class == Pathname then
          Pathstring.new(t)
        else
          t
        end
      end
    else
      return result # Other kinds of results are returned as they are
    end
  end

  def +(path)   # Overrides String behaviour.
    return Pathstring.new( (@pathname + Pathname.new(path)) )
  end
  
  # Differs from Pathname mkpath in that it also handles file paths
  def mkpath
    path = self.expand_path
    path = path.dirname if path.file? # Make sure the directory for the file exists
    Pathname(path).mkpath
  end
  
  
  # Added functions

  # Returns the content of the file
  #     TODO Add error handling in case file is alreay open
  def read
    return File.open(self, 'r'){|f| f.read}        
  end

  # Replaces the content of the file
  #     TODO Add error handling in case file is alreay open
  def write(new_content)
    File.open(self, 'w') {|f| f.write(new_content) }
  end

  # Like Dir.mkdir, but without the error if a folder is already in place
  # The most common error is SystemCallError = The direcotry cannot be created
  def ANVANDS_EJensure_directory   # ANVÄND MKPATH ISTÄLLET!!!!
    #$log.debug "Enters ensure_directory. self: #{self}"
    if self.exist? then 
      #$log.debug "#{self} alredy existed"
      return  # Directory already in place, no need to do anything.  
    end 
    self.mkdir  
  end
  
  # Returns the path of the volume
  #   Quite Mac-centric I'm afraid
  def volume
    path_parts = self.split(/\//) # Split on forward slash
          # (Note that path_parts[0] is the empty string before the first '/'
    if path_parts[1] == "Volumes" then
        volume = Pathstring.new(path_parts[0..2].join('/')) # /Volumes/volumename
    else
        volume = Pathstring.new('/')  # /
    end
  end
  
  def rootvolume?
    return self.volume == '/' ? true : false
  end
  
  # Checks if a volume exists (i.e. is mounted)
    def mounted?
      return File.exists?(volume) ? true : false
    end
    
  # Cheks if two paths are on the same volume
    def same_volume?(path2)
      return volume == Pathstring.new(path2).volume ? true : false  # (Yes, I know this is tautologic; but it makes the code easer to read, at least for me)
    end
    
  # Moves the file. 
  # Unlike FileUtils.mv this can move across volumes. 
  # Can not move a directory
  ##def mv(destination)
  ##end
  
  # If self is a directory, adds item.
  # If something with the same name is already present, adds a number to item and tries again, until success or to many tries.
  def enumbered_add_to_directory(item)
    $log.info "Renamed #{Pathstring.new(item).basename} to xxxx"
  end 
  
  # Array of child-files and folders that to not begin their name with a dot
  def undotted_children
    self.children.reject {|t| t[0].to_s == '.' }
  end
  
  def children_that_match(array_of_regexps)
    # TODO:
  end
  
  def children_that_dont_match(array_of_regexps)
    # TODO:
  end
  
  # Array of child-files and folders that to not begin their name with a dot
  def children_except_those_beginning_with(array_of_beginnings)
    # NOT IMPLEMENTED YET self.children.select {|t| t[0].to_s != '.' }
  end
  
  # Array of siblings (not including self)
  def siblings
    self.parent.children.reject {|t| t == self }
  end
  
  
  # Removes the extension from the basename
  # Counterpart to extname
  def basename_sans_ext
    return File.basename(self, self.extname)
  end
  
  # Removes the .DS_Store file - an autocreated file that just contains the visual settings 
  # for the folder - if there is one. Note that it may quickly be recreated by OSX. 
  # Mac-centric
  def delete_dsstore!
    if (self + '.DS_Store').exist? then
      (self + '.DS_Store').delete
    end
    return self
  end
  
  # Content of a directory, but with .DS_Store file excluded
  def children_sans_dsstore
    return self.children.reject{|t| t.basename == '.DS_Store'}
  end
  
  # Find the name for the application that contains this object
  #   Does this by finding the rb_main.rb-file in a Resource directory or the .app package.
  #   I'm not certain how robust this is. It's certainly RubyCocoa-centric.
  #   
  def application_name
    current = self.expand_path
    until current.root?
      if current.siblings.collect {|r| r.basename}.include?('rb_main.rb') then
        if current.parent.basename == 'Resources' && current.parent.parent.basename == 'Contents'
          # Part of an application bundle, applicationname.app
          OSX::NSLog "application_name (appbundle): #{current.parent.parent.parent.basename_sans_ext}"
          return current.parent.parent.parent.basename_sans_ext
        else
          # Assuming that we now are in the project folder, and that it is named like the app
          #OSX::NSLog "application_name (raw): #{current.parent.basename}"
          return current.parent.basename
        end
      end
      current = current.parent # Up one level for the next round in the loop
    end
    raise 'Unable to find an application name.'
  end
  
  # Array of the basenames of the children TROR DETTA REDAN ÄR TÄCKT AV TYP Dir*
  def children_basename
  
  end
  
end

# This makes Pathstring(path) work as Pathstring.new(path)
#       TODO: Refactor the whole Pathstring module to Path
module Kernel
  # create a pathstring object.
  #
  def Pathstring(path) # :doc:
    # require 'pathstring'
    Pathstring.new(path)
  end
  
  def Path(path)
    Pathstring.new(path)
  end
  
  private :Pathstring
end
