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


if __FILE__ == $0
  ;
end
