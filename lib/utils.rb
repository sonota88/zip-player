#!/usr/bin/ruby -Ku
# -*- coding: utf-8 -*-

require "rexml/document"
require "channel"
require "playlist"
require "archive-utils"
require "ya2yaml"

PREF_FILE = "prefs.yaml"

FILE_RSS2 = 0

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
  attr_accessor :CHANNEL_LIST_PATH
  attr_accessor :DIR_CACHE_PODCAST, :DIR_CACHE_SUB, :DIR_CACHE_SUB_ARCHIVE, :DIR_TRASH
  attr_accessor :DIR_TEMP
  attr_accessor :DIR_ARC_TEMP
  attr_accessor :DIR_RECAST, :DIR_RECAST_REMOTE_ROOT
  attr_accessor :fav_play_threshold, :editor, :ext_tag_editor
  attr_accessor :recent_tags
  attr_accessor :podcast_limit_MB

  def init
    @CHANNEL_LIST_PATH      ||= "channel_list.txt"
    @DIR_CACHE_PODCAST      ||= "cache_podcast"
    @DIR_CACHE_SUB          ||= "cache_sub"         
    @DIR_CACHE_SUB_ARCHIVE  ||= "__archive__"
    @DIR_TRASH              ||= "trash"
    @DIR_TEMP               ||= "temp_xxx"
    @DIR_ARC_TEMP           ||= "temp/archive"
    @DIR_RECAST             ||= nil
    @DIR_RECAST_REMOTE_ROOT ||= nil
    @fav_play_threshold     ||= -5
    @current_pl             ||= 'default'
    @podcast_limit_MB       ||= 10000
  end

  def save
    open(PREF_FILE, "w") do |f| 
      f.print self.to_yaml
    end
  end

  def current_tag
    @recent_tags.first
  end
end


def init
  if File.exist?(PREF_FILE)
    $PREFS = YAML.load( File.read(PREF_FILE) )
    $PREFS.init
  else
    $PREFS = Preferences.new
  end
  #y $PREFS ; exit


  unless File.exist?($PREFS.DIR_CACHE_PODCAST)
    Dir.mkdir(       $PREFS.DIR_CACHE_PODCAST)
  end

  unless File.exist?($PREFS.DIR_CACHE_SUB)
    Dir.mkdir(       $PREFS.DIR_CACHE_SUB)
  end

  unless File.exist?( File.join($PREFS.DIR_CACHE_SUB, $PREFS.DIR_CACHE_SUB_ARCHIVE) )
    Dir.mkdir(        File.join($PREFS.DIR_CACHE_SUB, $PREFS.DIR_CACHE_SUB_ARCHIVE) )
  end

  unless File.exist?(TEMP_DIR)
    Dir.mkdir(TEMP_DIR)
  end

  FileUtils.rm_rf $PREFS.DIR_ARC_TEMP
  Dir.mkdir( $PREFS.DIR_ARC_TEMP )

  ##--------fesafewaあいうえお
  if ARGV[0] == "-d"
    Thread.abort_on_exception = true
  end

  $Recast_track_list = Channel.new()

  first_dl_thread = nil

  if(File.exist?($Track_list_path))
    $pls = YAML.load(File.read($Track_list_path))
  else
    $pls = PlayLists.new()
  end

  scan_cache_sub($pls.current)
  puts "########"
  puts $pls.size rescue nil
  pp $pls.tags rescue nil
  puts "<<########"
  #exit
end


def scan_cache_sub(playlist)
  # already exist in playlist
  arc_list = playlist.map{|tr|
    if tr.is_archive?
      arcfile, entry = tr.arc_file_entry
      arcfile
    else
      nil
    end
  }.compact.uniq
  
  Dir.open($PREFS.DIR_CACHE_SUB).each do |path|
    next if path == "."
    next if path == ".."
    #puts path

    case File.extname(path)
    when ".mp3", ".MP3", ".ogg", ".oga", ".flac"
      append_single_file(playlist, path )
    when /\.(zip)/i
      if not arc_list.include?(path)
        append_archive_file(playlist, path)
      end
    else
      ;
    end
  end
end


def uniq_track(arr)
  result = PlayList.new($app)

  if arr == nil
    return PlayList.new($app)
  end

  for a in 0..(arr.size-2)
    is_same = false
    for b in (a+1)..(arr.size-1)
      #      puts "#{a}-#{b}: "
      is_same =true if arr[a].to_ezhash == arr[b].to_ezhash
    end
    result << arr[a] if not is_same
  end
  result << arr[-1]
  return result
