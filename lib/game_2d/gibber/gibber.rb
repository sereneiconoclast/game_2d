require 'treetop'

Treetop.load "#{File.dirname __FILE__}/gibber.treetop"

module Game2D
module Gibber

module Program
  def value(context)
    sequence.value(context)
  end
end

module Sequence
  def value(context)
    statements = [first_stmt] + rest.elements.map(&:stmt)
    statements.each do |s|
      context['_'] = s.value(context)
    end
    context['_']
  end
end

module Loop
  def value(context)
    while comparison.value(context)
      sequence.value(context)
    end
  end
end

module Conditional
  def value(context)
    if comparison.value(context)
      true_seq.value(context)
    elsif false_part.respond_to? :false_seq
      false_part.false_seq.value(context)
    end
  end
end

module Ternary
  def value(context)
    (
      comparison.value(context) ? true_exp : false_exp
    ).value(context)
  end
end

module Assignment
  def value(context)
    name = identifier.text_value.to_sym
    context[name] = expression.value(context)
  end
end

module Val
  def value(context)
    val.value(context)
  end
end

module Math
  def value(context)
    op.value(context, left.value(context), right.value(context))
  end
end

module MathOperator
  def value(context, a, b)
    a.send(text_value.to_sym, b)
  end
end

module IsDefined
  def value(context)
    name = identifier.text_value.to_sym
    context.include? name
  end
end

module Identifier
  def value(context)
    name = text_value.to_sym
    fail "Uninitialized variable '#{name}'" unless
      context.include? name
    context[name]
  end
end

module Integer
  def value(context)
    text_value.to_i
  end
end

module Negation
  def value(context)
    ! comparison.value(context)
  end
end

module Boolean
  def value(context)
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
