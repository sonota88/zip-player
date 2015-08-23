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
