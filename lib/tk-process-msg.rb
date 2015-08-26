# -*- coding: utf-8 -*-

QUEUE_SIZE = 8

def process_msg_ex_to_s(ex)
  [
    ex.message,
    ex.class.to_s,
    ex.backtrace.join("\n")
  ].
    map{|line| "#{line}\n" }.
    join("")
end

def process_msg_update_output(text_area, queue)
  text_area.delete("1.0", :end)
  text_area.insert(:end, queue.join(""))
end

def process_msg(cmd, options)
  options ||= {}
  options[:auto_close_sec] ||= nil

  threads = []
  do_exit = false

  win = TkToplevel.new

  label_cmd = TkLabel.new(
    win,
    :text => cmd,
    :padx => 10, :pady => 10
  )
  
  text_area = TkText.new(win) do
    height 12
    font TkFont.new({ 
        #:family => 'gothic',
        :family => 'fixed',
        :weight => 'normal',
        :slant => 'roman',
        :underline => false,
        :overstrike => false,
        :size => 8
      })
  end

  btn_abort = TkButton.new(
    win,
    :text => "Abort",
    :command => proc {
      threads.each do |t|
        t.exit if t.alive?
      end
    })

  btn_close = TkButton.new(
    win,
    :text => "Close",
    :command => proc {
      threads.each do |t|
        t.exit if t.alive?
      end
      do_exit = true
    })

  label_cmd.pack
  text_area.pack(:fill => :both, :expand => true)
  btn_abort.pack
  btn_close.pack
  
  # ----------------
  
  pout_in, pout_out = IO.pipe # stdout
  perr_in, perr_out = IO.pipe # stderr

  threads << Thread.new do
    fork do
      begin
        pout_in.close
        perr_in.close

        STDOUT.reopen( pout_out )
        STDERR.reopen( perr_out )
      
        exec cmd
      rescue => e
        $stderr.puts process_msg_ex_to_s(e)
      end
    end
  end
  sleep 0.01
  pout_out.close
  perr_out.close

  line_out = "non-nil"
  line_err = "non-nil"
  out_ended = false
  err_ended = false
  do_not_close = false
  queue = []

  threads << Thread.new do
    begin
      loop do
        line_out = pout_in.gets()
        if line_out.nil?
          out_ended = true
          break
        end

        queue << line_out
        queue.shift if queue.size > QUEUE_SIZE
        sleep 0.01
      end
    rescue => e
      queue << process_msg_ex_to_s(e)
      do_not_close = true
    end
  end

  threads << Thread.new do
    begin
      loop do
        line_err = perr_in.gets()
        if line_err.nil?
          err_ended = true
          break
        end

        queue << "[E] " + line_err
        queue.shift if queue.size > QUEUE_SIZE
        sleep 0.01
      end
    rescue => e
      queue << process_msg_ex_to_s(e)
      do_not_close = true
    end
  end

  watcher = Thread.new do
    begin
      loop do
        if do_exit
          queue << "interrupted\n"
          break
        end
        break if out_ended && err_ended

        process_msg_update_output text_area, queue
        sleep 0.01
      end
      queue << "done\n"
      process_msg_update_output text_area, queue
      if options[:auto_close_sec] && ! do_exit
        sleep options[:auto_close_sec]
      end
    rescue => e
      $stderr.puts process_msg_ex_to_s(e)
    ensure
      if do_not_close
        ;
      else
        if do_exit || options[:auto_close_sec]
          win.destroy
        end
      end
    end
  end
  watcher.join
end
