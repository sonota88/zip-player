#!/usr/bin/ruby -Ku

require "rubygems"
require "fileutils"
require "pp"
require "kconv"
require "tmpdir"
require "optparse"
require "id3lib"
require "ya2yaml"
require "zipruby"

$editor = nil
$Album_info_file = "info.yaml"
$Jamendo_readme = "Readme - www.jamendo.com .txt"

$AI_template =<<EOB
--- 
artists: 
- name: 
release_url: []
pub_date: 
licenses: 
- verify_at: 
  url: 
album: 
  title: 
  id: 
description:
tags: []
donation_info_url: 
EOB


def set_editor
  $editor = case PLATFORM
  when /mswin32/
    "notepad.exe"
  else
    "gedit"
  end
end


class ArchiveFile

  def initialize(arc_path)
    @arc_path = arc_path

    if not File.exist?(@arc_path)
      raise "could not find #{@arc_path}."
    end
  end


  def entry_exist?(entry)
    Zip::Archive.open(@arc_path) do |ar|
      n = ar.num_files  
      n.times do |i|
        name = ar.get_name(i)
        return true if name == entry
      end
    end
    false
  end


  def entry_read(entry)
    content = nil
    Zip::Archive.open(@arc_path) do |ar|
      ar.fopen(entry) do |f|
        next if f.name != entry
        content = f.read
      end
    end
    content
  end


  def entry_add(path, entry)
    Zip::Archive.open(@arc_path) do |ar|
      ar.add_file(entry, path)
    end
  end


  def entry_replace(path)
    Zip::Archive.open(@arc_path) do |ar|
      $stderr.puts ar.replace_file(0, path)
    end
  end


  def entry_rm(entry)
    Zip::Archive.open(@arc_path) do |ar|
      n = ar.num_files
      n.times do |i|
        entry_name = ar.get_name(i)
        ar.fopen(entry_name) do |f|
          if f.name == entry
            f.delete()
          end
        end
      end
    end
  end


  def entry_cp(entry, newentry)
    content = nil
    Zip::Archive.open(@arc_path) do |ar|
      n = ar.num_files
      ar.fopen(entry) do |f|
        next if f.name != entry
        content = f.read
      end
      ar.add_buffer(newentry, content)
    end
  end


  def entry_mv(entry, newentry)
    entry_cp(entry, newentry)
    entry_rm(entry)
  end


  def entry_list
    result = []
    Zip::Archive.open(@arc_path) do |ar|
      n = ar.num_files
      n.times do |i|
        result << ar.get_name(i)
      end
    end
    result
  end
end


def kconv_u16tou8(str)
  Kconv.kconv( str, Kconv::UTF8, Kconv::UTF16)
end


def exec_cmd(str)
  $stderr.puts str
  system str
end


def get_album_metadata(arc)
  result = {}

  entry = nil
  ext = nil

  arc.entry_list.each do |e|
    ext = File.extname(e)
    if /\.mp3$/ =~ ext
      entry = e
      break
    end
  end

  if entry == nil
    raise "could not find mp3."
  end

  $stderr.puts entry

  temp_path = File.join(Dir.tmpdir, "__#{File.basename(__FILE__)}_temp#{ext}")
  open(temp_path, "wb") do |f|
    f.write arc.entry_read(entry)
  end

  case ext
  when /\.mp3$/i
    tag = ID3Lib::Tag.new(temp_path, ID3Lib::V2)
    tag.each do |frame|
      case frame[:id]
      when :WOAS
        result[:release_url] = frame[:url]
      when :WCOP
        result[:license_url] = frame[:url]
      when :TALB
        result[:album_title] = kconv_u16tou8(frame[:text])
      else
        ;
      end
    end
  end
  FileUtils.rm(temp_path)
  
  result
end




