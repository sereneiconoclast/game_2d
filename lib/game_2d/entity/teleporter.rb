require 'game_2d/entity'

class Entity

class Teleporter < Entity
  attr_reader :destination_id

  def all_state; super.push(destination_id); end
  def as_json; super.merge!(:destination_id => destination_id); end

  def update_from_json(json)
    self.destination_id = json[:destination_id] if json[:destination_id]
    super
  end

  def should_fall?; false; end

  def update
    @space.entities_overlapping(x, y).each do |overlap|
      next if overlap == self
      next if (overlap.x - x).abs > WIDTH/2
      next if (overlap.y - y).abs > HEIGHT/2
      $stderr.puts "Overlapping: #{overlap}"
    end
  end

  def destroy!
    # destroy destination
  end

  def image_filename; "tele.gif"; end
end

end
