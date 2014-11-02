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
  # If we haven't received a full update from the server in this
  # many ticks, stop guessing.  We're almost certainly wrong by
  # this point.
  MAX_LEAD_TICKS = 60

  attr_reader :tick

  def initialize(game_window)
    @game_window, @width, @height = game_window, 0, 0
    @spaces = {}
    @deltas = Hash.new {|h,tick| h[tick] = Array.new}
    @earliest_tick = @tick = nil
  end

  def establish_world(world, at_tick)
    @width, @height = world['cell_width'], world['cell_height']
    create_initial_space(at_tick)
  end

  def create_initial_space(at_tick)
    @earliest_tick = @tick = at_tick
    @spaces[@tick] = GameSpace.new.establish_world(@width, @height)
  end

  def space_at(tick)
    return @spaces[tick] if @spaces[tick]

    fail "Can't create space at #{tick}; earliest space we know about is #{@earliest_tick}" if tick < @earliest_tick

    last_space = space_at(tick - 1)
    @spaces[tick] = new_space = GameSpace.new.copy_from(last_space)
    apply_deltas(tick)

    new_space.update
    new_space
  end

  def update
    return unless @tick # handshake not yet answered

    if @tick - @earliest_tick >= MAX_LEAD_TICKS
      $stderr.puts "Lost connection?  Running ahead of server?"
      return space_at(@tick)
    end
    space_at(@tick += 1)
  end

  def space
    @spaces[@tick]
  end

  def create_local_player(player_id)
    old_player_id = @game_window.player_id
    fail "Already have player #{old_player_id}!?" if old_player_id

    @game_window.player_id = player_id
    puts "I am player #{player_id}"
  end

  def add_delta(delta)
    at_tick = delta.delete 'at_tick'
    if at_tick < @tick
      $stderr.puts "Received delta #{@tick - at_tick} ticks late"
      if at_tick <= @earliest_tick
        $stderr.puts "Discarding it - we've received registry sync at <#{@earliest_tick}>"
        return
      end
    end
    @deltas[at_tick] << delta
  end

  def apply_deltas(at_tick)
    space = space_at(at_tick)

    @deltas[at_tick].each do |hash|
      npcs = hash['add_npcs']
      add_npcs(space, npcs) if npcs

      players = hash['add_players']
      add_players(space, players) if players

      doomed = hash['delete_entities']
      delete_entities(space, doomed) if doomed

      updated = hash['update_entities']
      update_entities(space, updated) if updated

      move = hash['move']
      apply_move(space, move) if move

      score_update = hash['update_score']
      update_score(space, score_update) if score_update
    end

    # Any later spaces are now invalid
    @spaces.delete_if {|key, _| key > at_tick}
  end

  def add_player(space, hash)
    player = Player.new(hash['player_name'])
    player.registry_id = registry_id = hash['registry_id']
    puts "Added player #{player}"
    player.update_from_json(hash)
    space << player
    registry_id
  end

  def add_players(space, players)
    players.each {|json| add_player(space, json) }
  end

  def apply_move(space, move)
    player_id = move['player_id']
    player = space[player_id]
    fail "No such player #{player_id}, can't apply #{move.inspect}" unless player
    player.add_move move['move']
  end

  def add_npcs(space, npcs)
    npcs.each {|json| space << Entity.from_json(json) }
  end

  def add_entity(space, json)
    clazz = json['class']
    method_in_class = (clazz == 'Player') ? Player : Entity
    space << method_in_class.from_json(json)
  end

  # Returns the set of registry IDs updated or added
  def update_entities(space, updated)
    registry_ids = Set.new
    registry = space.registry
    updated.each do |json|
      registry_id = json['registry_id']
      fail "Can't update #{entity.inspect}, no registry_id!" unless registry_id
      registry_ids << registry_id

      if my_obj = registry[registry_id]
        my_obj.update_from_json(json)
      else
        puts "Don't have #{json['class']} #{registry_id}, adding it"
        add_entity(space, json)
      end
    end

    registry_ids
  end

  def delete_entities(space, doomed)
    doomed.each do |registry_id|
      dead = space[registry_id]
      next unless dead
      puts "Disconnected: #{dead}" if dead.is_a? Player
      space.doom dead
    end
    space.purge_doomed_entities
  end

  def update_score(space, update)
    registry_id, score = update.to_a.first
    return unless player = space[registry_id]
    player.score = score
  end

  def sync_registry(server_registry, at_tick)
    # Any older deltas are now irrelevant
    @earliest_tick.upto(at_tick - 1) {|old_tick| @deltas.delete old_tick}

    # If the server is ahead of us, catch up by, effectively, starting over
    if at_tick > @tick
      $stderr.puts "Server is ahead of us -- dropping #{at_tick - @tick} frames"
      @spaces.clear
      update_entities(create_initial_space(at_tick), server_registry)
      return
    end

    # No longer need any earlier spaces
    @earliest_tick.upto(at_tick - 1) {|old_tick| @spaces.delete old_tick}
    @earliest_tick = at_tick

    space = space_at(at_tick)

    my_keys = space.registry.keys.to_set
    server_keys = update_entities(space, server_registry)

    (my_keys - server_keys).each do |registry_id|
      puts "Server doesn't have #{registry_id}, deleting it"
      space.doom space[registry_id]
    end
  end
end