class AlbumInfo
  def initialize(arc_path)
    @arc_path = arc_path
    @arc = ArchiveFile.new(arc_path)
  end


  def album_info_template
    info_exist = nil
    info_valid = nil
    invalid_text = nil

    if @arc.entry_exist? $Album_info_file
      info_exist = true
      # check validness
      begin
        YAML.load( @arc.entry_read($Album_info_file) )
        info_valid = true
      rescue
        info_valid = false
        invalid_text = @arc.entry_read($Album_info_file)
      end
    else
      info_exist = false
    end

    puts "info_exist: #{info_exist}"
    puts "info_valid: #{info_valid}"
    
    result = {}

    if info_valid
      result = YAML.load( @arc.entry_read($Album_info_file) )
    else
      result = YAML.load($AI_template)

      if @arc.entry_exist?($Jamendo_readme)
        existing = get_album_metadata(@arc)
        result["licenses"] = [{'url'=>existing[:license_url], 
                                'verify_at'=>existing[:release_url]}]
        result["album"]["title"] =  existing[:album_title]
      else
        print "no info.\n"
      end
    end

    return result, invalid_text
  end


  def new_or_modify(overwrite = nil, tempfile = nil)
    arc_basename = File.basename(@arc_path)

    if tempfile
      temp_infopath = tempfile
    else
      temp_infopath = File.join(Dir.tmpdir, $Album_info_file)
    end

    open(temp_infopath, "w") do |f|
      template, invalid_text = album_info_template()
      f.puts template.ya2yaml
      f.puts "\n..."
      if invalid_text
        f.puts invalid_text
      else
        f.puts "（文字コード判別用テキスト）"
      end
    end

    exec_cmd( %Q! #{$editor} "#{temp_infopath}" ! )

    temp_str = File.read(temp_infopath)
    open(temp_infopath, "w") {|f| f.print temp_str.toutf8 }

    FileUtils.cp(temp_infopath, "000.yaml") if $DEBUG

    new_arc_basename = "#{arc_basename}_with_info.zip"
    FileUtils.cp(@arc_path, new_arc_basename)
    #sleep 1
    
    new_arc = ArchiveFile.new(new_arc_basename)
    
    if new_arc.entry_exist?($Album_info_file)
      new_arc.entry_rm($Album_info_file)
    end
    new_arc.entry_add(temp_infopath, $Album_info_file)

    if overwrite
      #FileUtils.rm(arc_basename)
      FileUtils.mv(new_arc_basename, arc_basename)
    end
  end


  def content
    if @arc.entry_exist?($Album_info_file)
      @arc.entry_read($Album_info_file)
    else
      "could not find #{$Album_info_file}"
    end
  end

  
  def rm
    if @arc.entry_exist?($Album_info_file)
      @arc.entry_rm($Album_info_file)
    else
      "could not find #{$Album_info_file}"
    end
  end


  def self.edit_albuminfo(arc_path, tempfile, overwrite = nil)
    set_editor()
    
    ai = AlbumInfo.new(arc_path)
    if overwrite
      ai.new_or_modify(:overwrite, tempfile)
    else
      ai.new_or_modify(nil, tempfile)
    end
  end
end


################################################################
if $0 == __FILE__
  opts = {}
  ARGV.options {|o|
    o.banner = "ruby #$0 [options] [args]"
    o.on("-p", "--print", "print info.yaml") {|x| opts[:print] = x }
    o.on("-r", "--remove", "remove info.yaml") {|x| opts[:remove] = x }
    o.on("-w", "--overwrite", "overwrite original archive file") {|x| opts[:overwrite] = x }
    o.parse!
  }

  arc_path = nil
  if not ARGV[0]
    $stderr.puts "usage: #{__FILE__} foo.zip"
    exit 1
  end
  arc_path = ARGV[0]

  set_editor()

  ai = AlbumInfo.new(arc_path)
  if opts[:print]
    puts case PLATFORM
         when /mswin32/
           ai.content.tosjis
         else
           ai.content
         end
  elsif opts[:remove]
    ai.rm
  elsif opts[:overwrite]
    ai.new_or_modify(:overwrite)
  else
    ai.new_or_modify
  end
end
