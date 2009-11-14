#!/usr/bin/ruby
# -*- coding: utf-8 -*-

$LOAD_PATH << File.dirname(__FILE__)

require "kconv"
require "pp"

require "rubygems"

require "channel"

require "zipruby"
require "vorbis_comment"
require "id3lib"
require "flacinfo"


# $DIR_CACHE_SUB = "cache_sub"
# $DIR_TEMP = "temp_xxx"

def kconv_u16tou8(str)
  Kconv.kconv( str, Kconv::UTF8, Kconv::UTF16 )
end


def get_id3_frame(path, id)
  #tag = ID3Lib::Tag.new(path)
  tag = ID3Lib::Tag.new(path, ID3Lib::V2)
  tag.each do |frame|
    if frame[:id] == id
      if frame[:textenc] && frame[:text]
        if frame[:textenc] == 1
          frame[:text_u8] = kconv_u16tou8( frame[:text] )
        else
          frame[:text_u8] = frame[:text]
        end
      end
      return frame
    end
  end

  # if failed with ID3Lib::V2 then
  tag = ID3Lib::Tag.new(path, ID3Lib::V1)
  tag.each do |frame|
    if frame[:id] == id
      if frame[:textenc] && frame[:text]
        if frame[:textenc] == 1
          frame[:text_u8] = kconv_u16tou8( frame[:text] )
        else
          frame[:text_u8] = frame[:text]
        end
      end
      return frame
    end
  end

  nil
end


def read_file(arc_path, target)
  # $stderr.puts "xxarc_path = #{arc_path}"
  content = nil

  case File.extname(arc_path)
  when /^\.zip$/i
    Zip::Archive.open(arc_path) do |ar|
      n = ar.num_files # number of entries
      
      n.times do |i|
        entry_name = ar.get_name(i) # get entry name from archive
        next if entry_name != target
        # puts entry_name ## 内部パス
        
        # open entry
        ar.fopen(entry_name) do |f| # or ar.fopen(i) do |f|
          name = f.name           # name of the file
          size = f.size           # size of file (uncompressed)
          comp_size = f.comp_size # size of file (compressed)
          
          content = f.read # read entry content
        end
      end
    end
  end

  return content
end


def file_list_zip(arc_path)
  # STDERR.puts arc_path
  result = []
  Zip::Archive.open(arc_path) do |ar|
    n = ar.num_files # number of entries
    
    n.times do |i|
      result << ar.get_name(i) # get entry name from archive
    end
  end

  return result
end


def entry_exist?(arc_path, entry)
  file_list_zip(arc_path).include? entry
end


def get_tracks_zip(target)
  Zip::Archive.open($filename) do |ar|
    n = ar.num_files # number of entries
    
    n.times do |i|
      entry_name = ar.get_name(i) # get entry name from archive
      next if entry_name != target
      # puts entry_name ## 内部パス
      
      # open entry
      ar.fopen(entry_name) do |f| # or ar.fopen(i) do |f|
        name = f.name           # name of the file
        size = f.size           # size of file (uncompressed)
        comp_size = f.comp_size # size of file (compressed)
        
        content = f.read # read entry content
      end
    end
    
    # Zip::Archive includes Enumerable
    entry_names = ar.map do |f|
      f.name
    end
  end
end


def arc_root_dir(arc_path)
  list = file_list_zip(arc_path).map{ |path|
    path.sub(/^(.+?)\/.*$/, '\1')
  }
  
  if list.all?{|x| list.first == x }
    return list.first
  else
    return nil
  end
end


def arc_cp(arc_path, entry, dest_path)
  $stderr.puts "arc_path: #{arc_path} / dest_path: #{dest_path}" if $DEBUG
  temp_path = nil

  raise "could not find #{arc_path}" if not File.exist?(arc_path)

  Zip::Archive.open( arc_path ) do |ar|
    ar.each do |zf|
      # warn "^^ #{zf.name} ^^^^^^^^^^^^^^^^^^^^^^^"
      next if zf.name != entry
      # puts zf.name

      if zf.directory?
        FileUtils.mkdir_p(zf.name)
      else
        #dirname = File.dirname(zf.name)
        
        if File.directory? dest_path
          FileUtils.mkdir_p( dest_path ) unless File.exist?( dest_dir )
          temp_path = File.join( dest_path, File.basename(zf.name) )
        else
          temp_path = dest_path
        end
        #warn "temp_path = #{temp_path}"
        open( temp_path, 'wb') do |f|
          f << zf.read
        end
      end
    end
  end

  return temp_path
