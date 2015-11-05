# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'game_2d/version'

Gem::Specification.new do |spec|
  spec.name          = 'game_2d'
  spec.version       = Game2d::VERSION
  spec.authors       = ['Greg Meyers']
  spec.email         = ['cmdr.samvimes@gmail.com']
  spec.summary       = %q{Client/server sandbox game using Gosu and REnet}
  spec.description   = <<EOF
Built on top of Gosu, an engine for making 2-D games.  Gosu provides the means
to handle the graphics, sound, and keyboard/mouse events.  It doesn't provide
any sort of client/server network architecture for multiplayer games, nor a
system for tracking objects in game-space.  This gem aims to fill that gap.

Originally I tried using Chipmunk as the physics engine, but its outcomes were
too unpredictable for the client to anticipate the server.  It was also hard to
constrain in the ways I wanted.  So I elected to build something integer-based.

In the short term, I'm throwing anything into this gem that interests me.  There
are reusable elements (GameSpace, Entity, ServerPort), and game-specific
elements (particular Entity subclasses with custom behaviors).  Longer term, I
could see splitting it into two gems.  This gem, game_2d, would retain the
reusable platform classes.  The other classes would move into a new gem specific
to the game I'm developing, as a sort of reference implementation.
EOF
  spec.homepage      = 'https://github.com/sereneiconoclast/game_2d'
  spec.license       = 'MIT'

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ['lib']
  spec.required_ruby_version = '>= 1.9.3'

  spec.add_runtime_dependency 'clipboard', ['>= 1.0.6']
  spec.add_runtime_dependency 'facets', ['>= 2.9.3']
  spec.add_runtime_dependency 'gosu', ['>= 0.8.5']
  spec.add_runtime_dependency 'json', ['>= 1.8.1']
  spec.add_runtime_dependency 'renet', ['>= 0.1.14']
  spec.add_runtime_dependency 'trollop', ['>= 2.0']
# spec.add_runtime_dependency 'pry'

  spec.add_development_dependency 'bundler', '~> 1.7'
  spec.add_development_dependency 'rake', '~> 10.0'
  spec.add_development_dependency 'rr', '~> 1.1.2'
  spec.add_development_dependency 'rspec', '~> 3.1.0'
end
