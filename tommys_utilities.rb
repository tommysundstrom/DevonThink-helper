#
#  tommys_utilities.rb
#  ItunesFeeder
#
#  Created by Tommy Sundstršm on 18/3-09.
#  Copyright (c) 2009 Helt Enkelt ab. All rights reserved.
#

module Tommys_utilities

  def Tommys_utilities.last_line_of_file(path)
    f = File.new(path, 'r')
    f.each {|line| $current_line_with_long_complex_name_since_i_cant_figure_how_to_do_it_without_using_a_global = line} # Reads and forgets every line, but remembers the last one.
    f.close
    return $current_line_with_long_complex_name_since_i_cant_figure_how_to_do_it_without_using_a_global
  end

end
