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
    "NPC (#{registry_id_safe}) at #{x}x#{y}"
  end

  def as_json
    super().merge( :class => 'NPC' )
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
    # Entity's pixel_x/pixel_y is the location of the upper-left corner
    # draw_rot wants us to specify the point around which rotation occurs
    # That should be the center
    img.draw_rot(
      self.pixel_x + Entity::CELL_WIDTH_IN_PIXELS / 2,
      self.pixel_y + Entity::CELL_WIDTH_IN_PIXELS / 2,
      ZOrder::Objects, self.a,
      0.5, 0.5, # rotate around the center
      1, 1, # scaling factor
      @color, # modify color
      :add) # draw additively
  end
end
