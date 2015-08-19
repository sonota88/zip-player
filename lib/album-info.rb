# -*- coding: utf-8 -*-

require "rubygems"
require "fileutils"
require "pp"
require "tmpdir"
require "optparse"
require "taglib"
require "ya2yaml"
require "zipruby"


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


class AlbumInfo
  ALBUM_INFO_FILE = "info.yaml"
  JAMENDO_README = "Readme - www.jamendo.com .txt"
  NEW_ARC_SUFFIX = "_with_info.zip"
  AI_TEMPLATE =<<-EOB
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


  def initialize(arc_path)
    @arc_path = arc_path
    @arc = ArchiveFile.new(arc_path)

    @editor = case Config::CONFIG["host_os"]
              when "mswin32", "mingw32"
                "notepad.exe"
              else
                "gedit"
              end
  end

  
  def exec_cmd(str)
    _debug str
    system str
  end


  def get_album_metadata
    result = {}

    entry = nil
    ext = nil

    @arc.entry_list.each do |e|
      ext = File.extname(e)
      if /\.mp3$/ =~ ext
        entry = e
        break
      end
    end

    if entry == nil
      raise "could not find mp3."
    end

    _debug entry

    temp_path = File.join(Dir.tmpdir, "__#{File.basename(__FILE__)}_temp#{ext}")
    open(temp_path, "wb") do |f|
      f.write @arc.entry_read(entry)
    end

    case ext
    when /\.mp3$/i
      _todo "(get_album_metadata)"
      # tag = ID3Lib::Tag.new(temp_path, ID3Lib::V2)
      # tag.each do |frame|
      #   case frame[:id]
      #   when :WOAS
      #     result[:release_url] = frame[:url]
      #   when :WCOP
      #     result[:license_url] = frame[:url]
      #   when :TALB
      #     result[:album_title] = kconv_u16tou8(frame[:text])
      #   else
      #     ;
      #   end
      # end
    end
    FileUtils.rm(temp_path)
    
    result
  end


  def album_info_template
    info_exist = nil
    info_valid = nil
    invalid_text = nil

    info_entry = dest_info_entry()

    if @arc.entry_exist? info_entry
      info_exist = true
      # check validness
      begin
        YAML.load( @arc.entry_read(info_entry) )
        info_valid = true
      rescue
        info_valid = false
        invalid_text = @arc.entry_read(info_entry)
      end
    else
      info_exist = false
    end

    _debug "info_exist: #{info_exist}"
    _debug "info_valid: #{info_valid}"
    
    result = {}

    if info_valid
      result = YAML.load( @arc.entry_read(info_entry) )
    else
      result = YAML.load(AI_TEMPLATE)

      if @arc.entry_exist?(JAMENDO_README)
        existing = get_album_metadata()
        result["licenses"] = [{'url'=>existing[:license_url], 
                                'verify_at'=>existing[:release_url]}]
        result["album"]["title"] =  existing[:album_title]
      else
        _debug "no info.\n"
      end
    end

    return result, invalid_text
  end


  def get_preedit_str
    template, invalid_text = album_info_template()
    preedit_str = ""
    preedit_str << template.ya2yaml
    preedit_str << "\n...\n"
    if invalid_text
      preedit_str << invalid_text
    else
      preedit_str << "（エンコーディング判別用テキスト / Text for determining encoding）"
    end
    preedit_str << "\n"
  end

  
  def dest_info_entry
    require "archive-utils"
    arc_root = arc_root_dir(@arc_path)

    if arc_root
      File.join(arc_root, ALBUM_INFO_FILE)
    else
      ALBUM_INFO_FILE
    end
  end
    

  def new_or_modify(overwrite = nil)
    arc_basename = File.basename(@arc_path)
    temp_infopath = File.join(Dir.tmpdir, AlbumInfo::ALBUM_INFO_FILE)

    preedit_str = get_preedit_str()
    open(temp_infopath, "w") {|f| f.print preedit_str }

    exec_cmd( %Q! #{@editor} "#{temp_infopath}" ! )
    
    postedit_str = File.read(temp_infopath)
    if preedit_str == postedit_str
      _debug "Nothing changed."
      return
    end

    open(temp_infopath, "w") {|f| f.print postedit_str }

    new_arc_basename = "#{arc_basename}#{NEW_ARC_SUFFIX}"
    FileUtils.cp(@arc_path, new_arc_basename)
    #sleep 1
    
    new_arc = ArchiveFile.new(new_arc_basename)

    info_entry = dest_info_entry()

    if new_arc.entry_exist?(info_entry)
      new_arc.entry_rm(info_entry)
    end
    new_arc.entry_add(temp_infopath, info_entry)

    if overwrite
      #FileUtils.rm(arc_basename)
      FileUtils.mv(new_arc_basename, arc_basename)
    end
  end


  def content
    if @arc.entry_exist?(ALBUM_INFO_FILE)
      @arc.entry_read(ALBUM_INFO_FILE)
    else
      "Could not find #{ALBUM_INFO_FILE}"
    end
  end

  
  def rm
    if @arc.entry_exist?(ALBUM_INFO_FILE)
      @arc.entry_rm(ALBUM_INFO_FILE)
    else
      "Could not find #{ALBUM_INFO_FILE}"
    end
  end


  def self.edit_albuminfo(arc_path, overwrite = nil)
    ai = AlbumInfo.new(arc_path)
    if overwrite
      ai.new_or_modify(:overwrite)
    else
      ai.new_or_modify(nil)
    end
  end

  
  def new_arc_fullpath
    File.expand_path(@arc_path) + NEW_ARC_SUFFIX
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

  ai = AlbumInfo.new(arc_path)
  if opts[:print]
    puts case Config::CONFIG["host_os"]
         when "mswin32", "mingw32"
           ai.content.tosjis
         else
           ai.content
         end
  elsif opts[:remove]
    ai.rm
  elsif opts[:overwrite]
    ai.new_or_modify(:overwrite)
  else
    if File.exist? ai.new_arc_fullpath
      $stderr.puts "New file already exists: #{ai.new_arc_fullpath}"
      exit
    end
    ai.new_or_modify
  end
end
