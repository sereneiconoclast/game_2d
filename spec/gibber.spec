require 'spec_helper'
require 'game_2d/gibber/gibber'

describe Game2D::GibberParser do

  let(:droid) { Object.new }

  context "at (200, 400)" do
    before do
      stub(droid) {|s| s.x { 200 }; s.y { 400 } }
    end

    def eval_simple(txt, result, cycles_left)
      expect(tree = subject.parse(txt)).to_not be_nil
      expect(vm = tree.compile).to_not be_nil
      vm.owner = droid
      vm.reset!
      expect(vm.execute(999)).to eq cycles_left
      expect(vm.last).to eq result
      vm
    end

    it "understands true literals" do
      eval_simple 'true', true, 999
    end

    it "understands false literals" do
      eval_simple 'false', false, 999
    end

    it "understands negation" do
      eval_simple '!false', true, 999
      eval_simple '!true', false, 999
    end

    it "understands integer literals" do
      eval_simple '35', 35, 999
    end

    it "understands negative integers" do
      eval_simple '-5', -5, 999
    end

    it "understands ternary operator" do
      eval_simple 'true ? 8 : 3', 8, 998
      eval_simple 'false ? 8 : 3', 3, 998
    end

    it "understands addition" do
      eval_simple '2 + 3', 5, 998
    end

    it "understands subtraction" do
      eval_simple '2 - 3', -1, 998
    end

    it "understands multiplication" do
      eval_simple '2 * 3', 6, 998
    end

    it "understands division" do
      eval_simple '14 / 4', 3, 998
    end

    it "understands modulus" do
      eval_simple '14 % 4', 2, 998
    end

    it "understands equality" do
      eval_simple '4 == 4', true, 998
      eval_simple '4 == 5', false, 998
    end

    it "understands inequality" do
      eval_simple '4 != 4', false, 998
      eval_simple '4 != 5', true, 998
    end

    it "understands less-than" do
      eval_simple '3 < 4', true, 998
      eval_simple '3 < 3', false, 998
    end

    it "understands less-than-or-equal" do
      eval_simple '3 <= 3', true, 998
      eval_simple '3 <= 2', false, 998
    end

    it "understands greater-than" do
      eval_simple '3 > 2', true, 998
      eval_simple '3 > 3', false, 998
    end

    it "understands greater-than-or-equal" do
      eval_simple '3 >= 3', true, 998
      eval_simple '3 >= 4', false, 998
    end

    it "understands assignment" do
      vm = eval_simple 'foo := 3', 3, 998
      expect(vm.heap[:foo]).to eq 3
    end

    it "understands variables" do
      eval_simple 'foo := 3; bar := 4; foo', 3, 997
    end

    it "understands defined?" do
      eval_simple 'defined? foo', false, 999
      eval_simple 'foo := 1; defined? foo', true, 998
    end

    it "understands X position" do
      eval_simple 'X', 200, 999
    end

    it "understands Y position" do
      eval_simple 'Y', 400, 999
    end

    it "understands accelerate" do
      mock(droid).accelerate -2, -4
      eval_simple 'accelerate -2, -4', nil, 993
    end

    it "understands conditional" do
      eval_simple 'if (3 > 2) { 3; }', 3, 997
      eval_simple 'if (3 < 2) { 3; }', nil, 997
      eval_simple 'if (3 > 2) { 3; } else { 2; }', 3, 997
      eval_simple 'if (3 < 2) { 3; } else { 2; }', 2, 997
    end

    it "understands loop" do
      cost = 2 + 6*2 + 5*4
      eval_simple <<-EOP, 32, 999-cost
i := 1;
n := 1;
while (i <= 5) {
  i := i + 1;
  n := n * 2;
};
n
      EOP
    end
  end
end
