lib = File.expand_path('../lib/', __FILE__)
$:.unshift lib unless $:.include?(lib)

require 'rubygems'
require 'rake'
require 'graph_mediator/version'

require 'spec/rake/spectask'
Spec::Rake::SpecTask.new(:spec) do |spec|
  spec.libs << 'lib' << 'spec'
  spec.spec_files = FileList['spec/**/*_spec.rb']
end

Spec::Rake::SpecTask.new(:rcov) do |spec|
  spec.libs << 'lib' << 'spec'
  spec.pattern = 'spec/**/*_spec.rb'
  spec.rcov = true
end

task :default => :spec

require 'rake/rdoctask'
Rake::RDocTask.new do |rdoc|
  version = GraphMediator::VERSION

  rdoc.rdoc_dir = 'rdoc'
  rdoc.title = "graph_mediator #{version}"
  rdoc.main = 'README.rdoc'
  rdoc.rdoc_files.include('README*')
  rdoc.rdoc_files.include('LICENSE*')
  rdoc.rdoc_files.include('lib/**/*.rb')
end
