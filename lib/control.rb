#!/usr/bin/ruby
# -*- coding: utf-8 -*-

require "observer"

require "anbt-mplayer-ctl"
require "archive-utils"
require "album-info"
require "mini_magick"

$web_browser = "firefox"
$COVER_SIZE = "128x128"
$TEMP_AUDIO_BASENAME = "temp-audio"
$TEMP_IMAGE_BASENAME = "temp-image"

Thread.abort_on_exception = true


PrefPath = File.join( $app_home, "zip-player-pref.yaml" )

if File.exist?(PrefPath)
  $Prefs = YAML.load( File.read(PrefPath) )
  $Prefs.init
else
  $Prefs = Preferences.new
end


class Control
  include Observable
  attr_reader :percent

  DEFAULT_VOLUME = 75
  
  def initialize(parent)
    @parent = parent
    # " -nolirc -ao alsa -af volume=-100 "
    # @player = MPlayer.new(" -nolirc -af volume=-100 ")
    @player = MPlayer.new(" -nolirc -ao pulse volume=-100 ")

    watcher_thread()
  end


  def init_observer
    self.add_observer(@parent)
  end


  def watcher_thread
    @watcher = Thread.new {
      loop{
        if $pl == nil
          sleep 1
          next
        end

        @parent.set_label( "time", "%s / %s" % [sec2hhmmssxx(get_time_sec()), sec2hhmmssxx(get_length_sec())] )

        begin
          if get_length_sec
            @percent = get_time_sec() / get_length_sec() * 100
          end
          #pp "time: %.2f / length: %.2f / %.2f %%" % [get_time_sec, get_length_sec, @percent]

          if not @parent.in_seek?
            @parent.set_seekbar_percent(@percent)
          end
        rescue => e
          # $stderr.puts "%s / %s" % [ @control.get_time_sec(), @control.get_length_sec() ]
          $stderr.puts e.message, e.backtrace
        end
        
        # should separate to method such as "over_length()"
        over_end = begin  ; get_time_sec() > get_length_sec()
                   rescue ; false
                   end
        #pp "over_end?: #{get_time_sec} > #{get_length_sec} =>  #{over_end} / player_status: #{player_status}"
        #exit if over_end

        if (player_status == MPlayer::READY && @play_next) ||
            (player_status == MPlayer::ABNORMAL && @play_next) ||
            over_end
          move(1)
          play()
        end

        #sleep 1
        sleep 0.05
      }
    }
  end


  def refresh_info
    tr = $pl.current_track

    @parent.set_label("title", "title: #{tr.title}")
    @parent.set_label("by",    "by: #{tr.get_artists()}")

    $pl.current_track.volume ||= DEFAULT_VOLUME

    info = ""

    info << "volume: #{tr.volume} * #{$Prefs.global_volume} => #{tr.volume * $Prefs.global_volume / 100}"
    info << "\n"
    info << "license: #{tr.license_abbr}"
    info << "\n"
    info << "-" * 32
    info << "\n"
    info << tr.ya2yaml
    @parent.set_text("info", info)
  end
  
  
  def prepare_cover_img(tr, arc_path)
    # $VERBOSE = true

    temp_img_path = File.join( $temp_dir, "#{$TEMP_IMAGE_BASENAME}.jpg" )
    if File.exist? temp_img_path
      FileUtils.rm(temp_img_path)
    end

    cp_result = false
    case File.extname(arc_path)
    when /\.zip$/
      arc_root = arc_root_dir(arc_path)

      entry = ["cover.jpg",
               "cover.png",
               "#{arc_root}/cover.jpg",
               "#{arc_root}/cover.png"
              ].find{ |e|
        entry_exist?(arc_path, e)
      }

      cp_result = arc_cp(arc_path, entry, temp_img_path)
      cp_result = entry && cp_result

    when /\.flac$/i
      cmd = %Q! metaflac --export-picture-to="#{temp_img_path}" #{arc_path} !
      system cmd
      
      cp_result = File.exist? temp_img_path
    end

    if cp_result
      [temp_img_path].each{|img|
        MiniMagick::Image.new(img).resize $COVER_SIZE
      }
    end
  end


  def prepare_track
    $stderr.puts "prepare_track"
    tr = $pl.current_track
    
    @local_path = File.join($temp_dir, tr.local_path() )
    p "@local_path = #{@local_path}"
    
    $stderr.puts "archive? = #{tr.is_archive?}"
    if tr.is_archive?
      arc_file, entry = tr.arc_file_entry()
      p "arc_file, entry = #{arc_file} / #{entry}"
      #arc_path = File.join( $PREFS.DIR_CACHE_SUB, arc_file)
      arc_path = arc_file
      begin
        if not File.exist? @local_path
          arc_cp(arc_path, entry, @local_path)
        end
      rescue => e
        $stderr.puts e.message, e.backtrace
      end
    else
      @local_path = tr.local_path
      arc_path = tr.local_path
    end
    p "@local_path = #{@local_path}"

    if not File.exist?(@local_path)
      $stderr.puts "! could not find: #{@local_path}"
      #       $stderr.puts "$pls.list.size = #{$pls.list.size}"
      #       $stderr.puts "$pls.current_index = #{$pls.current_index}"
      # tr.file_exist_flag = false
      return :skip
    end

    prepare_cover_img(tr, arc_path)

    tr
  end


  def play(file_list=nil)
    tr = prepare_track()

    if tr == :skip
      move(1)
      play()
      return
    end

    # @local_path = tr.local_path()
    
    changed ; notify_observers(:listbox)

    @parent.update_cover()

    puts "play", file_list
    
    refresh_info()

    @play_next = true
    @player.load_playlist( [ @local_path ])
    @player.play()
    set_vol()

    @player.seek_sec(tr.start_sec, :absolute)

    #refresh_info()
  end


  def move(diff)
    puts "move: #{$pl.current_index} => #{$pl.current_index + diff} / {$pl.list.size-1}"
    $pl.current_index += diff
    if $pl.current_index <= 0
      $pl.current_index = 0
    elsif $pl.current_index >= $pl.size
      $pl.current_index = 0
      @play_next = false
    end
    
    move_to($pl.current_index)
  end

  
  def move_to(target)
    puts "move to: #{$pl.current_index+1} => #{target+1} / #{$pl.size}"
    $pl.current_index = target
    puts $pl.current_track.to_ezhash
    $pl.each_with_index{|t, n|
      if t.to_ezhash == $pl.current_track.to_ezhash
        $pl.current_index = n
      end
    }
    puts $pl.current_track.to_ezhash
    
    if player_status == MPlayer::PLAY
      stop()
      play()
      set_vol()
    end
    
    begin
      @parent.lbox_playlist.itemconfigure($pl.current_index, "background", $PLAYING_ITEM_BGCOLOR)
    rescue
      puts $!
    end

    refresh_info()
  end


  def seek(sec)
    puts "seek(#{sec})"
    @player.seek_sec(sec, :relative)
  end
  

  def get_length_sec
    if @player.length_sec == nil
      return nil
    end

    tr = $pl.current_track
    if tr.start_sec 
      if tr.end_sec
        tr.end_sec - tr.start_sec      
      else
        @player.length_sec - tr.start_sec      
      end
    else
      @player.length_sec
    end
  end


  def get_time_sec
    sec_f = @player.get_time_sec()
    if sec_f == nil
      return nil
    end
    
    if $pl.current_track.start_sec
      sec_f - $pl.current_track.start_sec
    else
      sec_f
    end
  end


  def set_vol
    @player.set_volume_abs( $Prefs.global_volume * $pl.current_track.volume / 100 )
    refresh_info()
  end


  def change_vol(diff)
    $pl.current_track.volume ||= DEFAULT_VOLUME

    temp_vol = $pl.current_track.volume + diff
    if    temp_vol < 0   ; temp_vol = 0
    elsif temp_vol > 100 ; temp_vol = 100
    end
    $pl.current_track.volume = temp_vol
    
    set_vol()
  end


  def change_vol_global(diff)
    $pl.current_track.volume ||= DEFAULT_VOLUME

    temp_vol = $Prefs.global_volume + diff
    if    temp_vol < 0   ; temp_vol = 0
    elsif temp_vol > 100 ; temp_vol = 100
    end
    $Prefs.global_volume = temp_vol

    set_vol()
  end


  def pause
    @player.pause()
  end


  def stop
    @player.stop()
    @play_next = false
  end

  
  def player_status
    return @player.status rescue nil
  end


  def open_release_url()
    #track = $pls[$pls.current_index]
    tr = $pl.current_track
    if tr.get_release_url()
      puts "release URL: #{tr.get_release_url()}"
      system %Q!#{$web_browser} #{tr.get_release_url()}!
    else
      TkWarning.new("There is not release_url.")
      return
    end
  end


  def reload_tracks(pl, arc_file, temp_dir)
    pl.clear
    append_tracks_from_archive(pl, arc_file, temp_dir)
  end

  def edit_albuminfo
    puts $arc_file, $pl.current_index
    puts tempfile = File.join( $app_home, "__temp_info.yaml")

    temp_index = $pl.current_index

    AlbumInfo.edit_albuminfo($arc_file, :overwrite)

    reload_tracks($pl, $arc_file, $temp_dir)
    
    $pl.current_index = temp_index

    refresh_info()
  end


  def delete_temp_audio
    Dir.open($temp_dir).each {|path|
      next if path == "."
      next if path == ".."
      print "deleting: "
      puts File.join( $temp_dir, path)
      File.delete File.join( $temp_dir, path)
    }
  end


  def seek_percent_absolute(percent)
    diff_sec_f = get_length_sec * (percent.to_f / 100) - get_time_sec # to - from
    @player.seek_sec( diff_sec_f, :relative)
  end

  
  def set_cover(cover_path)
    /^(.+)\.(.+?)$/ =~ File.basename(cover_path)
    cover_base, cover_ext = $1, $2

    /^(.+)\.(.+?)$/ =~ $arc_file
    base, arc_ext = $1, $2

    case arc_ext.downcase
    when "zip"
      root_dir = arc_root_dir($arc_file)

      dest_dir = if root_dir != nil
                   root_dir + "/"
                 else
                   "/"
                 end
    
      arc_add_overwrite($arc_file, cover_path, dest_dir + "cover." + cover_ext)
    when "flac"
      cmd = %Q! metaflac --remove --block-type=PICTURE "#{$arc_file}" !
      system cmd
      cmd = %Q! metaflac --import-picture-from="#{File.expand_path(cover_path)}" "#{$arc_file}" !
      system cmd
    end


    prepare_cover_img($pl.current_track, $arc_file)
    @parent.update_cover()
  end


  def append_album(pl, arc_path, temp_dir)
    case arc_path
    when /\.zip$/i
      append_tracks_from_archive(pl, arc_path, temp_dir)
    when /\.flac$/i
      append_flac(pl, arc_path, temp_dir)
    else
      $stderr.puts "File type not recognizable."
      exit
    end
  end

  
  def prepare_album(arc_location, temp_dir)
    $pl = PlayList.new($app)
    #pp $pl ; exit

    t = Thread.new {
      if /^(http|ftp)/ =~ arc_location
        url = arc_location
        temp_file = url.split("/").last
        $arc_file = File.expand_path( File.join( temp_dir, "__temp__" + temp_file ) )
        pp cmd = %Q! wget "#{url}" -O "#{$arc_file}" !

        require "tk-process-msg"
        process_msg(cmd, :stderr) {|line|
           if /(\d+%)\s(.+)\s(.+)/ =~ line
             "%s(%s)" % [$1, $3]
           else
             "download by wget"
           end
        }
      else
        $arc_file = arc_location
      end
      
      append_album($pl, $arc_file, temp_dir)
    
      play($pl)
    }
  end


  def app_exit
    stop()
    delete_temp_audio()
    $Prefs.save(PrefPath)
    exit
  end
end
