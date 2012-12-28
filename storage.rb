require 'fileutils'
require 'json'

class Storage
  def self.in_home_dir(name)
    Storage.new "#{Dir.home}/#{name}"
  end

  def initialize(dir)
    @dir = dir
    FileUtils.mkdir_p @dir
  end

  def dir(subdir)
    Storage.new("#{@dir}/#{subdir}")
  end

  def [](name)
    Settings.new("#{@dir}/#{name}")
  end

  def to_s; "Storage(#{@dir})"; end
end

class Settings
  def initialize(name)
    @name = name
    @values = File.exist?(name) ? JSON.parse(IO.read(name)) : {}
  end

  def save
    puts "Writing to #{self}"
    File.open(@name, 'w') {|f| f.write(@values.to_json) }
  end

  def [](key); @values[key]; end
  def []=(key, value); @values[key] = value; end
  def empty?; @values.empty?; end

  def to_s; "Settings(#{@name})"; end
end
