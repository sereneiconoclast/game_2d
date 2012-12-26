require 'entity'
require 'gosu'
require 'zorder'

class NPC < Entity
  def initialize(space, x, y, a = 0, x_vel = 0, y_vel = 0)
    super
  end

  def empty_underneath?
    beneath = space.contents([
      [left_cell_x, bottom_cell_y(self.y + 1)],
      [right_cell_x, bottom_cell_y(self.y + 1)],
    ]).delete(self)
    beneath.empty?
  end

  # Primitive gravity: Accelerate downward if all cells beneath are empty
  def update
    accelerate(0, 1) if empty_underneath?
    super
  end

  # Sleep if any cells underneath are occupied and we're not moving
  def sleep_now?
    self.x_vel == 0 && self.y_vel == 0 && !empty_underneath?
  end

  def to_s
    "NPC (#{registry_id}) at #{x}x#{y}"
  end

  def to_json(*args)
    as_json.to_json(*args)
  end

  def as_json
    {
      :class => 'NPC',
      :registry_id => registry_id,
      :position => [ self.x, self.y ],
      :velocity => [ self.x_vel, self.y_vel ],
      :angle => self.a,
      :moving => self.moving?,
    }
  end

  def update_from_json(json)
    new_x, new_y = json['position']
    new_x_vel, new_y_vel = json['velocity']
    new_angle = json['angle']
    new_moving = json['moving']

    warp(new_x, new_y, new_x_vel, new_y_vel, new_angle, new_moving)
  end
end

class ClientNPC < NPC
  def self.load_animation(window)
    @@animation = Gosu::Image::load_tiles(window, "media/tele.gif", 40, 40, false)
  end

  def initialize(space, x, y, a = 0, x_vel = 0, y_vel = 0)
    super
    @color = Gosu::Color.new(0xff000000)
    @color.red = rand(255 - 40) + 40
    @color.green = rand(255 - 40) + 40
    @color.blue = rand(255 - 40) + 40
  end

  def draw
    img = @@animation[Gosu::milliseconds / 100 % @@animation.size]
    img.draw_rot(
      self.pixel_x - img.width / 2.0, self.pixel_y - img.height / 2.0,
      ZOrder::Objects,
      self.a, 0.5, 0.5,
      1, 1, @color, :add)
  end
end
