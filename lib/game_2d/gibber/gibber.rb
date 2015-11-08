require 'treetop'

Treetop.load "#{File.dirname __FILE__}/gibber.treetop"

module Game2D
module Gibber

module Program
  def value(this, context)
    sequence.value(this, context)
  end
end

module Sequence
  def value(this, context)
    statements = [first_stmt] + rest.elements.map(&:stmt)
    statements.each do |s|
      context['_'] = s.value(this, context)
    end
    context['_']
  end
end

module Loop
  def value(this, context)
    while comparison.value(this, context)
      sequence.value(this, context)
    end
  end
end

module Conditional
  def value(this, context)
    if comparison.value(this, context)
      true_seq.value(this, context)
    elsif false_part.respond_to? :false_seq
      false_part.false_seq.value(this, context)
    end
  end
end

module Ternary
  def value(this, context)
    (
      comparison.value(this, context) ? true_exp : false_exp
    ).value(this, context)
  end
end

module Assignment
  def value(this, context)
    name = identifier.text_value.to_sym
    context[name] = expression.value(this, context)
  end
end

module Val
  def value(this, context)
    val.value(this, context)
  end
end

module Math
  def value(this, context)
    op.value(this, context,
             left.value(this, context),
             right.value(this, context))
  end
end

module MathOperator
  def value(this, context, a, b)
    a.send(text_value.to_sym, b)
  end
end

module IsDefined
  def value(this, context)
    name = identifier.text_value.to_sym
    context.include? name
  end
end

module Identifier
  def value(this, context)
    name = text_value.to_sym
    fail "Uninitialized variable '#{name}'" unless
      context.include? name
    context[name]
  end
end

module Command
  def value(this, context)
    case elements.first.text_value
    when 'accelerate' then
      this.accelerate x_val.value(this, context),
                      y_val.value(this, context)
    else fail "Unexpected: #{text_value}"
    end
  end
end

module SpecialInteger
  def value(this, context)
    case text_value
    when 'X' then this.x
    when 'Y' then this.y
    else fail "Unexpected: #{text_value}"
    end
  end
end

module Integer
  def value(this, context)
    text_value.to_i
  end
end

module Negation
  def value(this, context)
    ! comparison.value(this, context)
  end
end

module Boolean
  def value(this, context)
    text_value == 'true'
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
