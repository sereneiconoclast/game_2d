require 'chipmunk'

# Convenience method for converting from radians to a Vec2 vector.
class Numeric
  def radians_to_vec2
    CP::Vec2.new(Math::cos(self), Math::sin(self))
  end
end

# Convenience method for getting position and velocity as a single array.
class CP::Body
  def game_vector
    [ p.x, p.y, v.x, v.y ]
  end
end
