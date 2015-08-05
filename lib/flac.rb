# -*- coding: utf-8 -*-

require "pp"

require "rubygems"
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
  
  # make template track from album info
  template = Track.new
  template.album['title'] = nil
  template.album['id'] = "__id"

  template.release_url = "http://..."
  template.licenses << {"url" => nil, "verify_at" => nil}
  template.path = flac_path
  
  tracks = flac_tracks(flac_path, template)


  tracks.sort_by{|tr| tr.track_number }.each{ |track|
    append_to_playlist(playlist, track)
  }
end


def flac_tracks(flac_path, template)
  cuesheet_text = ` metaflac --show-tag="RAW_CUESHEET" "#{flac_path}" `
  cuesheet_text.sub!( /\A(RAW_CUESHEET=)/, "" )

  cs = CueSheet.new
  cuesheet = cs.parse(cuesheet_text)

  if cuesheet_text.empty?
    STDERR.puts %Q!No cuesheet in FLAC.!
    STDERR.puts %Q!To set cuesheet: metaflac --set-tag="RAW_CUESHEET=`cat foo.cue`" foo.flac!
    exit
  end

  pre_end_sec = nil
  tracks = cuesheet[:tracks].
    sort{ |a,b| b[:index] <=> a[:index] }.
    map{|t|
    temp = Track.new
    temp.path = template.path
    
    temp.track_number = t[:index].to_i
    temp.title = t[:title]
    temp.album["title"] = cuesheet[:album][:title]

    if t[:performer]
      temp.artists << { "name" => t[:performer] }
    else
       if cuesheet[:album][:performer]
         temp.artists << { "name" => cuesheet[:album][:performer] }
       end
    end

    temp.start_sec = if t[:start_sec]
                       mmssxx2sec( t[:start_sec] )
                     else
                       0
                     end
    temp.end_sec = t[:end_sec]

    temp.end_sec = pre_end_sec
    pre_end_sec = temp.start_sec
    
    temp
  }

  tracks
end


class Anbt
  class Flac
    def self.readtag(path, tag)
      cmd = %Q! metaflac --show-tag=#{tag} "#{path}" !
      result = `#{cmd}`.split("\n")
      result = result.map{|x| x.sub(/^#{tag}=(.+)$/i, '\1') }
      result
    end

    
    def self.metadata(path)
      title       = nil
      artist      = nil # not ARTIST*S*
      album       = nil
      tracknumber = nil
      comment     = nil
      
      %w(
        title artist album tracknumber comment
      ).each{|tag|
        eval %Q{ #{tag} = readtag(path, "#{tag}") }
      }

      return {
        "title"        => title[0],
        "artists"      => artist.map{|a|
          { "name" => a }
        },
        "album_title"  => album[0],
        "license"      => {},
        "track_number" => tracknumber[0],
        "comment"      => comment.join("\n")
      }
    end
  end
end
