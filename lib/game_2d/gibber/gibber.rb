require 'treetop'

Treetop.load "#{File.dirname __FILE__}/gibber.treetop"

module Game2D
module Gibber

class VM
  DEBUG = false

  def initialize(instructions=[], heap={})
    @instructions = instructions
    @heap = heap
    @stack = []
    @current = 0
    @owner = @last = nil
    @done = false
  end

  attr_reader :last, :heap, :done
  attr_accessor :owner

  def done?; @done end

  # To clear the heap, pass an empty hash
  def reset!(heap=nil)
    fail "Need an owner" unless @owner
    @heap = heap if heap

    @stack.clear
    @current = 0
    @last = nil
    @done = false
  end

  def as_json
    {
      :instructions => @instructions,
      :heap => @heap,
      :stack => @stack,
      :current => @current,
      :last => @last,
      :done => @done
    }
  end

  def update_from_json(json)
    @instructions = json[:instructions]
    @heap = json[:heap]
    @stack = json[:stack]
    @current = json[:current]
    @last = json[:last]
    @done = json[:done]
  end

  # Performs as much work as possible given the cycles
  # available.  Returns the unconsumed cycles.
  def execute(avail_cycles)
    loop do
      if DEBUG
        puts(
          @instructions.each.with_index.collect do |v, i|
            case @current
            when i then "[#{v}"
            when i-1 then "]#{v}"
            else " #{v}"
            end
          end.join('') + ' | ' + @stack.join(' ')
        )
      end

      if @current >= @instructions.size
        @done = true
        return avail_cycles
      end

      if avail_cycles <= 0
        return avail_cycles
      end

      case inst = @instructions[@current]

      when 'J' then # Skip ahead (or back) N bytes
        @current += 2 + @instructions[@current + 1]

      when 'X' then # Push X position
        @stack.push(@last = @owner.x)
        @current += 1

      when 'Y' then # Push Y position
        @stack.push(@last = @owner.y)
        @current += 1

      when 'P' then # Push a literal
        @stack.push(@last = @instructions[@current + 1])
        @current += 2

      when '!' then # pop, negate
        @stack.push(@last = ! @stack.pop)
        @current += 1

      when '+', '-', '*', '/', '%', # pop two numbers, do math
           '==', '!=', '<', '>', '<=', '>='
        l, r = @stack.pop(2)
        @stack.push(@last = l.send(inst, r))
        @current += 1
        avail_cycles -= 1

      when 'A' then # pop, assign to variable
        id = @instructions[@current + 1]
        @heap[id.to_sym] = @stack.pop
        @current += 2
        avail_cycles -= 1

      when 'D' then # defined-variable check
        id = @instructions[@current + 1]
        @stack.push(@last = @heap.include?(id.to_sym))
        @current += 2

      when 'V' then # variable reference
        id = @instructions[@current + 1]
        @stack.push(@last = @heap[id.to_sym])
        @current += 2

      when 'T' then # pop, decide whether to jump ahead
        expr = @stack.pop
        t_size = @instructions[@current + 1]
        # 'T' 4 t1 t2 J 2 f1 f2 ...
        # Size byte tells us how many to skip ahead if
        # the expression was false
        @current += expr ? 2 : 2 + t_size
        @last = nil
        avail_cycles -= 1

      when 'accel' then
        x_accel, y_accel = @stack.pop(2)
        @owner.accelerate x_accel, y_accel
        @current += 1
        avail_cycles -= (x_accel.abs + y_accel.abs)
        @last = nil

      else fail "Unexpected: #{inst}"
      end
    end
  end

end

module Program
  def compile
    VM.new(sequence.compile)
  end
end

module Sequence
  def compile
    statements = [first_stmt] + rest.elements.map(&:stmt)
    statements.map(&:compile).flatten
  end
end

module Loop
  def compile
    c, b = comparison.compile, sequence.compile
    c + ['T', b.size + 2] + b +
      ['J', -(c.size + 2 + b.size + 2)]
  end
end

module Conditional
  def compile
    c, t = comparison.compile, true_seq.compile
    if false_part.respond_to? :false_seq
      f = false_part.false_seq.compile
      c + ['T', t.size + 2] + t + ['J', f.size] + f
    else
      c + ['T', t.size] + t
    end
  end
end

module Ternary
  def compile
    # 'T' <n> -- jump ahead N if expr is false
    c, t, f = comparison.compile,
      true_exp.compile, false_exp.compile
    c + ['T', t.size + 2] + t + ['J', f.size] + f
  end
end

module Assignment
  def compile
    e = expression.compile
    e + ['A', identifier.text_value]
  end
end

module Val
  def compile
    val.compile
  end
end

module Math
  def compile
    l, r = left.compile, right.compile
    l + r + [op.text_value]
  end
end

module MathOperator
  def compile
    fail "undefined for MathOperator"
  end
end

module IsDefined
  def compile
    ['D', identifier.text_value]
  end
end

module Identifier
  def compile
    ['V', text_value]
  end
end

module Command
  def compile
    case elements.first.text_value
    when 'accelerate' then
      x_val.compile + y_val.compile + ['accel']
    else fail "Unexpected: #{text_value}"
    end
  end
end

module SpecialInteger
  def compile
    case text_value
    when 'X' then ['X']
    when 'Y' then ['Y']
    else fail "Unexpected: #{text_value}"
    end
  end
end

module Integer
  def compile
    ['P', text_value.to_i]
  end
end

module Negation
  def compile
    comparison.compile + ['!']
  end
end

module Boolean
  def compile
    ['P', text_value == 'true']
  end
end

end
end

if $0 == __FILE__
  input = ARGV.join(' ')
  parser = Game2D::GibberParser.new
  if result = parser.parse(input)
    # puts result.inspect
    puts result.value({})
  else
    puts "Parsing error at (#{parser.failure_line}, #{parser.failure_column})"
    puts parser.failure_reason
  end
end
