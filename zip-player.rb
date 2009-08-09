#!/usr/bin/ruby -Ku

def init
  $temp_dir = "temp"

  if File.symlink?($0)
    origin = File.readlink $0
    $app_home = File.dirname(origin)
    app_libdir = File.join($app_home, "lib")
    puts app_libdir
  else
    $app_home = File.dirname( File.expand_path( $0 ) )
    app_libdir = File.join( $app_home, "lib" )
  end
  puts app_libdir
  $temp_audio_dir = File.join($app_home, "audio_temp")

  if not File.exist? $temp_audio_dir
    Dir.mkdir $temp_audio_dir
  end

  $LOAD_PATH << $app_home
  $LOAD_PATH << app_libdir

  if not File.exist? $temp_dir
    Dir.mkdir $temp_dir
  end

  $arc_file = ARGV[0]
end


################################################################

#$pl = PlayList.new($app)
init()

require "app"
require "playlist"

$pl = PlayList.new($app)
append_archive_file($pl, $arc_file, $temp_dir)

$app = App.new
$app.init_observer

#Tk.mainloop
$app.start
