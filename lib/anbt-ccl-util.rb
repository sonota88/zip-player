module CCL
  def self.url_parse(urlstr)
    return nil unless urlstr
    return urlstr.sub( /^http:\/\/(.+)$/, '\1' )
  end
  
  def self.url2abbr(urlstr)
    path = url_parse(urlstr) 
    return nil unless path
    
    pieces = path.split("/")
    
    raise "invalid url: #{pieces[1]}" unless "licenses" == pieces[1]
    
    type    = pieces[2]
    version = pieces[3]
    nokori  = pieces[4]

    case type
    when "publicdomain"
      return "PD"
    when "MIT"
      return "MIT"
    when "BSD"
      return "BSD"
    when "GPL"
      return "GPL 2.0" if version == "2.0"
    when "LGPL"
      return "LGPL 2.1" if version == "2.1"
    end
    
    if version == "1.0"
      case type
      when "sampling" 
        return "Sampling 1.0 (retired)"
      when "sampling+" 
        return "Sampling+ 1.0"
      when "nc-sampling+" 
        return "NC-Sampling+ 1.0"
      else
        ; #raise "must not happen."
      end
    end
    
    licenseText = "CC "
    licenseText += type.upcase
    licenseText += " " + version
    
    if nokori
      if( /deed\..+/ =~ nokori )
        ;
      else
        licenseText += " " + nokori.upcase
      end
    end
  
    return  licenseText
  end
end


=begin

= References

License Properties - CC Wiki
http://wiki.creativecommons.org/License_Properties

=end
