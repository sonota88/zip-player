# -*- coding: utf-8 -*-

require "tk"
require "observer"

require "archive-utils"
require "flac"
require "control"


$web_browser = "firefox"
$PLAYING_ITEM_BGCOLOR = "#cccccc"

$ImageManipulate = false
begin
  require "tkextlib/tkimg"
  require "mini_magick"
  $ImageManipulate = true
rescue => e
  $stderr.puts e.message
end


Thread.abort_on_exception = true


def init
  if not File.exist? $temp_dir
    Dir.mkdir $temp_dir
  end

  $arc_file = ARGV[0]
  append_tracks_from_archive($pl, $arc_file, $temp_dir)
end


class App
  attr_accessor :control

  def initialize
    @control = Control.new(self)
    @play_next = nil
    @seekbar_pressed = nil

    init_widget_monitor()
    init_widget_seekbar()
    init_widget_console()
    init_widget_misc()
    init_widget_playlist()
    init_widget_info()

    update(:listbox)
  end


  def in_seek?
    return @seekbar_pressed
  end


  def init_observer
    @control.init_observer
  end


  def update(type)
    case type
    when :listbox
      update_listbox()
    when :info
      update_info()
    when :cover
      update_cover()
    when :interval
      update_interval()
    end
  end


  def init_widget_monitor
    frame_outer = TkFrame.new
    frame_inner = TkFrame.new(frame_outer)

    monitor_font = TkFont.new({
                                #'family' => 'pgothic',
                                'family' => 'fixed',
                                'weight' => 'bold',
                                'slant' => 'roman',
                                'underline' => false,
                                'overstrike' => false,
                                "size" => 10
                              })

    @lbl_title = TkLabel.new(frame_inner) {
      bg("#88ff00")
      text "title"
      font monitor_font
    }
    @lbl_by = TkLabel.new(frame_inner) {
      bg("#88ff00")
      text "by"
      font monitor_font
    }

    @lbl_time = TkLabel.new(frame_inner){      text("--:--:--")
      bg("#88ff00")
      pady 6 ; padx 16
      font monitor_font
    }

    if $ImageManipulate
      @lbl_cover = TkLabel.new(frame_outer)
    end

    @lbl_title.pack(:fill => :both, :expand => true)
    @lbl_by.pack(:fill => :both, :expand => true)
    @lbl_time.pack(:fill => :both, :expand => true)

    @lbl_cover.pack(:side => :left) if $ImageManipulate
    frame_inner.pack(:fill => :both, :expand => true)

    frame_outer.pack(:fill => :both, :expand => true)
  end


  def init_widget_seekbar
    @seekbar = TkScale.new{
      from 0
      to 100
      orient "horizontal"
      borderwidth 1
      showvalue false
    }
    
    # detect click seekbar
    @seekbar.bind "ButtonPress-1", proc { 
      @pos_start = @percent
      _debug @pos_start
      @seekbar_pressed = true
    }

    # スライダーから離れたらシーク実行
    @seekbar.bind "ButtonRelease-1", proc { 
      diff = @seekbar.value - @control.percent
      _debug "move from %.02f to #{@seekbar.value} (%.02f)" % [ @control.percent, diff ] 
      @control.seek_percent_absolute(@seekbar.value)
      @seekbar_pressed = false
    }

    @seekbar.pack(:fill => :both, :expand => true)
  end

  
  def init_widget_info
    @text_info = TkText.new{
      height 12
      font TkFont.new({ 
                        #:family => 'gothic',
                        :family => 'fixed',
                        :weight => 'normal',
                        :slant => 'roman',
                        :underline => false,
                        :overstrike => false,
                        :size => 10
                      })
    }
    @text_info.insert("end", "-")

    @text_info.pack(:fill => :both, :expand => true)
  end

  
  def init_widget_playlist
    frame_pl = TkFrame.new
    bar_pl = TkScrollbar.new(frame_pl)
    @lbox_playlist = TkListbox.new(frame_pl) {|f|
      selectmode 'extended'
      font TkFont.new({ 
                        #:family => 'gothic',
                        :family => 'fixed',
                        :weight => 'normal',
                        :slant => 'roman',
                        :underline => false,
                        :overstrike => false,
                        :size => 10
                      })
      height 12
      yscrollbar bar_pl
    }
    # 左ボタンダブルクリック
    @lbox_playlist.bind 'Double-Button-1', proc {
      @control.move_to(@lbox_playlist.curselection[0]) 
    }

    @lbox_playlist.pack(:fill => :both, :expand => true, :side => :left)
    bar_pl.pack(:side=>:left, :fill=>:y)
    frame_pl.pack(:expand=>true, :fill=> :both)
  end

  
  def init_widget_console
    frame_console = TkFrame.new
    @btn_play = TkButton.new(frame_console){ text ">" }
    @btn_play.command {
      case @control.player_status
      when MPlayer::PAUSED
        _debug "pause => play"
        @btn_play.text "||"
        @control.pause() 
      when MPlayer::PLAY
        _debug "play => pause"
        @btn_play.text ">"
        @control.pause() 
        _debug @control.player_status
      when MPlayer::INACTIVE, MPlayer::Ready, MPlayer::Abnormal
        _debug "not play, not pause"
      else
        raise "must not happen."
      end
    }
    
    @btn_prev = TkButton.new(frame_console) { text "|<" }
    @btn_prev.command { @control.move(-1) }
    
    @btn_next = TkButton.new(frame_console) { text ">|" }
    @btn_next.command { @control.move(1) }

    @btn_seek_rw_div = TkButton.new(frame_console) { text "<1/20" }
    @btn_seek_rw_div.command { @control.seek( -(@control.get_length_sec / 20) ) }
    
    @btn_seek_ff_div = TkButton.new(frame_console) { text "1/20>" }
    @btn_seek_ff_div.command { 
      begin
        @control.seek(@control.get_length_sec / 20) 
      rescue
        @control.seek(0) 
      end
    }

    @btn_vol_minus = TkButton.new(frame_console) { text "vol-" }
    @btn_vol_minus.command { @control.change_vol(-5) }
    @btn_vol_plus = TkButton.new(frame_console) { text "+" }
    @btn_vol_plus.command  { @control.change_vol(5)  }
    
    @btn_vol_global_minus = TkButton.new(frame_console) { text "global vol-" }
    @btn_vol_global_minus.command { @control.change_vol_global(-5) }
    @btn_vol_global_plus = TkButton.new(frame_console) { text "+" }
    @btn_vol_global_plus.command  { @control.change_vol_global(5)  }
    
    frame_console.pack
    @btn_play.pack(:side => :left)
    @btn_prev.pack(:side => :left)
    @btn_next.pack(:side => :left)
    @btn_seek_rw_div.pack(:side => :left)
    @btn_seek_ff_div.pack(:side => :left)
    @btn_vol_minus.pack(:side => :left)
    @btn_vol_plus.pack(:side => :left)
    @btn_vol_global_minus.pack(:side => :left)
    @btn_vol_global_plus.pack(:side => :left)
  end

  
  def init_widget_misc
    frame_misc = TkFrame.new
    @btn_open_release_url = TkButton.new(frame_misc) { text "Open release URL" }
    @btn_open_release_url.command { @control.open_release_url() }

    @btn_edit_albuminfo = TkButton.new(frame_misc) { text "Edit album info" }
    @btn_edit_albuminfo.command { @control.edit_albuminfo() }

    @btn_set_cover = TkButton.new(frame_misc) { text "Set cover" }
    @btn_set_cover.command {
      path = Tk.getOpenFile
      @control.set_cover path
    }
    
    @btn_quit = TkButton.new(frame_misc) { text "Quit" }
    @btn_quit.command { @control.app_exit }

    frame_misc.pack(:side => :top)
    @btn_open_release_url.pack(:side => :left)
    @btn_edit_albuminfo.pack(:side => :left)
    @btn_set_cover.pack(:side => :left)
    @btn_quit.pack(:side => :left)
  end


  ################################################################


  def update_cover
    @lbl_cover.image = if File.exist? "#{$temp_dir}/#{$TEMP_IMAGE_BASENAME}.jpg"
                         TkPhotoImage.new("file" => "#{$temp_dir}/#{$TEMP_IMAGE_BASENAME}.jpg")
                       else
                         TkPhotoImage.new("file" => "#{$app_home}/share/no-cover.png")
                       end
  end


  def update_listbox
    begin
      $pl.size
    rescue
      return
    end


    puts "update_listbox #{$pl.size}"
    @lbox_playlist.delete(0, :end)
    
    n = 0
    $pl.each{|tr|
#       artist = if not track.get_artists() ; "?"
#                else                       ; track.get_artists()
#                end

      # append item
      @lbox_playlist.insert(
                            :end,
                            sprintf("%4s:% 3s #{tr.title}",
                                    n+1,
                                    tr.track_number
                                    )
                            )
      n += 1
    }
    
    # hilite current track
    begin
      @lbox_playlist.itemconfigure($pl.current_index, "background", $PLAYING_ITEM_BGCOLOR)
    rescue
      ;
    end
    _debug "<< refresh_listbox"
  end


  def update_info
    tr = @control.data[:current_tr]

    set_label "title", "title: " + tr.title
    set_label "by", "by: " + tr.get_artists()

    info = ""
    info << "volume: #{tr.volume} * #{$Prefs.global_volume} => #{tr.volume * $Prefs.global_volume / 100}"
    info << "\n"
    info << "license: #{tr.license_abbr}"
    info << "\n"
    info << "-" * 32
    info << "\n"
    info << tr.ya2yaml

    set_text "info", info
  end


  def update_interval
    current = sec2hhmmssxx(@control.get_time_sec())
    length = sec2hhmmssxx(@control.get_length_sec())
    set_label "time", "%s / %s" % [current, length]
  end

  
  def set_label(lbl_name, str)
    if eval( "@lbl_#{lbl_name}" )
      begin
        str.gsub!('"', "\\"+'"' )
        eval %Q!@lbl_#{lbl_name}.text "#{str}"!
      rescue SyntaxError
        eval %Q!@lbl_#{lbl_name}.text #{str.inspect}!
      end
    end
  end


  def set_text(target, str)
    str.gsub!( '"', "\\" + '"')

    if eval( "@text_#{target}" )
      #str.gsub!('"', "\\"+'"' )
      eval( %Q!@text_#{target}.delete( "1.0", :end) ! ) rescue false
      eval( %Q!@text_#{target}.insert( :end, "#{str}" )! ) rescue false
    end
  end


  def set_seekbar_percent(percent)
    begin
      if percent
        @seekbar.value = percent
      end
    rescue => e
      $stderr.puts "XXXX %s / %s" % [ @control.get_time_sec(), @control.get_length_sec() ]
      $stderr.puts e.message, e.backtrace
    end
  end

  
  def start(arc_path, temp_dir)
    @control.prepare_album(arc_path, temp_dir)
    Tk.mainloop
  end
end
