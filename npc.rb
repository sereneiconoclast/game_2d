require 'chipmunk'
require 'gosu'
require 'zorder'
require 'registerable'

class NPC
  include Registerable
  attr_reader :body, :shape

  def initialize(x, y, x_vel = 0.0, y_vel = 0.0)
    @body = CP::Body.new(0.0001, 0.0001)
    @body.object = self
    @body.p = CP::Vec2.new(x, y) # position
    @body.v = CP::Vec2.new(x_vel, y_vel) # velocity
    @body.a = (3*Math::PI/2.0) # angle in radians; faces towards top of screen

    shape_array = [
      CP::Vec2.new(-10.5, -10.5),
      CP::Vec2.new(-10.5, 10.5),
      CP::Vec2.new(10.5, 10.5),
      CP::Vec2.new(10.5, -10.5)
    ]
    @shape = CP::Shape::Poly.new(@body, shape_array, CP::Vec2.new(0, 0))
    @shape.collision_type = :npc

    @shape.e = 0.99 # elasticity
  end

  def to_s
    "NPC (#{registry_id})"
  end

  def to_json(*args)
    as_json.to_json(*args)
  end

  def as_json
    {
      :class => 'NPC',
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

class ClientNPC < NPC
  def self.load_animation(window)
    @@animation = Gosu::Image::load_tiles(window, "media/tele.gif", 40, 40, false)
  end

  def initialize(x, y, x_vel, y_vel)
    super(x, y, x_vel, y_vel)
    @color = Gosu::Color.new(0xff000000)
    @color.red = rand(255 - 40) + 40
    @color.green = rand(255 - 40) + 40
    @color.blue = rand(255 - 40) + 40
  end

  def draw
    img = @@animation[Gosu::milliseconds / 100 % @@animation.size]
    img.draw_rot(
      @body.p.x - img.width / 2.0, @body.p.y - img.height / 2.0,
      ZOrder::Objects,
      @body.a.radians_to_gosu, 0.5, 0.5,
      1, 1, @color, :add)
  end
end
