require 'chipmunk'
require 'gosu'
require 'zorder'
require 'registerable'

class Star
  include Registerable
  attr_reader :body, :shape

  def initialize(x, y, x_vel = 0.0, y_vel = 0.0)
    @body = CP::Body.new(0.0001, 0.0001)
    @body.object = self
    @shape = CP::Shape::Circle.new(body, 25/2, CP::Vec2.new(0.0, 0.0))
    @shape.collision_type = :star

    @shape.e = 0.99 # elasticity
    @shape = shape
    @body.p = CP::Vec2.new(x, y) # position
    @body.v = CP::Vec2.new(x_vel, y_vel) # velocity
    @body.a = (3*Math::PI/2.0) # angle in radians; faces towards top of screen
  end

  def to_s
    "STAR (#{registry_id})"
  end

  def to_json(*args)
    as_json.to_json(*args)
  end

  def as_json
    {
      :class => 'Star',
      :registry_id => registry_id,
      :position => [ @body.p.x, @body.p.y ],
      :velocity => [ @body.v.x, @body.v.y ]
    }
  end

  def update_from_json(json)
    x, y = json['position']
    x_vel, y_vel = json['velocity']
    @body.p = CP::Vec2.new(x, y) # position
    @body.v = CP::Vec2.new(x_vel, y_vel) # velocity
  end
end

class ClientStar < Star
  def self.load_animation(window)
    @@animation = Gosu::Image::load_tiles(window, "media/Star.png", 25, 25, false)
  end

  def initialize(x, y, x_vel, y_vel)
    super(x, y, x_vel, y_vel)
    @color = Gosu::Color.new(0xff000000)
    @color.red = rand(255 - 40) + 40
    @color.green = rand(255 - 40) + 40
    @color.blue = rand(255 - 40) + 40
  end

  def draw
    img = @@animation[Gosu::milliseconds / 100 % @@animation.size];
    img.draw(@body.p.x - img.width / 2.0, @body.p.y - img.height / 2.0, ZOrder::Stars, 1, 1, @color, :add)
  end
end
