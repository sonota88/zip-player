#!/usr/bin/ruby

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


class Control
  include Observable
  attr_reader :percent

  DEFAULT_VOLUME = 75
  
  def initialize(parent)
    @parent = parent
    @player = MPlayer.new(" -nolirc -ao alsa ")

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

        @parent.set_label( "time", "%s / %s" % [get_time(), get_length()] )
        begin
          @percent = get_time_sec() / get_length_sec() * 100
          if not @parent.in_seek?
            @parent.set_seekbar_percent(@percent)
          end
        rescue => e
          # $stderr.puts "XXXX %s / %s" % [ @control.get_time_sec(), @control.get_length_sec() ]
          $stderr.puts e.message
        end
        

        if player_status == MPlayer::READY && @play_next
          move(1)
          play()
        end

        if player_status == MPlayer::ABNORMAL && @play_next
          move(1)
          play()
        end

        sleep 0.05
      }
    }
  end


  def refresh_info
    tr = $pl.current_track

    @parent.set_label("title", "title: #{tr.title}")
    @parent.set_label("by",    "by: #{tr.get_artists()}")

    info = ""

    info << "volume: #{tr.volume}"
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
    
    $stderr.puts "prepare_track #{tr.is_archive?}"
    if tr.is_archive?
      arc_file, entry = tr.arc_file_entry()
      p "arc_file, entry = #{arc_file} / #{entry}"
      #arc_path = File.join( $PREFS.DIR_CACHE_SUB, arc_file)
      arc_path = arc_file
      begin
#        arc_cp( arc_path, entry, @local_path )
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
    @player.load_playlist( [ @local_path ] )
    @player.play()

    begin
      if tr.volume
        @player.set_volume_abs(tr.volume)
      end
    rescue => e 
      tr.volume = DEFAULT_VOLUME
      @player.set_volume_abs(DEFAULT_VOLUME)
    end

    #refresh_info()
  end


  def move(diff)
    puts "move: #{$pl.current_index} => #{$pl.current_index + diff} / {$pl.list.size-1}"
    $pl.current_index += diff
    if $pl.current_index <= 0
      $pl.current_index = 0
    elsif $pl.current_index >= $pl.size
      # $pls.current_index = $pls.list.size-1
      $pl.current_index = 0
      #randomize_playlist()
      @play_next = false
    end
    
    move_to($pl.current_index)
  end

  
  def move_to(target)
    puts "move to: #{$pl.current_index+1} => #{target+1} / #{$pl.size}"
    $pl.current_index = target
    puts "///////////////////////////////"
    puts $pl.current_track.to_ezhash
    $pl.each_with_index{|t, n|
      if t.to_ezhash == $pl.current_track.to_ezhash
        $pl.current_index = n
      end
    }
    puts $pl.current_track.to_ezhash
    puts "<<///////////////////////////////"
    
    # @parent.set_label( "title", "title: #{$pl.current_track.title}")
    # @parent.set_label( "by",    "by: #{$pl.current_track.get_artists()}")
    
    if player_status == MPlayer::PLAY
      stop()
      puts "<<22 2 ///////////////////////////////"
      play()
      puts "<<22 3 ///////////////////////////////"
      if $pl.current_track.volume
        @player.set_volume_abs($pl.current_track.volume)
      end
    end
    puts "<<33///////////////////////////////"
    # @parent.lbox_playlist.see $pl.current_index
    
    begin
      @parent.lbox_playlist.itemconfigure($pl.current_index, "background", $PLAYING_ITEM_BGCOLOR)
    rescue
      puts $!
    end

    refresh_info()
  end


  def seek(sec)
    puts "seek(#{sec})"
    @player.seek(sec)
  end
  

  def get_length
    begin
      return @player.length
    rescue => e
      return "(length)"
    end
  end


  def get_length_sec
    return @player.length_sec
  end

  
  def get_time
    #    return @player.get_time()
    begin
      sec_f = @player.get_time().to_f
    rescue => e
      return "time: ---- #{e.message} "
    end
    sec_i = sec_f.to_i
    ms = (sec_f % 1.0) * 100
    h = sec_i / 3600
    m = (sec_i - h * 3600) / 60
    s = (sec_i - h * 3600 - m * 60)
    
    return "time: %02d:%02d:%02d.%02d" % [h, m, s, ms]
  end


  def get_time_sec
    return @player.get_time().to_f
  end


  def change_vol(diff)
    if $pl.current_track.volume
      temp_vol = $pl.current_track.volume + diff
      if    temp_vol < 0   ; temp_vol = 0
      elsif temp_vol > 100 ; temp_vol = 100
      end
      $pl.current_track.volume = temp_vol
    else
      $pl.current_track.volume = DEFAULT_VOLUME
    end
    @player.set_volume_abs($pl.current_track.volume)
    refresh_info()
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


  def edit_albuminfo
    puts $arc_file, $pl.current_index
    puts tempfile = File.join( $app_home, "__temp_info.yaml")

    temp_index = $pl.current_index

    AlbumInfo.edit_albuminfo($arc_file, :overwrite)
    $pl.clear
    append_archive_file($pl, $arc_file, $temp_dir)
    
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


  def seek_percent(percent)
    @player.seek_percent percent
  end


  def app_exit
    stop()
    delete_temp_audio()
    exit
  end
end
