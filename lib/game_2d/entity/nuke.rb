class Entity

class Nuke < Entity
  MAX_AGE = 200
  BLAST_RADIUS = 1300

  def initialize(*args)
    super(*args)
    @age = 0
  end

  def update
    super
    if @age % 20 == 0
      @space.within_range(cx, cy, BLAST_RADIUS).each do |victim|
        victim.harmed_by(self)
      end
    end
    @age += 1
    @space.doom(self) if @age >= MAX_AGE
  end

  def sleep_now?; false; end

  def should_fall?; empty_underneath?; end

  def image_filename; "nuke.png"; end

  def draw_image(anim)
    # Explosion blossoms quickly, then fades slowly
    show_image = case @age
      when (30..79), (85..89) then 3
      when (20..29), (80..84), (90..119), (125..129) then 2
      when (10..19), (120..124), (130..159), (165..169) then 1
      else 0
    end
    anim[show_image]
  end

  def all_state
    super.push(@age)
  end

  def as_json
    super.merge!(:age => @age)
  end

  def update_from_json(json)
    @age = json[:age] if json[:age]
    super
  end
end

end
