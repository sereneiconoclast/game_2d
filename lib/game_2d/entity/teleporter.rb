require 'game_2d/entity'
require 'game_2d/entity/owned_entity'

class Entity

class Teleporter < Entity
  def should_fall?; false; end

  def update
    space.entities_overlapping(x, y).each do |overlap|
      next if overlap == self
      next if (overlap.x - x).abs > WIDTH/2
      next if (overlap.y - y).abs > HEIGHT/2
      dest = space.possessions(self)
      case dest.size
        when 1 then
          dest = dest.first
          if overlap.entities_obstructing(dest.x, dest.y).empty?
            overlap.warp(dest.x, dest.y)
          end
        when 0 then
          $stderr.puts "#{self}: No destination"
        else
          $stderr.puts "#{self}: Multiple destinations: #{dest.inspect}"
      end
    end
  end

  def destroy!
    # destroy destination
  end

  def image_filename; "tele.gif"; end

  def draw_zorder; ZOrder::Teleporter end

  def to_s
    destinations = space.possessions(self).collect do |d|
      "#{d.x}x#{d.y}"
    end.join(', ')
    "#{super} => [#{destinations}]"
  end
end

end
