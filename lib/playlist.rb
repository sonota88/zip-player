require "observer"

class PlayList
  include Enumerable
  include Observable

  attr_accessor :list
  attr_accessor :current_index
  attr_accessor :title
  attr_accessor :date, :artists, :url, :license_url

  def initialize(app)
    @list = []
    @current_index = 0

    $stderr.puts "---- add_observer ----" if $DEBUG
    
    begin
      self.add_observer(app)
    rescue
      $stderr.puts $!
    end
  end

  def current_track
    if @list.empty?
      false
    else
      @list[@current_index]
    end
  end

  def size ; @list.size ; end
  def empty? ; @list.empty? ; end
  def <<(x) ; @list << x ; end
  
  def [](index)
    @list[index]
  end

  def map
    @list.map{|x| yield x }
  end
  def each
    @list.each{|x| yield x }
  end

  def uniq!
    # @list.uniq!
    @list = self.uniq()
  end
  def uniq
    temp = self.dup
    temp.list.uniq!
    return temp
  end

  def include?(other)
    @list.include?(other)
  end

  def shuffle
    @list = @list.sort_by{rand()}
  end

  def sort!
    @list = @list.sort_by {|t|
      sort_order = ""
      sort_order << t.get_artists()
      sort_order << t.album['title'] if defined? t.album['title']
      sort_order << t.title

      sort_order
    }
  end


  def clear
    @list.clear
  end
  
  
  def sort_by_point!
    @list = @list.sort_by{ |t|
      if t.fav_point ; t.fav_point
      else           ; 0
      end
    }.reverse
  end

  def insert(n, *vals)
    @list[n, 0] = vals
  end
  def delete_at(n)
    @list.delete_at(n)
  end

  def volume_stat
    n = 0
    min = 100
    max = 0
    sum = 0
    @list.each{|t|
      if t.volume
        sum += t.volume
        n += 1

        min = t.volume if min > t.volume
        max = t.volume if max < t.volume
      end
    }

    return {
      :sum => sum,
      :n => n,
      :average => sum.to_f / n,
      :min => min,
      :max => max
    }
  end

  def tags
    aa = (@list.map{|t|
       t.sys_tags if t.sys_tags && t.sys_tags != nil && !(t.sys_tags.empty?)
     }.flatten - [nil] + [DEFAULT_TAG]
     ).map{|tag| tag.downcase}.sort.uniq

    bb=(@list.map{|t|
       t.tags if t.tags && t.tags != nil && !(t.tags.empty?)
     }.flatten - [nil]
     ).map{|tag| tag.downcase}.sort.uniq

    aa + bb
  end

  
  def append_track(elem)
    @list << elem

    temp_hash = current_track.to_ezhash
    $stderr.puts "current track ez hash = #{temp_hash}"
    # $pls.list = uniq_track( $pl.list )
    @list.uniq!
    
    if $DEBUG
      $stderr.puts "--DDDDDDD #{current_index} // #{temp_hash} DDDDDDDD"
      $stderr.puts "--FFFFFFFFF"
      $stderr.puts @list.map{|a| a.to_ezhash }
      $stderr.puts "--FFFFFFFFF"
    end
    current_index = @list.map{|a| a.to_ezhash }.index(temp_hash)

    if $DEBUG
      $stderr.puts "--DDDDDDDEE #{current_index} DDDDDDDD"
      $stderr.print "#{current_index} / #{@list.size}\n"
      sleep 2
      $stderr.puts "--DDDDDDD => #{current_index} DDDDDDDD"
    end

    changed
    notify_observers()
  end
end


