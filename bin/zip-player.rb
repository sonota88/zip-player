#!/usr/bin/ruby -Ku

# $LOAD_PATH << "/home/user/ruby-src/zip-player"

require "rubygems"
require "pp"

def init
  $temp_dir = "temp"
  $app_home = nil

  if File.symlink?($0)
    origin = File.readlink $0
    $app_home = File.join(File.dirname(origin), "..")
  else
    $app_home = File.dirname( File.expand_path( $0 ), ".." )
  end
  $temp_audio_dir = File.join($app_home, "audio_temp")

  if not File.exist? $temp_audio_dir
    Dir.mkdir $temp_audio_dir
  end

  $LOAD_PATH << $app_home

  if not File.exist? $temp_dir
    Dir.mkdir $temp_dir
  end

  $arc_file = ARGV[0]
end


################################################################

#$pl = PlayList.new($app)
init()

$LOAD_PATH << File.join( File.dirname(__FILE__), "..", "lib" )


require "lib/app"
require "lib/playlist"

$pl = PlayList.new($app)
append_archive_file($pl, $arc_file, $temp_dir)

$app = App.new
$app.init_observer

#Tk.mainloop
$app.start
