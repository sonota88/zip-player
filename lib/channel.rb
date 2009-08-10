#!/usr/bin/ruby -Ku

require "yaml"
require "fileutils"
require "pp"

require "utils"
require "anbt-ccl-util"

TEMP_DIR = "temp"

# class Caster
#   attr_accessor :name, :url

#   def initialize(name=nil, url=nil)
#     @name = name if name
#     @url = url if url
#   end
# end

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


# class Artist
#   # essential
#   attr_accessor :name, :type, :website, :tags
#   # artist, composer, arranger, performer, producer

#   def initialize(name=nil, type=nil, website=nil, tags=nil)
#     %w(name type website tags).each {|f|
#       str = %Q!@#{f} = #{f} if #{f}!
#       eval str
#     }
#   end
# end


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
  attr_accessor :label, :date
  attr_accessor :tags, :sys_tags
  attr_accessor :description
  attr_accessor :cast_from, :file_exist_flag
  #  attr_accessor :album_title, :album_id
  attr_accessor :album
  attr_accessor :cast_date
  attr_accessor :volume
  attr_accessor :description
  attr_accessor :fav_point
  
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
  end


  def track_number
    case @track_number
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
    if @licenses == nil || @licenses == [nil]
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
      if File.exist?("#{$PREFS.DIR_CACHE_PODCAST}/#{self.filename()}")
        #"#{$PREFS.DIR_CACHE_PODCAST}/#{self.filename()}"
      elsif File.exist?("#{$PREFS.DIR_CACHE_SUB}/#{self.filename()}")
        #"#{$PREFS.DIR_CACHE_SUB}/#{self.filename()}"
      else
        #raise "could not find #{self.filename()}"
        @file_exist_flag = false
        false
      end
    end
  end

  def html_snipet
    $stderr.puts "@@@@@@@@@@ #{@licenses.inspect} @@@@"
    result = ""
    if @licenses 
      $stderr.puts "@@@@ a"
      if (@licenses - [nil]).empty?
        $stderr.puts "@@@@ 3"
        raise "could not find license info"
        return
      end  
    else
    $stderr.puts "@@@@ b"
      raise "could not find license info"
      return
    end
    
    license = license_links() #.join(" ")
    # $stderr.puts license
    
    
    result = "<p>\n"
    if @album && @album['title']
      result += %Q!"<span class=\"track_title\">#{ @title }</span>" by #{ get_artists() }!
      result += %Q!\n<br />from album "<a href="#{ get_first_release_url() }">#{ album_title_with_id() }</a>" !
    else
      result += %Q!"<a href="#{ get_first_release_url() }"><span class=\"track_title\">#{ @title }</span></a>" by #{ get_artists() }!
    end
    if license
      result += "\n<br />" + license
    end

    result << "\n</p>"

    if not @cast_from.empty?
      result << "\n<p>"
      begin
        result += "\n"
        result += @cast_from.map{|cf| 
          %Q!(via <a href="#{ @cast_from.first['url'] }">#{ @cast_from.first['name'] }</a>)!
        }.join(" &lt;- ")
      rescue => e
        puts "@@@@@@@@@@@@@@@@@@@@@@@@"
        puts e.message, e.backtrace
        pp @cast_from
        puts "<<@@@@@@@@@@@@@@@@@@@@@@@@"
      end
      result += "\n</p>"
    end

    result
  end
end ## Track




def make_sample_yaml
  a = Artist.new()
  a.name = "artist name"
  a.type = "artist"
  
  t = Track.new()
  t.title = "track title"
  t.artist << a
  t.path = "/foo.mp3"
  t.license_url << "http://creativecommons.org/licenses/by-nc-nd/3.0/"
  
  album = TrackList.new()
  album.list << t
  
  a2 = Artist.new()
  a2.name = "artist name 2"
  a2.type = "artist 2"
  
  t2 = Track.new()
  t2.title = "track title: bar"
  t2.artist << a2
  t2.path = "/bar.mp3"
  t2.license_url << "http://creativecommons.org/licenses/by/3.0/"
  
  ch = Channel.new()
  ch.address = "foo@gmail.com"
  ch.dj = "sonota"
  ch.website = "http://twitter.com/sonota"
  ch.base_url = "http://dl.getdropbox.com/u/217014/radio"
  ch.list << album
  ch.list << t2
  
  puts ch.to_yaml
  #puts YAML.dump(program)
end


if __FILE__ == $0
  t = Track.new
  p t
  p t.release_url
  t.release_url = Array.new
  #t.release_url << 6789
  p t.release_url

  #make_test_yaml()
  case ARGV[0]
  when "sample"
    make_sample_yaml
  when "get"
    get_program("http://dl.getdropbox.com/u/217014/radio")
  end
end
