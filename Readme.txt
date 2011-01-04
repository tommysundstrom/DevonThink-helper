
BACKUP YOUR DATABASES BEFORE USING. THIS IS AN EARLY VERSION, AND CAN POTENTIALLY MESS UP YOUR VALUABLE DATA.
This is an early version, so don't trust it.

====================================================
DevonThink-helper - using Ruby to control DevonThink
====================================================

This is a test on using Ruby (instead of AppleScript) to control DevonThink.

For the moment, it can:

 * Take all records that have the same URL and consolidate them into one record, with replicas in all places where
   the records used to be.

   Cavets:  Will choose what record to replicate randomly.

            I'm not sure that tags are handled correctly (they may be, but I've not tested it enough to be sure.)

            If you intentionally have several version of the page saved - maybe to have a historical documentation -
            they will be lost.

 * Take PDF files of web-pages, replace them with Readability-versions of the page and transform it to rtf.
   At least on my databases, the Move To/See Also-functionality used to be worthless. After applying Readability to
   the pages, the results are much better (but strength of the recommendation is still seldom better than the red area).
   Also, it reduces the size of the database considerably.

   Cavets:  Will download the page again (so in worst case, if the page has disapered from the web, it will be replaced
            by a 404)

            While Readability does a decent job, it can sometime fail to identify the relevant content of the page.

            While TextEdit is does a reasonable job formatting the page, the result is not always pretty.

   (Tip: This script, that opens the web page with the same url when the record is selected, could be a good complement:
   http://www.devon-technologies.com/scripts/userforum/viewtopic.php?f=20&t=10894)


There is no user interface (not even command line), so the only way of controlling it is to write code in
the "if __FILE__ == $0 then" section, or calling if from another script.


Scripting DevonThink with Ruby
------------------------------
If you want to use Ruby to script DevonThink, I hope this code will give you some pointers on how to get started.

The biggest hurdle is to figure out the syntax for the commands, since the documentation is weak or nonexistent.
Also, you can often guess the syntax if you know the corresponding AppleScript command, and I often find myself
reading the DevonThink AppleScript dictionary in order to figure out how different commands works.

The .h file can also be a source of insight. Instructions on how to produce it here:
http://www.fscript.org/documentation/SystemWideScriptingWithFScript/index.htm


Scripting DevonThink with F-script
----------------------------------
Even if you will use Ruby, I recommend learning some rudimentary F-script (http://www.fscript.org/), since F-scripts
"sys browse:" command will bring up a list of all available commands for an object.

Run these commands in the F-script window to bring up the object browser:

> devonthink := SBApplication applicationWithBundleIdentifier: 'com.devon-technologies.thinkpro2'
> sys browse: devonthink


Installation etc.
-----------------
Tested with Ruby 1.8.7 (the version that comes with Snow Leopard)

Requires these gems:

* 'readability' # See https://github.com/iterationlabs/ruby-readability.
* 'open-uri'
* 'log4r'

Please note that 'readability' requires 'nokogiri', which can be tricky to install.


Git access, bugs etc.
---------------------
I have little time to spend on this, so don't expect frequent updates (or, likely, any updates at all).

But feel free to do whatever you want with the code here. Write me at tommy@heltenkelt.se to get access to the
git repository.

/Tommy Sundström