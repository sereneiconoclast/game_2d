require 'set'
require 'game_2d/game_space'

describe GameSpace do
  subject { GameSpace.new(nil).establish_world('lump', nil, 3, 3) }
  describe "@grid" do
    let(:grid) { subject.instance_variable_get :@grid }
    it "has the right size grid" do
      expect(grid.size).to eq(5)
      expect(grid.first.size).to eq(5)
      expect(grid.last.size).to eq(5)
    end

    it "has cells" do
      expect(grid[0][0]).to be_a Cell
    end

    it "has cells that know their positions" do
      expect(grid[4][2].x).to eq(3)
      expect(grid[4][2].y).to eq(1)
      expect(grid[0][1].x).to eq(-1)
      expect(grid[0][1].y).to eq(0)
    end

    it "forbids changes" do
      expect { grid[0][0] = nil }.to raise_exception
    end
  end

  describe "#at" do
    it "returns the right cell" do
      cell = subject.at(0,2)
      expect(cell.x).to eq(0)
      expect(cell.y).to eq(2)
    end
    it "disallows illegal coordinates" do
      expect { subject.at(2, 4) }.to raise_exception
      expect { subject.at(-2, 3) }.to raise_exception
    end
  end

  describe "#put and #cut" do
    let(:dirt) { Entity::Block.new(@x, @y) }

    it "populates the cell" do
      cell = subject.at(1, 2)
      expect(cell).to be_empty
      subject.put(1, 2, dirt)
      expect(cell).to include(dirt)
    end

    it "clears the cell" do
      cell = subject.at(1, 2)
      subject.put(1, 2, dirt)
      expect(cell).to include(dirt)
      subject.cut(1, 2, dirt)
      expect(cell).to be_empty
    end
  end

  describe "#cell_at_point" do
    it "translates from a point to a cell" do
      expect(subject.cell_at_point(399,399)).to eq([0,0])
      expect(subject.cell_at_point(399,400)).to eq([0,1])
      expect(subject.cell_at_point(401,399)).to eq([1,0])
      expect(subject.cell_at_point(799,800)).to eq([1,2])
    end
  end

  describe "#cells_at_points" do
    it "translates from points to cells" do
      expect(subject.cells_at_points(
        [
          [399,399],
          [399,400],
          [401,399],
          [799,800]
        ]
      )).to eq([[0,0], [0,1], [1,0], [1,2]].to_set)
    end
  end

  describe "#corner_points_of_entity" do
    it "returns all four corners, given the upper-left corner" do
      expect(subject.corner_points_of_entity(200,300)).to eq(
        [
          [200,300], [599,300], [200,699], [599,699]
        ]
      )
    end
  end

  # Normally these blocks wouldn't be allowed to intersect this
  # way, but we're using the low-level put() call, so no check
  # for collisions is done.
  describe "#entities_at_point" do
    let(:first_match)  { Entity::Block.new(400, 400) }
    let(:second_match) { Entity::Block.new(799, 799) }
    let(:not_match)    { Entity::Block.new(600, 399) } # too high
    it "returns all entities touching that point" do
      subject.put(1, 1, first_match)
      subject.put(1, 1, second_match)
      subject.put(2, 1, second_match)
      subject.put(1, 2, second_match)
      subject.put(2, 2, second_match)
      subject.put(1, 0, not_match)
      subject.put(2, 0, not_match)
      subject.put(1, 1, not_match)
      subject.put(2, 1, not_match)
      result = subject.entities_at_point(799, 799)
      expect(result).to be_an(Array)
      expect(result).to include(first_match)
      expect(result).to include(second_match)
      expect(result).not_to include(not_match)
      expect(result.size).to eq(2)
    end
  end

  describe "#entities_at_points" do
    let(:first_match)  { Entity::Block.new(0, 0) }
    let(:second_match) { Entity::Block.new(780, 400) }
    let(:not_match)    { Entity::Block.new(799, 400) } # too far right
    it "returns all entities touching those points" do
      subject.put(0, 0, first_match)
      subject.put(1, 1, second_match)
      subject.put(2, 1, second_match)
      subject.put(1, 1, not_match)
      subject.put(2, 1, not_match)
      result = subject.entities_at_points([[10,10],[785,600]])
      expect(result).to be_a(Set)
      expect(result).to include(first_match)
      expect(result).to include(second_match)
      expect(result).not_to include(not_match)
      expect(result.size).to eq(2)
    end
  end

  describe "#entities_bordering_entity_at" do
    let(:above1)    { Entity::Block.new(201, 200) }
    let(:above2)    { Entity::Block.new(999, 200) }
    let(:below1)    { Entity::Block.new(201, 1000) }
    let(:below2)    { Entity::Block.new(999, 1000) }
    let(:left1)     { Entity::Block.new(200, 201) }
    let(:left2)     { Entity::Block.new(200, 999) }
    let(:right1)    { Entity::Block.new(1000, 201) }
    let(:right2)    { Entity::Block.new(1000, 999) }
    let(:too_left)  { Entity::Block.new(199, 600) }
    let(:too_right) { Entity::Block.new(1001, 600) }
    let(:too_high)  { Entity::Block.new(600, 199) }
    let(:too_low)   { Entity::Block.new(600, 1001) }
    it "returns all entities bordering that space" do
      subject.put(1, 1, above1)
      subject.put(1, 1, left1)
      subject.put(1, 1, too_left)
      subject.put(2, 1, above2)
      subject.put(2, 1, right1)
      subject.put(2, 1, too_right)
      subject.put(1, 2, below1)
      subject.put(1, 2, left2)
      subject.put(1, 2, too_high)
      subject.put(2, 2, below2)
      subject.put(2, 2, right2)
      subject.put(2, 2, too_low)
      result = subject.entities_bordering_entity_at(600, 600)
      expect(result).to eq(
        [above1, above2, below1, below2,
         left1, left2, right1, right2].to_set
      )
    end
  end

  describe "#entities_overlapping" do
    let(:upperleft)  { Entity::Block.new(201, 201) }
    let(:upperright) { Entity::Block.new(999, 201) }
    let(:lowerleft)  { Entity::Block.new(201, 999) }
    let(:lowerright) { Entity::Block.new(999, 999) }
    let(:too_left)   { Entity::Block.new(200, 600) }
    let(:too_right)  { Entity::Block.new(1000, 600) }
    let(:too_high)   { Entity::Block.new(600, 200) }
    let(:too_low)    { Entity::Block.new(600, 1000) }
    it "returns entities that intersect with an entity at that position" do
      subject.put(1, 1, upperleft)
      subject.put(1, 1, too_high)
      subject.put(2, 1, upperright)
      subject.put(2, 1, too_right)
      subject.put(1, 2, lowerleft)
      subject.put(1, 2, too_left)
      subject.put(2, 2, lowerright)
      subject.put(2, 2, too_low)
      result = subject.entities_overlapping(600, 600)
      expect(result).to eq(
        [upperleft, upperright, lowerleft, lowerright].to_set
      )
    end
  end

  describe "#cells_overlapping" do
    it "returns cells that intersect with an entity at that position" do
      result = subject.cells_overlapping(600, 600)
      expect(result).to eq(
        [Cell.new(1,1), Cell.new(2,1), Cell.new(1,2), Cell.new(2,2)]
      )
    end
  end

  describe "#add_entity_to_grid and #remove_entity_from_grid" do
    let(:thing) { Entity::Block.new(600, 600) }
    it "populates and de-populates the correct cells" do
      expect(subject.at(1,1)).to be_empty
      expect(subject.at(2,1)).to be_empty
      expect(subject.at(1,2)).to be_empty
      expect(subject.at(2,2)).to be_empty
      subject.add_entity_to_grid(thing)
      expect(subject.at(1,1)).to include(thing)
      expect(subject.at(2,1)).to include(thing)
      expect(subject.at(1,2)).to include(thing)
      expect(subject.at(2,2)).to include(thing)
      subject.remove_entity_from_grid(thing)
      expect(subject.at(1,1)).to be_empty
      expect(subject.at(2,1)).to be_empty
      expect(subject.at(1,2)).to be_empty
      expect(subject.at(2,2)).to be_empty
      expect { subject.remove_entity_from_grid(thing) }.to raise_exception
    end
  end
  describe "#update_grid_for_moved_entity" do
    it "works when going from one cell to two" do
      thing = Entity::Block.new(400, 400)
      subject.add_entity_to_grid(thing)
      expect(subject.at(1,1)).to include(thing)
      expect(subject.at(2,1)).to be_empty
      expect(subject.at(1,2)).to be_empty
      expect(subject.at(2,2)).to be_empty
      thing.x = 401
      subject.update_grid_for_moved_entity(thing, 400, 400)
      expect(subject.at(1,1)).to include(thing)
      expect(subject.at(2,1)).to include(thing)
      expect(subject.at(1,2)).to be_empty
      expect(subject.at(2,2)).to be_empty
    end
    it "works when going from one cell to four" do
      thing = Entity::Block.new(400, 400)
      subject.add_entity_to_grid(thing)
      expect(subject.at(1,1)).to include(thing)
      expect(subject.at(2,1)).to be_empty
      expect(subject.at(1,2)).to be_empty
      expect(subject.at(2,2)).to be_empty
      thing.x = thing.y = 401
      subject.update_grid_for_moved_entity(thing, 400, 400)
      expect(subject.at(1,1)).to include(thing)
      expect(subject.at(2,1)).to include(thing)
      expect(subject.at(1,2)).to include(thing)
      expect(subject.at(2,2)).to include(thing)
    end
    it "works when going from four cells to one" do
      thing = Entity::Block.new(410, 410)
      subject.add_entity_to_grid(thing)
      expect(subject.at(1,1)).to include(thing)
      expect(subject.at(2,1)).to include(thing)
      expect(subject.at(1,2)).to include(thing)
      expect(subject.at(2,2)).to include(thing)
      thing.x = thing.y = 400
      subject.update_grid_for_moved_entity(thing, 410, 410)
      expect(subject.at(1,1)).to include(thing)
      expect(subject.at(2,1)).to be_empty
      expect(subject.at(1,2)).to be_empty
      expect(subject.at(2,2)).to be_empty
    end
  end

  describe "#register" do
    it "adds the object to the registry and entity list" do
      thing = Entity::Block.new(0, 0)
      thing.registry_id = :A
      expect(subject.npcs).to be_empty
      expect(subject[:A]).to be_nil
      expect(subject.registered?(thing)).to be false
      subject.register(thing)
      expect(subject.npcs).to eq([thing])
      expect(subject[:A]).to equal(thing)
      expect(subject.registered?(thing)).to be true
    end
    it "allows the same object to be registered twice" do
      thing = Entity::Block.new(0, 0)
      thing.registry_id = :A
      subject.register(thing)
      subject.register(thing)
      expect(subject.npcs).to eq([thing])
      expect(subject[:A]).to equal(thing)
      expect(subject.registered?(thing)).to be true
    end
    it "rejects another object with the same ID" do
      thing1 = Entity::Block.new(0, 0)
      thing1.registry_id = :A
      subject.register(thing1)
      thing2 = Entity::Block.new(0, 0)
      thing2.registry_id = :A
      subject.register(thing2)
      expect(subject.npcs).to eq([thing1])
      expect(subject[:A]).to equal(thing1)
      expect(subject.registered?(thing1)).to be true
      expect { subject.registered?(thing2) }.to raise_exception
    end
  end
  describe "#deregister" do
    it "removes the object from the registry and entity list" do
      thing = Entity::Block.new(0, 0)
      thing.registry_id = :A
      subject.register(thing)
      subject.deregister(thing)
      expect(subject.npcs).to be_empty
      expect(subject[:A]).to be_nil
      expect(subject.registered?(thing)).to be false
    end
    it "refuses to remove the wrong object" do
      thing1 = Entity::Block.new(0, 0)
      thing1.registry_id = :A
      subject.register(thing1)
      thing2 = Entity::Block.new(0, 0)
      thing2.registry_id = :A
      expect { subject.deregister(thing2) }.to raise_exception
      expect(subject.npcs).to eq([thing1])
      expect(subject[:A]).to equal(thing1)
      expect(subject.registered?(thing1)).to be true
    end
  end

  describe "#<<" do
    it "registers the entity and adds it to the grid" do
      thing = Entity::Block.new(200, 400)
      thing.registry_id = :A
      subject << thing
      expect(subject[:A]).to equal(thing)
      expect(subject.at(0, 1)).to include thing
    end
    it "checks for conflicts" do
      thing1 = Entity::Block.new(200, 400)
      thing1.registry_id = :A
      subject << thing1
      thing2 = Entity::Block.new(0, 100)
      thing2.registry_id = :B
      subject << thing2
      expect(subject[:B]).to be_nil
    end
  end
end