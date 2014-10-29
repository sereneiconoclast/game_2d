require 'set'
require 'game_space'

# Server sends authoritative copy of GameSpace for tick T0.
# We store that, along with pending moves generated by
# our player, and pending moves for other players sent to us
# by the server.  Then we calculate further ticks of action.
# These are predictions and might well be wrong.
#
# When the user requests an action at T0, we delay it by 100ms
# (T6).  We tell the server about it immediately, but advise
# it not to perform the action until T6 arrives.  The server
# rebroadcasts this information to other players.  Hopefully,
# everyone receives all players' actions before T6.
#
# We render one tick after another, 60 per second, the same
# speed at which the server calculates them.  But because we
# may get out of sync, we also watch for full server updates
# at, e.g., T15.  When we get a new full update, we can discard
# all information about older ticks.  Anything we've calculated
# past the new update must now be recalculated, applying again
# whatever pending player actions we have heard about.
class ClientEngine
  attr_reader :tick

  def initialize(space, tick)
    @spaces = {tick => space}
    @earliest_tick = @tick = tick

    @player_actions = Hash.new {|h,tick| h[tick] = Array.new}
  end

  def add_player_action(player_id, action)
    at_tick = action['at_tick']
    unless at_tick
      $stderr.puts "Received update from #{player_id} without at_tick!"
      at_tick = @tick
    end
    if at_tick < @tick
      $stderr.puts "Received update from #{player_id} #{@tick - at_tick} ticks late"
      at_tick = @tick
    end
    @player_actions[at_tick] << [player_id, action]
  end

  def space_at(tick)
    return @spaces[tick] if @spaces[tick]

    fail "Can't create space at #{tick}; earliest space we know about is #{@earliest_tick}" if tick < @earliest_tick

    last_space = space_at(tick - 1)
    @spaces[tick] = new_space = GameSpace.new.copy_from(last_space)

    @player_actions[tick].each do |player_id, action|
      player = new_space[player_id]
      unless player
        $stderr.puts "No such player #{player_id} -- dropping move"
        next
      end
      if (move = action['move'])
        player.add_move move
      else
        # No other client-side processing we can do
        # We can't 'create_npc' in the client; the server assigns registry IDs
        $stderr.puts "IGNORING BAD DATA from #{player}: #{action.inspect}"
      end
    end

    new_space.update
    new_space
  end

  def update
    space_at(@tick += 1)
  end

  def space
    @spaces[@tick]
  end

  def add_player(json, at_tick)
    space = space_at(at_tick)
    player = Player.new(space, json['player_name'])
    player.registry_id = registry_id = json['registry_id']
    puts "Added player #{player}"
    player.update_from_json(json)
    space << player
    registry_id
  end

  def add_players(players, at_tick)
    players.each {|json| add_player(json, at_tick) }
  end

  def add_npcs(npcs, at_tick)
    space = space_at(at_tick)
    npcs.each {|json| space << Entity.from_json(space, json) }
  end

  def delete_entities(doomed, at_tick)
    space = space_at(at_tick)
    doomed.each do |registry_id|
      dead = space[registry_id]
      next unless dead
      puts "Disconnected: #{dead}" if dead.is_a? Player
      space.doom dead
    end
    space.purge_doomed_entities
  end

  def update_score(update, at_tick)
    space = space_at(at_tick)
    registry_id, score = update.to_a.first
    return unless player = space[registry_id]
    player.score = score
  end

  def sync_registry(server_registry, at_tick)
    @earliest_tick.upto(at_tick - 1) {|old_tick| @spaces.delete old}
    @earliest_tick = at_tick if at_tick > @earliest_tick

    space = space_at(at_tick)
    registry = space.registry
    my_keys = registry.keys.to_set

    server_registry.each do |registry_id, json|
      if my_obj = registry[registry_id]
        my_obj.update_from_json(json)
      else
        clazz = json['class']
        puts "Don't have #{clazz} #{registry_id}, adding it"
        space << clazz.from_json(space, json)
      end

      my_keys.delete registry_id
    end

    my_keys.each do |registry_id|
      puts "Server doesn't have #{registry_id}, deleting it"
      space.doom space[registry_id]
    end
  end
end