# -*- coding: utf-8 -*-

=begin

 Ruby library for MPlayer( Ruby/MPlayer)

 (c) Copyright 2004 Kazuki Takemura(kyun@key.kokone.to), japan.
 All rights reserverd.

    Redistribution and use in source and binary forms, with or without
    modification, are permitted provided that the following conditions
    are met:
    1. Redistributions of source code must retain the above copyright
       notice, this list of conditions and the following disclaimer as
       the first lines of this file unmodified.
    2. Redistributions in binary form must reproduce the above copyright
       notice, this list of conditions and the following disclaimer in the
       documentation and/or other materials provided with the distribution.

    THIS SOFTWARE IS PROVIDED BY Kazuki Takemura ``AS IS'' AND ANY EXPRESS OR
    IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
    OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
    IN NO EVENT SHALL Kazuki Takemura BE LIABLE FOR ANY DIRECT, INDIRECT,
    INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
    NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
    DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
    THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
    (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
    THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

=end

require 'kconv'
require 'socket'

# mplayer のある場所
$MPLAYER = "mplayer"

# $MPLAYER = "/home/QtPalmtop/bin/mplayer"  # Linux Zaurus
# $MPLAYER = "/usr/local/bin/mplayer"

# mplayer に渡すオプション
# $MPLAYER_OPTS = "-cache 4096"
$MPLAYER_OPTS = ""

class MPlayer
  attr_reader :status, :length, :length_sec, :volume

  # 状態定数
  INACTIVE  = :inactive
  READY     = :ready
  PLAY      = :play
  PAUSED    = :paused
  ABNORMAL  = :abnormal


  def initialize( addopts = "")
    @mplayerpath = $MPLAYER
    @status = MPlayer::INACTIVE
    @playlist = Array::new()
    @playlistfile = ''

    @addopts = addopts
    @playfile = ''
    @type = 'unknown'
    @bitrate = 'unknown'
    @title = 'unknown'
    @artist = 'unknown'
    @album = 'unknown'
    @channel = 'unknown'
    
    @time_str = nil
    @length = nil
    @volume = 80
    
#     @th_watch = Thread.new{
#       loop{
#         if @status == PLAY
# #          if str = @child_in.gets("\r")
# #           if str = @receive.gets("\r") 
# #             @time_str = str
# #           end
#           sleep 1
#         end
#       }
#     }
  end


  def load_playlist( playlist)

    stop if @status == PLAY || @status == PAUSED
    @playlist = playlist
    @status = MPlayer::READY
    #@playlistfile = @playlist.join(" ")
    @playlistfile = @playlist.map{|file| %Q!"#{file}"! }.join(" ")

    # 再生時間取得のため -slave は外す
    # @mplayeropts = "-quiet -slave " + @addopts + " " + $MPLAYER_OPTS
    @mplayeropts = " -slave " + @addopts + " " + $MPLAYER_OPTS
    
  end


  def play
    if @status == READY

      @receive, send = Socket::pair(Socket::AF_UNIX, Socket::SOCK_STREAM, 0)
      receive, @send = Socket::pair(Socket::AF_UNIX, Socket::SOCK_STREAM, 0)
      @file = ''
      @type = 'unknown'
      @bitrate = 'unknown'
      @title = 'unknown'
      @artist = 'unknown'
      @album = 'unknown'
      @channel = 'unknown'
      @length = nil
      @length_sec = nil
      
      @child = fork {
        @send.close
        @receive.close
        STDIN.reopen(receive)
        STDOUT.reopen(send)
        
        cmdstr = "#{@mplayerpath} #{@mplayeropts} #{@playlistfile}"
        exec cmdstr
      }
      
      send.close
      receive.close
      
      @status = PLAY
      
      @lastmsg = @receive.readline
      start_inspector
      return true
    else
      return false
    end
  end


  def stop
    if @status == PLAY || @status == PAUSED
      stop_inspector
      @send.write("quit\n")
      Process::waitpid( @child, 0)
      @send.close
      @receive.close
      @status = READY
      return true
    else
      return false
    end
  end
  

  def pause
    if @status == PLAY || @status == PAUSED
      @send.write("pause\n")
      if @status == PLAY
        @status = PAUSED
      else
        @status = PLAY
      end
      return true
    else
      return false
    end
  end


  def playlist(step)
    if @status == PLAY || @status == PAUSED
      # @playfile = ''
      str = "pt_step #{step}\n"
      @send.write(str)
      return true
    else
      return false
    end
  end


  def playlist_next
    playlist(1)
  end

  
  def playlist_prev
    playlist(-1)
  end
  

  def seek_sec(sec, rel_or_abs)
    type = case rel_or_abs
           when :relative ; 0
           when :absolute ; 2
           else
             return false
           end
    
    if @status == PLAY || @status == PAUSED
      str = "seek #{sec} type=#{type}\n"
      @send.write(str)
      return true
    else
      return false
    end
  end


  def seek_percent_absolute(percent)
    if @status == PLAY || @status == PAUSED
      # str = "seek %.04f type=1\n" % [ percent ]
      str = "seek %d 1\n" % [ percent ]
      #str = "seek 10% type=1\n"
      @send.write(str)
      return true
    else
      return false
    end
  end
    

  def get_status
    return @status
  end


  def get_fileinfo
    return @playfile, @type, @bitrate, @channel, @title, @artist, @album
  end


  ## 再生直後に呼ばれる
  def start_inspector
    stop_inspector
    @polling_thread = Thread::start{
      while true
        critial = true
        
        begin
          @lastmsg = @receive.readline("\r")
        rescue => e
          $stderr.puts e.class, e.message, e.backtrace
          p @receive
          @status = MPlayer::ABNORMAL
          stop_inspector
          break
        end
        
        @lastmsg.chop!
        case @lastmsg
        when /^Volume: (\d+) %/
          @volume = $1.to_i
          $stderr.puts @volume
          exit
        when /^Playing (.+)/
          ;
        when /^ Title: (.+)/
        when /^ Artist: (.+)/
        when /^ Album: (.+)/
        when /^A:(.+)$/
          @time_str = $&
          unless @length
            /^A:.+?\((.+?)\).+?\((.+?)\).+$/ =~ @time_str
            @length = $2
            case @length
            when /^(.+?):(.+):(.+)\.(.+)$/
              @length_sec = $1.to_i * 60 * 60 + $2.to_i * 60 + $3.to_i + $4.to_f
            when /^(.+):(.+)\.(.+)$/
              @length_sec = $1.to_i * 60 + $2.to_i + $3.to_f
            when /^(.+)\.(.+)$/
              @length_sec = $1.to_i + $2.to_f
            else
              @length_sec = 9999
            end
          end
          
        when /^Selected audio codec: \[(.+?)\] (.+)$/
        when /^AUDIO: (\d+) Hz, (\d) ch,(.+)\((.*?) kbit\)$/
        when /^Exiting\.\.\. \(End of file\)/
          print "Exited.\n"
          @status = READY
          stop_inspector
          @send.close
          @receive.close
        else
          ;
        end 
        critical = false
      end
    }
  end
  

  def stop_inspector
    @polling_thread.exit if !@polling_thread.nil? && @polling_thread.alive?
  end


  # should return float
  def get_time_sec
    if @time_str
      if /^A:(.+?)\s\(/ =~ @time_str
        return $1.to_f
      end
    else
      return nil 
    end
  end

  
  def set_volume(diff)
    @send.print "volume #{diff}\n"
  end


  def set_volume_abs(diff)
    @send.print "volume #{diff} 1\n"
  end
end

=begin
# 動作テスト

playlist = ["/home/kazuki/mp3/imaginary_affair.mp3", "/home/kazuki/mp3/namidanochikai.mp3"]
x = MPlayer::new()
x.load_playlist(playlist)

x.play

sleep(5)
p x.get_fileinfo

x.pause
sleep(3)

x.pause
sleep(5)

x.play
sleep(5)

x.playlist_next
sleep(5)

x.playlist_prev
sleep(4)

x.seek(10)
p x.get_status
p x.get_fileinfo
sleep(4)

x.stop
=end

if $0 == __FILE__
  x = MPlayer.new(" -nolirc -ao alsa ")
  x.load_playlist([ARGV[0]])

  x.play
  sleep 5
  x.pause
  sleep 3
  x.pause
  sleep 3
  x.stop
  sleep 3
end
