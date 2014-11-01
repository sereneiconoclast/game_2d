require 'entity'

class Wall < Entity
  def initialize(space, cell_x, cell_y)
    super(cell_x * Entity::WIDTH, cell_y * Entity::HEIGHT)
    self.space = space
  end

  def moving?; false; end
  def moving=(moving); end

  def sleep_now?; true; end
  def wake!; end

  def to_s
    "Wall at #{left_cell_x}x#{top_cell_y} (#{x}x#{y})"
  end
end
