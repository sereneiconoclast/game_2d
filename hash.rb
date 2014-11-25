require 'facets/array/recurse'
require 'facets/hash/recurse'
require 'facets/hash/symbolize_keys'

class Hash
  def fix_keys
    recurse(Hash, Array) do |x|
      x.is_a?(Hash) ? x.symbolize_keys : x
    end
  end
end