#!/usr/bin/env ruby

require "rubygems"
require "pp"
require "fileutils"

$temp_dir = nil

def init
  $temp_dir = "temp"
  $app_home = nil

  if File.symlink?($0)
    origin = File.readlink $0
    $app_home = File.dirname(origin)
  else
    $app_home = File.dirname( File.expand_path($0) )
  end
  $LOAD_PATH.unshift File.join($app_home, "lib")

  $temp_dir = File.join($app_home, "temp")

  if not File.exist? $temp_dir
    Dir.mkdir $temp_dir
  end

  ## proc arc file
  $arc_file = ARGV[0]
end

def _todo msg
  $stderr.puts "[ TODO] #{msg}"
end

def _debug *msgs
  $stderr.puts "[DEBUG] " + msgs.join(", ")
end

def _debug_pp *msgs
  $stderr.puts "[DEBUG] " + msgs.map(&:pretty_inspect).join(", ")
end

################################################################

init()

require "gui-tk"
require "playlist"

$app = App.new
$app.init_observer

$app.start($arc_file, $temp_dir)
