module EntityConstants
  # All our drawings are 40x40
  CELL_WIDTH_IN_PIXELS = 40

  # We track entities at a resolution higher than pixels, called "subpixels"
  # This is the smallest detectable motion, 1 / PIXEL_WIDTH of a pixel
  PIXEL_WIDTH = 10

  # The dimensions of a cell, equals the dimensions of an entity
  WIDTH = HEIGHT = CELL_WIDTH_IN_PIXELS * PIXEL_WIDTH

  # Maximum velocity is a full cell per tick, which is a lot
  MAX_VELOCITY = WIDTH
end