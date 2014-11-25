#!/usr/bin/env ruby
require 'rubygems'
require 'trollop'
require 'game_2d/game_window'

opts = Trollop::options do
  opt :name, "Player name", :type => :string, :required => true
  opt :hostname, "Hostname of server", :type => :string, :required => true
  opt :port, "Port number", :default => DEFAULT_PORT
  opt :profile, "Turn on profiling", :type => :boolean
  opt :debug_traffic, "Debug network traffic", :type => :boolean
end

$debug_traffic = opts[:debug_traffic] || false

window = GameWindow.new( opts[:name], opts[:hostname], opts[:port], opts[:profile] )
window.show
