require 'facets/kernel/try'
require 'game_2d/serializable'

# A complex move is any move that has its own state.
# Moves that span multiple ticks are complex, because
# the server may have to tell the client how much of
# the complex move has been completed by a player.
class ComplexMove
  include Serializable

  attr_reader :actor_id

  def initialize(actor=nil)
    self.actor_id = actor.nullsafe_registry_id
  end

  def actor_id=(id)
    @actor_id = id.try(:to_sym)
  end

  # Execute one tick of the move.
  # Return true if there is more work to do,
  # false if the move has completed.
  def update(actor)
    false
  end

  # Take a final action after the complex move
  # is done
  def on_completion(actor); end

  def all_state
    [actor_id]
  end
  def as_json
    Serializable.as_json(self).merge!(:actor_id => actor_id)
  end
  def update_from_json(json)
    self.actor_id = json[:actor_id] if json[:actor_id]
    self
  end
  def to_s
    self.class.name
  end
end