end


def arc_rm(arc_path, entry)
  Zip::Archive.open(arc_path) do |ar|
    n = ar.num_files # number of entries

    n.times do |i|
      entry_name = ar.get_name(i) # get entry name from archive
      ar.fopen(entry_name) do |f| # or ar.fopen(i) do |f|
        if f.name == entry
          f.delete()
        end
      end
    end
  end
end


def arc_mv(arc_path, entry, newentry)
  $stderr.puts "arc_mv"
  arc_cp(arc_path, entry, newentry)
  arc_rm(arc_path, entry)
end


def arc_add_overwrite(arc_path, path, entry)
  puts "arc_path = #{arc_path}"
  puts "path = #{path}"
  puts "entry = #{entry}"

  temp_path = "____gqwhrkahfjk1ahfh2jek7af"

  arc_rm(arc_path, entry)
  FileUtils.cp( path, temp_path )

  Zip::Archive.open(arc_path) {|ar|
    ar.add_file(entry, temp_path)
  }

  FileUtils.rm temp_path
end

def read_metadata(path, local_path)
  ext = File.extname(path)

  title = album_title = nil
  tr_num = nil
  artists = []
  license = {}
  release_url = nil
  pub_date = nil

  case ext
  when ".ogg", ".oga"
    comment = VorbisComment.new(local_path)
    title = comment.fields["TITLE"].join(" / ")
    album_title = comment.fields["ALBUM"].join(" / ") rescue nil
    
    comment.fields["ARTIST"].map{|a|
      artists << {'name'=>a}
    }

    license['url'] = comment.fields["LICENSE"].join(" / ") if comment.fields["LICENSE"]
    license['verify_at'] = comment.fields["VERIFY_AT"].join(" / ") if comment.fields["VERIFY_AT"]
    
    if comment.fields["TRACKNUMBER"]
      tr_num = comment.fields["TRACKNUMBER"].to_s
    end
  when ".mp3", ".MP3"
    frame = get_id3_frame(local_path, :TIT2 )
    title = frame[:text_u8] rescue title = nil

    frame = get_id3_frame(local_path, :TALB)
    album_title = frame[:text_u8] rescue album_title = nil
    
    frame = get_id3_frame(local_path, :TPE1)
    artist_name = begin
                    frame[:text_u8]
                  rescue
                    path
                  end
    artists << {
      'name'=>artist_name
    }

    license['url'] = get_id3_frame(local_path, :WCOP)
    release_url = get_id3_frame(local_path, :WOAF)
    tr_num = get_id3_frame(local_path, :TRCK)[:text_u8] rescue nil
    pub_date = get_id3_frame(local_path, :TYER)[:text] rescue nil
  end
  
  {
    'title'=>title,
    'artists'=>artists,
    'license'=>license,
    'release_url'=>release_url,
    'track_number'=>tr_num,
    'album_title'=>album_title,
    'pub_date'=>pub_date
  }
end


# result << audio2track(temp_audio_path, template, entry)
def audio2track(path, dir_temp, arc_template=nil, entry=nil)
  puts "audio2track()" if $DEBUG
  #puts path, arc_template.path, entry

  if arc_template
    audio_path = File.join(dir_temp, File.basename(path))
  else
    audio_path = File.join($PREFS.DIR_CACHE_SUB, path)
  end

  tr = Track.new
  tag = read_metadata(path, audio_path)

  if arc_template
    tr.path = "%s#%s" % [ arc_template.path, entry ]
    tr.album['id'] = arc_template.album['id'] if arc_template.album['id']
  else
    tr.path = File.join($PREFS.DIR_CACHE_SUB, path)
  end
  tr.title = tag['title']
  tr.album['title'] = tag['album_title']
  tr.cast_date = Time.now
  tr.track_number = tag['track_number'] if tag['track_number']
  tr.licenses << tag['licenses'] if not tag['license'].empty?

  if tag['artists'].empty? && arc_template
    ## template を優先
    tr.artists = arc_template.artists
  else
    ## タグを優先
    tr.artists = tag['artists']
  end

  if arc_template
    tr.release_url = arc_template.release_url
    tr.album['title'] = arc_template.album['title']

    if arc_template.licenses
      tr.licenses = arc_template.licenses
    elsif arc_template.license_url
      tr.license_url = arc_template.license_url
    end
  end

  #puts "RRRRRRRRRRRRRRRRRRRRRRRRRR", tr.path if $VERBOSE

  tr
end


