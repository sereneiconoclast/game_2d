class Entity

class Block < Entity
  def should_fall?; empty_underneath?; end

  def image_filename; "media/dirt.gif"; end
end

end
