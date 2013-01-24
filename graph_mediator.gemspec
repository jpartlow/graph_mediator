lib = File.expand_path('../lib/', __FILE__)
$:.unshift lib unless $:.include?(lib)

require 'graph_mediator/version'

Gem::Specification.new do |s|
  s.name = %q{graph_mediator}
  s.version = GraphMediator::VERSION
  s.required_rubygems_version = ">= 1.3.6"

  s.authors = ["Josh Partlow"]
  s.email = %q{jpartlow@glatisant.org}
  s.summary = %q{Mediates ActiveRecord state changes}
  s.description = %q{Mediates state changes between a set of interdependent ActiveRecord objects.}
  s.homepage = %q{http://github.com/jpartlow/graph_mediator}
  s.extra_rdoc_files = [
    "LICENSE",
    "README.rdoc"
  ]
  s.rdoc_options = ["--main=README.rdoc", "--charset=UTF-8"]
  s.require_paths = ["lib"]
  s.rubygems_version = %q{1.3.6}
  s.files = `git ls-files`.split("\n")
  s.test_files = `git ls-files spec/*`.split("\n")

  s.add_development_dependency(%q<rspec>, [">= 1.2.9"])
  s.add_development_dependency(%q<diff-lcs>)
  s.add_development_dependency(%q<sqlite3>)
  s.add_runtime_dependency(%q<activerecord>, [">= 2.3.6", "< 3.0.0"])
  s.add_runtime_dependency(%q<activesupport>, [">= 2.3.6", "< 3.0.0"])
  s.add_runtime_dependency(%q<aasm>, [">= 2.2.0"])
end