def arc_get_tracks(arc_path, template, dir_temp)
  $stderr.puts "++++++++++ #{arc_path}" if $VERBOSE
  #local_path = File.join( $PREFS.DIR_CACHE_SUB, arc_path )

  result = []
  case File.extname(arc_path)
  when /^\.zip$/i
    #list = file_list_zip(local_path)
    list = file_list_zip(arc_path).
      select{|e| /^__MACOSX\// !~ e }
    
    count = 1
    list.each do |entry|
      ext = File.extname(entry)
      next unless /^\.(ogg|oga|flac|mp3)$/ =~ ext

      ## 一時ファイル取り出す
      #temp_audio_path = arc_cp(local_path, entry, File.join($PREFS.DIR_TEMP, "000#{ext}") )
      temp_audio_path = arc_cp(arc_path,
                               entry,
                               File.join(dir_temp, "000#{ext}")
                               )
      
      ## タグ読む
      begin
        result << audio2track(temp_audio_path, dir_temp, template, entry)
      rescue => e
        puts e.message, e.backtrace
        puts temp_audio_path, entry, arc_path
        exit 1
      end
      
      FileUtils.rm(temp_audio_path)

      $stderr.print "t#{count} "
      count += 1
    end
    $stderr.print "\n"
  when /^\.flac$/i
    temp_cuesheet_path = File.join($temp_dir, "__000.cue")
    system %Q! metaflac --export-cuesheet-to="#{temp_cuesheet_path}" "#{arc_path}" !
    text = File.read(temp_cuesheet_path)

    result = parse_flac_cuesheet(text, template)

    $stderr.print "\n"
  else
    raise "File type not recongnized: #{arc_path} ."
  end
  #puts result.to_yaml

  return result
end


def append_to_playlist(playlist, tr)
  # pp 6666699999, [].include?( tr.to_ezhash),
  # playlist.map{|e| e.to_ezhash}.include?( tr.to_ezhash ),
  # playlist.map{|e| e.to_ezhash}
  
  #if not playlist.map{|e| e.to_ezhash}.include?( tr.to_ezhash )
    playlist << tr
  #end
end


def append_archive_file(playlist,
                        arc_path, # basename
                        temp_dir
                        )
  warn "Archive: #{arc_path}"
  
  list = file_list_zip(arc_path)

  # info 取得
  info = nil
  list.each {|entry|
    if /info.yaml$/ =~ entry
      puts "info.yaml exist."
      temp = read_file(arc_path, entry)
      info = YAML.load( temp )
      pp info if $DEBUG
    end
  }

  if $DEBUG
    pp info
  end

  # テンプレートtrack作成
  template = Track.new
  if info
    if info['album']
      template.album['title'] = if info['album']['title']
                                  info['album']['title']
                                else
                                  info['album_title']
                                end
      template.album['id'] = if info['album']['id']
                               info['album']['id']
                             else
                               info['album_id']
                             end
    end
    pp template

    template.release_url = info["release_url"] if info["release_url"]

    if info["licenses"]
      template.licenses = info["licenses"]
    elsif info["license_url"]
      $stderr.puts "license_url is obsolete!"
      #template.license_url = info["license_url"]
    end

    template.artists = info["artists"] if info["artists"]
  end
  template.path = arc_path
  
  tracks = arc_get_tracks(arc_path, template, temp_dir)

  tracks.sort_by{|tr| tr.track_number }.each do |track|
    append_to_playlist(playlist, track)
  end
end


def append_single_file(playlist, path)
  STDERR.puts "F: #{path}"
  #track = get_track(path)
  track = audio2track(path)
  #  pp track

  append_to_playlist(playlist, track)
end




if $0 == __FILE__
#   file = ARGV[0]
#   #target = ARGV[1]

#   playlist = [123]
#   case File.extname(file)
#   when /^\.(zip)$/
#     append_archive_file(playlist, file)
#   else
#     append_single_file(playlist, file)
#   end

#   puts playlist.to_yaml


 #  tag = read_metadata("Yoma_Aoki__02 - girl age ガールエージ.mp3",
#                       "test/sample/Yoma_Aoki__02 - girl age ガールエージ.mp3")

  path = ARGV[0]
#   tag = ID3Lib::Tag.new(path, ID3Lib::V1)
#   pp tag; puts "====================================="
#   tag = ID3Lib::Tag.new(path, ID3Lib::V2)
#   pp tag; puts "====================================="
  tag = ID3Lib::Tag.new(path).each{|t|
    pp t; puts "====================================="
  }

  tag = read_metadata(ARGV[0], ARGV[0])
  pp tag
end
