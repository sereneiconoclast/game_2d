#!/usr/bin/env ruby
require 'rubygems'
require 'trollop'
require 'game_2d/game'

opts = Trollop::options do
  opt :level, "Level name", :type => :string, :required => true
  opt :width, "Level width", :type => :integer
  opt :height, "Level height", :type => :integer
  opt :port, "Port number", :type => :integer
  opt :storage, "Data storage dir (in home directory)", :type => :string
  opt :max_clients, "Maximum clients", :type => :integer
  opt :self_check, "Run data consistency checks", :type => :boolean
  opt :profile, "Turn on profiling", :type => :boolean
  opt :debug_traffic, "Debug network traffic", :type => :boolean
  opt :registry_broadcast_every, "Send registry broadcasts every N frames (0 = never)", :type => :integer
end

$debug_traffic = opts[:debug_traffic] || false

Game.new(opts).run
