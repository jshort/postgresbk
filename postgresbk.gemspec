# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "postgresbk/version"

Gem::Specification.new do |s|
  s.name        = "postgresbk"
  s.version     = Postgresbk::VERSION
  s.platform    = Gem::Platform::RUBY
  s.authors     = ["James Short"]
  s.email       = ["james.short@alumni.duke.edu"]
  s.homepage    = ""
  s.summary     = %q{Gem for backing up PostgreSQL databases including quiescing and unquiescing}
  s.description = %q{Gem for backing up PostgreSQL databases including quiescing and unquiescing}

  s.add_runtime_dependency "pg"
  s.add_development_dependency "rspec", "~>2.5.0"

  s.files = Dir['lib/**/*.rb'] + Dir['bin/*']
  s.files += Dir['[A-Z]*'] + Dir['test/**/*']
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = ['postgresbk']
  s.require_paths = ["lib"]
end
