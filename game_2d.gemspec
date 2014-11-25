# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'game_2d/version'

Gem::Specification.new do |spec|
  spec.name          = "game_2d"
  spec.version       = Game2d::VERSION
  spec.authors       = ["Greg Meyers"]
  spec.email         = ["cmdr.samvimes@gmail.com"]
  spec.summary       = %q{Client/server sandbox game using Gosu and REnet}
  spec.description   = %q{Client/server sandbox game using Gosu and REnet}
  spec.homepage      = ""
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]
  spec.required_ruby_version = ">= 1.9.3"

  spec.add_runtime_dependency "facets", [">= 2.9.3"]
  spec.add_runtime_dependency "gosu", [">= 0.8.5"]
  spec.add_runtime_dependency "json", [">= 1.8.1"]
  spec.add_runtime_dependency "renet", [">= 0.1.14"]
  spec.add_runtime_dependency "trollop", [">= 2.0"]

  spec.add_development_dependency "bundler", "~> 1.7"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "rr", "~> 1.1.2"
  spec.add_development_dependency "rspec", "~> 3.1.0"
end
