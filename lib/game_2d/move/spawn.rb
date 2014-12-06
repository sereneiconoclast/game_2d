require 'game_2d/complex_move'
require 'game_2d/game_client'
require 'game_2d/entity_constants'
require 'game_2d/entity/gecko'

module Move

# A move for ghosts.
class Spawn < ComplexMove
  include EntityConstants

  SPAWN_TRAVEL_SPEED = 80

  # target_id is registry_id of selected base
  attr_accessor :target_id

  def on_completion(actor)
    space = actor.space
    target = space[target_id]
    return unless target && target.available?

    gecko = Entity::Gecko.new(actor.player_name)
    gecko.score = actor.score
    gecko.x, gecko.y, gecko.a = target.x, target.y, target.a
    return unless space << gecko

    actor.replace_player_entity(gecko)
  end

  def update(actor)
    # It's convenient to set 'self' to the Player
    # object, here
    actor.instance_exec(self) do |cm|
      # Abort if the target gets destroyed, or becomes
      # occupied
      target = space[cm.target_id]
      return false unless target && target.available?

      # We're done
      if x == target.x && y == target.y
        @x_vel = @y_vel = 0
        return false
      end

      @x_vel = [[target.x - x, -SPAWN_TRAVEL_SPEED].max, SPAWN_TRAVEL_SPEED].min
      @y_vel = [[target.y - y, -SPAWN_TRAVEL_SPEED].max, SPAWN_TRAVEL_SPEED].min
      # move returns false: it failed somehow
      return move
    end
  end

  def all_state
    super.push @target_id
  end
  def as_json
    super.merge! :target => @target_id
  end
  def update_from_json(json)
    self.target_id = json[:target].to_sym if json[:target]
    super
  end
  def to_s
    "Spawn[#{target_id}]"
  end
end

end
