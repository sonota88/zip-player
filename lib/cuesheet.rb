#!/usr/bin/ruby
# -*- coding: utf-8 -*-

## 文字コード判別用テキスト

require "pp"

class CueSheet
  attr_accessor :album, :tracks

  def initialize
    @album = {}
    @tracks = []
  end


  def parse_tracks(lines)
    temp = nil

    loop {
      line = lines[0]
      #pp line

      case line
      when /  TRACK (\d\d) AUDIO/
        @tracks << temp if temp != nil
        temp = {}
        #temp[:index] = []
        
        temp[:track_number] = $1.to_i
      when /    TITLE "(.+)"/
        temp[:title] = $1
      when /    PERFORMER "(.+)"/
        temp[:performer] = $1
      when /    INDEX (\d\d) (\d\d:\d\d:\d\d)/
        #puts $1.to_i, $2
        temp[:start_sec] = $2
      end


      lines.delete_at(0)
      break if lines.empty?
    }
    @tracks << temp
  end


  def parse(src)
    src.gsub! /\r\n/, "\n"
    lines = src.split("\n")

    count = 0
    while line = lines[0]
      count == 0 ? count = 0 : count += 1
      
      case line
      when /^REM /
        ; # comment
      when /^PERFORMER "(.+)"/
        @album[:performer] = $1
      when /^TITLE "(.+)"/
        @album[:title] = $1
      when /^FILE "(.+)" WAVE/
        @album[:file] = $1
      when /\s+TRACK \d+ AUDIO/
        break
      end

      lines.delete_at(0)
      break if lines.empty?
    end

    parse_tracks(lines)
  end

  def each_track
    @track.each{|t|
      yield t
    }
  end

  def disp
    pp @album
    pp @tracks
  end
end

if $0 == __FILE__
  src = ""
  if ARGV[0] == nil
    while line = gets
      src << line
    end
  else
    src = File.read(ARGV[0])
  end


  cs = CueSheet.new
  cs.parse(src)

  cs.disp
end
