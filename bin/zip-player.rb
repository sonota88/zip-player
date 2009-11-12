#!/usr/bin/ruby -Ku

# $LOAD_PATH << "/home/user/ruby-src/zip-player"

require "rubygems"
require "pp"

$temp_dir = nil

def init
  $temp_dir = "temp"
  $app_home = nil

  if File.symlink?($0)
    origin = File.readlink $0
    $app_home = File.join( File.dirname(origin), "..")
  else
    $app_home = File.join( File.dirname($0), ".." )
  end
  $LOAD_PATH << $app_home

  $temp_dir = File.join($app_home, "temp")

  if not File.exist? $temp_dir
    Dir.mkdir $temp_dir
  end

  $arc_file = ARGV[0]
end


def append_album(pl, album_path, temp_dir)
  case album_path
  when /\.zip$/i
    append_archive_file(pl, album_path, temp_dir)
  when /\.flac$/i
    append_flac(pl, album_path, temp_dir)
  else
    $stderr.puts "File type not recognizable."
    exit
  end
end

################################################################


# $pl = PlayList.new($app)


init()
# pp $app_home, $temp_dir, $LOAD_PATH ; exit

require "lib/gui-tk"
require "lib/playlist"

$pl = PlayList.new($app)
append_album($pl, $arc_file, $temp_dir)
#pp $pl ; exit

$app = App.new
$app.init_observer

#Tk.mainloop
$app.start
