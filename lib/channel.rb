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


if __FILE__ == $0
  ;
end
