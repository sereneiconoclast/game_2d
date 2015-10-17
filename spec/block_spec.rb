require 'game_2d/game_space'
require 'game_2d/entity/block'
require 'game_2d/entity/titanium'

describe Entity::Block do
  let(:world) { GameSpace.new(nil).establish_world('lump', nil, 3, 3) }

  subject { world << Entity::Block.new(400, 400) }

  def add_titanium(x, y)
    world << Entity::Titanium.new(x, y)
  end

  def expect_new_height(height)
    expect(subject.y).to eq(height)
  end

  context "when 5 HP or less" do
    before(:each) { subject.hp = 1 }

    it "is level 0 (dirt)" do
      expect(subject.level_name).to eq('dirt')
      expect(subject.level).to eq(0)
    end
    it "falls when nothing underneath" do
      add_titanium 400, 0   # above
      add_titanium 0, 400   # on left
      add_titanium 800, 400 # on right
      add_titanium 0, 800   # lower-left
      add_titanium 800, 800   # lower-right
      expect_new_height 400
      world.update; expect_new_height 401
    end
    it "doesn't fall when something directly underneath" do
      add_titanium 400, 800
      world.update; expect_new_height 400
    end
    it "doesn't fall when something slightly underneath" do
      add_titanium 1, 800
      world.update; expect_new_height 400
    end
  end

  context "when 6 to 10 HP" do
    before(:each) { subject.hp = 10 }

    it "is level 1 (brick)" do
      expect(subject.level_name).to eq('brick')
      expect(subject.level).to eq(1)
    end
    it "falls when supported on left only" do
      add_titanium 400, 0   # above
      add_titanium 0, 400   # on left
      world.update; expect_new_height 401
    end
    it "falls when supported on right only" do
      add_titanium 400, 0   # above
      add_titanium 800, 400   # on right
      world.update; expect_new_height 401
    end
    it "doesn't fall when supported on both sides" do
      add_titanium 0, 400   # on left
      add_titanium 800, 400   # on right
      world.update; expect_new_height 400
    end
    it "falls if the supports don't line up with each other" do
      add_titanium 0, 400   # on left, perfect
      add_titanium 800, 401   # on right, a bit low
      world.update; expect_new_height 401
      world.update; expect_new_height 403
    end
    it "falls until the supports line up with it" do
      add_titanium 0, 402   # on left, a bit below
      add_titanium 800, 402   # on right, same distance below
      world.update; expect_new_height 401
      world.update; expect_new_height 402
      world.update; expect_new_height 402
    end
    it "rises until the supports line up with it" do
      subject.y_vel = -10
      add_titanium 0, 385   # on left, a bit above
      add_titanium 800, 385   # on right, same distance above
      world.update; expect_new_height 391
      world.update; expect_new_height 385
      world.update; expect_new_height 385
    end
  end

  context "when 11 to 15 HP" do
    before(:each) { subject.hp = 11 }

    it "is level 2 (cement)" do
      expect(subject.level_name).to eq('cement')
      expect(subject.level).to eq(2)
    end
    it "falls when supported on top only" do
      add_titanium 400, 0   # above
      world.update; expect_new_height 401
    end
    it "doesn't fall when supported on left only" do
      add_titanium 0, 400   # on left
      world.update; expect_new_height 400
    end
    it "doesn't fall when supported on right only" do
      add_titanium 800, 400   # on right
      world.update; expect_new_height 400
    end
    it "doesn't fall when supported on both sides" do
      add_titanium 0, 400   # on left
      add_titanium 800, 400   # on right
      world.update; expect_new_height 400
    end
    it "falls if the support doesn't line up" do
      add_titanium 0, 398   # on left, a bit high
      world.update; expect_new_height 401
    end
    it "falls until the support lines up" do
      add_titanium 0, 402   # on left, a bit below
      add_titanium 800, 403   # on right, a bit further below
      world.update; expect_new_height 401
      world.update; expect_new_height 402
      world.update; expect_new_height 402
    end
  end

  context "when 16 to 20 HP" do
    before(:each) { subject.hp = 20 }

    it "is level 3 (steel)" do
      expect(subject.level_name).to eq('steel')
      expect(subject.level).to eq(3)
    end
    it "doesn't fall when supported on top only, directly" do
      add_titanium 400, 0   # above
      world.update; expect_new_height 400
    end
    it "doesn't fall when supported on top only, slightly touching" do
      add_titanium 0, 1   # above, far over
      world.update; expect_new_height 400
    end
    it "falls when not touching anything" do
      add_titanium 0, 0   # upper-left
      world.update; expect_new_height 401
    end
  end

  context "when abve 20 HP" do
    before(:each) { subject.hp = 21 }

    it "is level 4 (unlikelium)" do
      expect(subject.level_name).to eq('unlikelium')
      expect(subject.level).to eq(4)
    end
    it "doesn't fall ever" do
      world.update; expect_new_height 400
    end
  end

end