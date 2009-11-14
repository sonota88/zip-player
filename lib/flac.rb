#!/usr/bin/ruby -Ku
# -*- coding: utf-8 -*-

require "pp"

require "rubygems"
require "flacinfo"
require "cuesheet"

class FlacInfo
  def tag(tagname)
    values = []
    self.comment.each{|str|
      if /^#{tagname}=(.+)$/ =~ str
        values << $1
      end
    }
    
    values
  end
end


def append_flac(playlist, flac_path, temp_dir)
  # $VERBOSE = true
  warn "Flac: #{flac_path}"
  
  fi = FlacInfo.new flac_path
  #pp fi.comment, fi.tag("ARTIST") ; exit

  temp_cue_file = File.join( $temp_dir, "__000.cue" )
  system %Q! metaflac --export-cuesheet-to="#{temp_cue_file}" "#{flac_path}" !
  cuesheet_text = File.read(temp_cue_file)
  cuesheet = CueSheet.new.parse(cuesheet_text)

  # make template track from album info
  template = Track.new
  template.album['title'] = fi.tag("TITLE") #"__ttttttt"
  template.album['id'] = "__id"

  template.release_url = "http://..."
  template.licenses << {"url" => nil, "verify_at" => nil}
  template.artists << {"name" => fi.tag("ARTIST").join(" / ")}
  template.path = flac_path
  
  tracks = flac_get_tracks(flac_path, template, temp_dir)

  tracks.each{|t|
    temp = cuesheet.select{ |c|
      c[:track_number] == t.track_number
    }.first
    t.title = temp[:title] if temp[:title]
    
      t.start_sec = if temp[:start_sec]
                       mmssxx2sec( temp[:start_sec] )
                     else
                       0
                     end
  }

  tracks.sort_by{|tr| tr.track_number }.each{ |track|
    append_to_playlist(playlist, track)
  }
end


def flac_get_tracks(flac_path, template, temp_dir)
  arc_get_tracks(flac_path, template, temp_dir)
end


def parse_flac_cuesheet(text, template)
  temp_tracks = nil
  buf = {:index => nil, :start_sec => nil, :end_sec => nil}
  
  text.each_line{|line|
    case line
    when /^  TRACK (\d\d) AUDIO/
      temp_tracks == nil ? temp_tracks = [] : temp_tracks << buf
      buf = {:index => nil, :start_sec => nil, :end_sec => nil}

      buf[:index] = $1.to_i
    when /^    INDEX (\d\d) (\d\d):(\d\d):(\d\d)/ 
      min, sec, msec = $2.to_i, $3.to_i, $4.to_i
      buf[:start_sec] = min * 60 + sec + msec / 1000.0
      #buf[:end_sec] = buf[:start_sec] + 60
      buf[:end_sec] = nil
    end
  }

  temp_tracks.map!{|t|
    temp = nil
    temp = template.dup
    
    temp.track_number = t[:index].to_i
    temp.title = "%s (track-%s)" % [temp.album["title"], temp.track_number]
    temp.start_sec = t[:start_sec]
    temp.end_sec = t[:end_sec]

    temp
  }

  pre_end_sec = nil
  temp_tracks.
    sort{ |a,b| b.track_number <=> a.track_number }.
    each{ |t|
    t.end_sec = pre_end_sec
    pre_end_sec = t.start_sec
  }

  temp_tracks
end