end


def file_type(path)
  src = File.read path
  # puts src
  
  begin
    feed = REXML::Document.new(src)
    rss_version = feed.elements["rss"].attributes["version"]
    case rss_version
    when "2.0"
      # puts "FILE_RSS2"
      return FILE_RSS2
    end
  rescue
    ;
  end

  return "unknown"
end


def esc_path(str)
  return str.gsub(/[ \/\(\)\[\]]/, "_")
end


def fetch_feed(url, local_path)
  $stderr.puts "fetch_feed(url, local_path)"
  cmd = %Q!wget --no-verbose "#{url}" -O "#{local_path}" !
  #  cmd = %Q!curl --remote-name #{url} --output "#{local_path}" !
  $stderr.puts cmd
  system cmd
  #result = `#{cmd}`
  if $?.to_i == 0
    src = File.read(local_path)
    return src
  else
    $stderr.puts "failed to fetch feed (#{url})"
    return nil
  end
end


def rss2item2track(i, feed_info, channel)
  t = Track.new()

  if i.elements["link"].text
    t.release_url.push i.elements["link"].text
  elsif feed_info.feed_url
    t.release_url << feed_info.feed_url
  else
    raise "must not happen."
  end
  
  t.title = i.elements['title'].text
  
  #      t.cast_from << [channel.title, channel_url]
  t.cast_from << { "name"=>channel.title, "url"=> feed_info.feed_url }
  
