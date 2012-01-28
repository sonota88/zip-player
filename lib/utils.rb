#!/usr/bin/ruby -Ku
# -*- coding: utf-8 -*-

require "rexml/document"
require "channel"
require "playlist"
require "archive-utils"
require "ya2yaml"

$Track_list_path = "./playlist.yaml"


# abstruct class for YAML, RSS2, ...
class FeedInfo
  attr_accessor :feed_title, :feed_url
  attr_accessor :title_path, :audiofile_path, :artists_path, :release_url_path, :license_url_path
  
  def initialize(yaml)
    yaml.each{|key, val|
      eval %Q! @#{key} = "#{val}" !
    }
  end
end


class Preferences
  attr_accessor :global_volume


  def initialize
    init()
  end


  def init
    @global_volume ||= 80
  end


  def save(pref_path)
    File::open(pref_path, "w") do |f| 
      f.print self.to_yaml
    end
  end
end


def mmssxx2sec(mmssxx)
  /(\d\d):(\d\d):(\d\d?)/ =~ mmssxx
  $1.to_i * 60 + $2.to_i + $3.to_f / 100
end


def sec2mmssxx(sec)
  temp = sec
  sec = sec.to_f
  msec = sec % 1 * 1000
  sec = (sec - msec/1000).round
  min = sec / 60
  sec -= min * 60

  if min >= 100
    raise "Minute dirgit overflow: #{min}"
  end

  "%02d:%02d:%02d" % [min, sec, msec.to_s[0..1].to_i]
end


def sec2hhmmssxx(sec)
  temp = sec
  sec = sec.to_f
  msec = sec % 1 * 1000
  sec = (sec - msec/1000).round
  h   = sec / 3600 ; sec -= h   * 3600
  min = sec / 60   ; sec -= min * 60

  if min >= 100
    raise "Minute dirgit overflow: #{min}"
  end

  "%02d:%02d:%02d.%02d" % [h, min, sec, msec.to_s[0..1].to_i]
end


###############################################################


if $0 == __FILE__
  pp sec2hhmmssxx(0)
  pp sec2hhmmssxx(0.548654152)
  pp sec2hhmmssxx(5)
  pp sec2hhmmssxx(59.5864)
  pp sec2hhmmssxx(60.5864)
  pp sec2hhmmssxx(3599.5864)
  pp sec2hhmmssxx(3600.5864)
  pp sec2hhmmssxx(5999.5864)


  # pp sec2mmssxx(0)
  # pp sec2mmssxx(0.548654152)
  # pp sec2mmssxx(5)
  # pp sec2mmssxx(59.5864)
  # pp sec2mmssxx(60.5864)
  # pp sec2mmssxx(3599.5864)
  # pp sec2mmssxx(3600.5864)
  # pp sec2mmssxx(5999.5864)
  exit

end

