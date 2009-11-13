#!/usr/bin/ruby -Ku

require "yaml"
require "fileutils"
require "pp"

require "utils"
require "anbt-ccl-util"

TEMP_DIR = "temp"


class Channel
  # essential
  attr_accessor :title, :list, :dj, :address, :base_url
  # not essential
  attr_accessor :website
  attr_accessor :description
  attr_accessor :tags
  
  def initialize
    @list = []
    @tags = []
  end
end


class PlayLists
  include Enumerable

  attr_accessor :h, :current_pl_name

  def initialize
    @current_pl_name = 'default'
    @h = {@current_pl_name => PlayList.new($app)}
  end

  def current
    @h[@current_pl_name]
  end

  def each
    @h.each {|k,v|
      yield(k, v)
    }
  end

  def each_track
    self.current.each{|t|
      yield(t)
    }
  end

  def current_track
    self.current.current_track
  end

  def current_index
    self.current.current_index
  end
  def current_index=(x)
    self.current.current_index = x
  end
end




class Track
  # essential
  attr_accessor :title, :artists, :path
  attr_accessor :release_url, :licenses
  #attr_accessor :license_url ## obsolete

  # not essential
  attr_accessor :label, :date, :track_number
  attr_accessor :tags, :sys_tags
  attr_accessor :description
  attr_accessor :cast_from, :file_exist_flag
  #  attr_accessor :album_title, :album_id
  attr_accessor :album
  attr_accessor :cast_date
  attr_accessor :volume
  attr_accessor :description
  attr_accessor :fav_point
  attr_accessor :start_sec, :end_sec
  
  def initialize
    @artists = []
    #    @license_url = []
    @licenses = []
    @release_url = []
    # @recast_from = []
    @tags = []
    @sys_tags = []
    @track_number = nil
    @album = {}
    @fav_point = 0
    @cast_from = []
    @description = ""
    @donation_info_url = nil
    @start_sec, @end_sec = nil, nil
  end


  def track_number
    case @track_number.to_s
    when /\A(\d+)\/(\d+)\z/
      return $1.to_i
    when /\d+/
      return $&.to_i
    else
      return 0
    end
  end


  def track_number=(x)
    @track_number = x
  end


#   def import(obj)
#     @artists = obj.artists.map{|a| a }
#     @title = obj.title
#     @path = obj.path
#   end

  #def release_url
  def get_release_url
    if @release_url && !(@release_url.select{|e| e }.empty?)
      @release_url.first
    else
      if @licenses && !(@licenses.empty?)
        @licenses.first["verify_at"]
      else
        nil
      end
    end
  end
  
  def filename
    return File.basename(@path)
  end
  
  def license_abbr
    if @licenses == nil ||
        @licenses == [nil] ||
        @licenses.first["verify_at"] == nil
      return nil
    end

    @licenses.map {|l|
      CCL.url2abbr(l["url"])
    }.join(" / ")
  end
  
  def license_links
#     temp = @license_url.map {|url| 
#       %Q!<a href="%s">%s</a>! % [ url, CCL.url2abbr(url) ] 
#     }
    temp = %Q!<a href="%s">%s</a>! % [ @licenses.first['url'], CCL.url2abbr(@licenses.first['url']) ] 
    #return temp.join(" / ")
    temp
  end
  
  def get_artists
    if !(@artists.empty?) || @artists != nil
      result = @artists.map {|a|
        begin
          a['name']
          #a.name
        rescue
          '?'
        end
      }.join(", ")
      if not result.empty? ; result
      else                 ; nil
      end
    else
      return nil
    end
  end
  
  def get_first_release_url
    if not @release_url.empty?
      @release_url.first
    else
      if not @licenses.empty?
        @licenses.first['verify_at']
      else
        nil
      end
    end
    
    #return @release_url.first
  end
  
  def album_title_with_id
    unless @album
      @album = nil #"(not in album)" 
      return nil
    end

    str = @album['title']
    if @album['id']
      str += " [#{@album['id']}]"
    else
      @album['id'] = nil
    end
    return str
  end


  def to_ezhash
    @album_title ||= nil if $DEBUG
    #"#{get_artists()} #{@title} #{@album_title} #{@path}"
    "#{get_artists()} #{@title} #{@album_title} #{@path}"
  end


  def ==(other)
    if other.is_a?(Track)
      self.to_ezhash == other.to_ezhash
    else
      false
    end
  end


  def is_archive?
    if /^((.+)\.(zip))\#(.+)/i =~ @path
      return $1
    else
      return false
    end
  end


  def basename
    if is_archive?
      return is_archive?
    else
      File.basename @path
    end
  end


  def arc_file_entry
    if self.is_archive?
      /^(.+?)\#(.+)$/ =~ self.path
      return $1, $2
    else
      return false
    end
  end

  
  def local_path
    if self.is_archive?
      arc_file, entry = self.arc_file_entry()
      #arc_path = File.join( $PREFS.DIR_CACHE_SUB, arc_file)
      arc_path = arc_file
      filenm = File.basename(entry)
      
      #"#{$PREFS.DIR_ARC_TEMP}/#{filenm}"
      "#{filenm}"
    else
      @path
    end
  end
end ## Track


if __FILE__ == $0
  ;
end