#  aa = Artist.new()
  aa = {}
  if feed_info.artists_path 
    str = %Q! i.elements#{feed_info.artists_path} !
    aa['name'] = eval( str )
  else
    aa['name'] = if i.elements['dc:creator'] != nil
                   i.elements['dc:creator'].text
                 elsif i.elements['itunes:author'] != nil
                   i.elements['itunes:author'].text
                 elsif i.elements['author'] != nil
                   i.elements['author'].text
                 else
                   "?"
                 end
  end
  t.artists << aa
  
  begin
    if not i.elements["enclosure"]
      return nil
    end

    i.each_element("enclosure") {|e|
      mimetypes = %w(
            audio/ogg
            audio/mpeg
            x-audio/m4a
            application/octet-stream
          ).join("|")
      if not /^(#{mimetypes})$/ =~ e.attributes["type"]
        # 入ってないフィードもある……
        # next
      end
      t.path = e.attributes['url']
    }
  rescue
    next
  end
  
  begin
    #     $stderr.puts "iiiiiiiiiiiiiiiiiiii"
    #     $stderr.puts i.elements['creativeCommons:license'].text
    #     $stderr.puts i.elements['cc:license'].text
    #     $stderr.puts "<<iiiiiiiiiiiiiiiiiiii"

    if i.elements['creativeCommons:license'] && i.elements['creativeCommons:license'].text != nil
      #t.license_url << i.elements['creativeCommons:license'].text
      t.licenses << { "url" => i.elements['creativeCommons:license'].text }
    elsif i.elements['cc:license'].text && i.elements['cc:license'].text != nil
      #t.license_url << i.elements['cc:license'].text
      t.licenses << { "url" => i.elements['cc:license'].text }
    else
      t.license << nil
    end
  rescue => e
    # $stderr.puts e.message, e.backtrace
    $stderr.puts "! could not find license info. (#{t.title})"
  end

  #pp t, "ttttttttttttttttttttttttttttttttttttttttttttttttttttttt"
  t
end


def read_feed(feed_info)
  $stderr.puts "@@@@@@@@ read_feed: #{feed_info.feed_url} @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
  channel_url = feed_info.feed_url
  temp_channel_file = "%s/%s" % [ TEMP_DIR, esc_path(feed_info.feed_title) ]

  feed_fetch_interval_hour = 2
  
  if File.exist?(temp_channel_file) 
    $stderr.puts "Last feed fetch: %s" \
    % File.stat(temp_channel_file).mtime.strftime("%Y-%m-%d %H:%M")

    if Time.now - File.stat(temp_channel_file).mtime > feed_fetch_interval_hour * 60 * 60
      src = fetch_feed(channel_url, temp_channel_file)
    else
      $stderr.puts "Not enough time (#{feed_fetch_interval_hour}h) passed since last fetch."
      src = File.read temp_channel_file
    end
    #elsif not File.exist?(temp_channel_file)
  else
    src = fetch_feed(channel_url, temp_channel_file)
  end
  
  if src == nil
    $stderr.puts "Feed src is nill."
    return nil
  end

  case file_type(temp_channel_file)
  when FILE_RSS2
    $stderr.puts "RSS 2.0"
    channel = Channel.new()
    src = File.read(temp_channel_file)
    feed = REXML::Document.new(src)
    channel.dj = feed.root.elements["channel"].elements["title"].text
    channel.title = feed.root.elements["channel"].elements["title"].text

    feed.root.elements["channel"].each_element("item"){|i|
      t = rss2item2track(i, feed_info, channel)
      channel.list << t
    }
    # $stderr.puts "RSS 2.0 end"
  else
    $stderr.puts "feed type: YAML or invalid"
    src = File.read(temp_channel_file)
    begin
      channel = YAML.load(src)
    rescue
      raise
    end
    
    channel.list.each{|elem|
      unless elem.cast_from
        elem.cast_from = []
      end
      elem.path = "#{channel.base_url}#{elem.path}"
      elem.cast_from << [channel.title, channel.base_url]
    }
  end
  
  #pp program
  
  #puts "@p@p@p@p@p@p@p@p@p@p@p@p@p@p@p@p@p@p@p@p@p@p@p@p@p" ; exit
  p "<<channel"
  return channel
end


def read_channel_list
  $stderr.puts "read_channel_list()"
  temp = []
  pp $PREFS.CHANNEL_LIST_PATH
  begin
    yaml = YAML.load( File.read( $PREFS.CHANNEL_LIST_PATH) )
  rescue => e
    $stderr.puts e.message, e.backtrace
    $stderr.puts "failed to load #{$PREFS.CHANNEL_LIST_PATH}."
    exit
  end
  pp yaml
  
  $stderr.puts "ddddddddddddddddddddd"
  yaml.each{|item|
    $stderr.puts  item.class
    feed = FeedInfo.new(item)
    pp feed
    temp << feed
  }
  $stderr.puts "read_channel_list() end"
  return temp
end


def get_dl_track_list(feed_list)
  $stderr.puts "get_dl_track_list(#{feed_list})"
  $stderr.puts "size of feed_list: #{feed_list.size})"
  ch_list = []

  feed_list.each do |feed_info|
    $stderr.puts feed_info.feed_title
    $stderr.puts feed_info.feed_url
    begin
      ch = read_feed(feed_info)
      #puts "ch.list size: #{ch.list.size}"
    rescue => e
      $stderr.puts e.message, e.backtrace
      next
    end

    next if ch == nil

    ch.list.reverse!
    ch_list << ch
    puts ch_list.size
  end
  puts "list of channel size: #{ch_list.size}"
  
  tracks = []
  item_index = 0
  loop{
    track_exist = []
#     for ch_index in 0..(ch_list.size - 1) do
#       puts "## #{ch_index} ###############################"
#       ch = ch_list[ch_index]
#       track_exist << ch.list[item_index] ## track を移し替え
#       next if ch.list[item_index] == nil

#       tracks << ch.list[item_index]
#     end
    ch_list.each_with_index {|ch, i|
      #print " (item:#{item_index} ch:#{i}) "
      track_exist << ch.list[item_index] ## track を移し替え
      next if ch.list[item_index] == nil # to next channel

      tracks << ch.list[item_index]
    }
    #pp track_exist.compact

    if track_exist.compact == []
      puts "ch-track scan end. #{tracks.size}"
      return tracks 
    end

    item_index += 1
  }
end


def get_cache_filename(elem)
  #p "get_cache_filename(#{elem})"
  ext = case elem.path
        when /\.(ogg|oga)$/i ; "oga"
        when /\.flac$/i ; "flac"
        when /\.mp3$/i ; "mp3"
        when /\.m4a$/i ; "m4a"
        else ; "unknown"
        end
  #p "ext: #{ext}"
  p "elem.get_artists(): #{elem.get_artists()}"
  p "elem.title: #{elem.title}"
  #p "elem.class: #{elem.class}"
  #p "elem.class == Track: #{elem.class == Track}"

  case elem.class.to_s
  when "Track"
    result = "%s__%s.%s" % [elem.get_artists(), elem.title, ext]
    result.gsub!( /(
   \s+ | ^\.
 | \? | \! | \& | \# | \@
 | \/ 
 | \[ | \]
 | \( | \)
 | \: | \;
 | \" | \' | \`
)/x, "_")
    p "result: #{result}"
    return result
  else
    ;
  end
end


def download(first_wait_sec, wait_interval_sec, num_files_to_dl = nil)
  $stderr.puts "download() first_wait_sec=#{first_wait_sec} / wait_interval_sec=#{wait_interval_sec}"
  sleep first_wait_sec
  
  $feed_list = read_channel_list()
  puts "reading #{$feed_list.size} feeds."

  dl_track_list = get_dl_track_list($feed_list)
  puts "dl_track_list.size: #{dl_track_list.size}"

  at_exit {
    Process.kill( "KILL", $pid_dl_audio) if $pid_dl_audio
  }
  
  count = 0
  # each track
  dl_track_list.each do |elem|
    pp "** tracks to dl: #{count} / #{dl_track_list.size} ********************************************"

    #if $pls.map{|item| item.to_ezhash }.include?(elem.to_ezhash)
    if $pls.include?(elem)
      puts "HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH"
      count += 1
      next
    end


    if elem.class == Track
      # $stderr.puts elem.inspect ; exit
      puts "cast from: #{elem.cast_from}"
      
      /.*\/(.+?)$/ =~ elem.path
      filename = $1
      escaped_filename = get_cache_filename(elem)
      local_path = %Q!#{$PREFS.DIR_CACHE_PODCAST}/#{escaped_filename}!
      
      print %Q!title: #{elem.title} __#{local_path}__!
      if File.exist?(local_path)
        puts " ... exists"
        elem.path = escaped_filename
        $pls.current.append_track(elem)
      else
        puts " ... does not exist"
        temp_path = "#{TEMP_DIR}/000.track"
        begin
          $pid_dl_audio = nil
          $pid_dl_audio = fork {
            exec( "wget", 
                  elem.path,
                  "-O", temp_path,
                  "--tries=2", 
                  "--timeout=60" 
                  )
          }
          Process.waitpid2($pid_dl_audio)
          $pid_dl_audio = nil
          
          if File.stat(temp_path).size == 0
            p "empty file. maybe failed to fetch."
            next
          end
          #sleep 10
          FileUtils.mv(temp_path, local_path)
          $stderr.puts local_path
          elem.path = escaped_filename
          
          $pls.current.append_track(elem)

          sleep wait_interval_sec 
        rescue => e
          puts e.message, e.backtrace
          puts %Q!failed to download #{elem.path}!
          if File.exist? temp_path
            FileUtils.rm(temp_path)
          end
        end
      end
    else
      ;
    end
    
    #save_playlist()
    count += 1
    #num_files_to_dl = 20
    if num_files_to_dl != nil && count >= num_files_to_dl
      return
    end
  end
end



###############################################################

if $0 == __FILE__

  if true
    ## find license
    feed_path = ARGV[0]

    feed = REXML::Document.new(File.read(feed_path))
    ch = Channel.new
    ch.dj = feed.root.elements["channel"].elements["title"].text
    ch.title = feed.root.elements["channel"].elements["title"].text

    feed.root.elements["channel"].each_element("item") do |i|
      p i.elements["creativeCommons:license"].text
      sleep 1
    end
  end

  if false
    ## find link to audio file
    feed_path = ARGV[0]

    feed = REXML::Document.new(File.read(feed_path))
    ch = Channel.new
    ch.dj = feed.root.elements["channel"].elements["title"].text
    ch.title = feed.root.elements["channel"].elements["title"].text

    feed.root.elements["channel"].each_element("item") do |i|

      
      i.each_element("enclosure") do |e|
        next if e.attributes["type"] == "image/jpeg"
        p e
      end
      exit
    end
  end

  if false
    feed_path = ARGV[0]

yaml = <<EOB
- ch_title: "Curt Siffert's Piano Musings"
  url: "http://feeds.feedburner.com/UweHermannsMusicPodcast"
  artists_path: "['dc:creator'].text"
  license_url: 
EOB
    
    feed_info_list = YAML.load(yaml)
    #pp feed_info_list
    feed_info_list.each{|ci|
      temp = FeedInfo.new(ci)
      pp temp.feed_url
      get_channel(temp)
    }
  end

  if false
    download()
  end
end


def save_playlist

  $stderr.puts "write: $pls.current_index = #{$pls.current_index}"
  temp_pls = $pls.dup

  temp_pls.each {|k,v|
    p "OOOOOOOOOOOOOOOO", v.count_observers
    v.delete_observers 
    p "OOOOOOOOOOOOOOOO", v.count_observers
  }
  $pls.each {|k,v|
    p "LLLLLLLLLLLLLL", v.count_observers
  }

  open($Track_list_path, "w"){|fout|
    fout.puts temp_pls.ya2yaml
  }
end
