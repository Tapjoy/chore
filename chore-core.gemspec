# -*- encoding: utf-8 -*-
$: << File.expand_path('lib', File.dirname(__FILE__))

require 'chore/version'

Gem::Specification.new do |s|
  s.name = "chore-core"
  s.version = Chore::Version::STRING

  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=
  s.authors = ["Tapjoy"]
  s.date = Time.new.strftime("%Y-%m-%d")
  s.description = "Job processing with pluggable backends and strategies"
  s.email = "eng-group-arch@tapjoy.com"

  s.executables = Dir["bin/*"].map { |f| f.gsub(/bin\//, '') }
  s.default_executable = "chore"

  s.extra_rdoc_files = [
    "LICENSE.txt",
    "README.md"
  ]
  s.files = Dir[*%w(
    chore-core.gemspec
    LICENSE.txt
    README.md
    Rakefile
    bin/*
    lib/**/*
    spec/**/*
  )]

  s.homepage = "http://github.com/Tapjoy/chore"
  s.licenses = ["MIT"]
  s.require_paths = ["lib"]
  s.rubygems_version = "1.8.25"
  s.summary = "Job processing... for the future!"

  s.add_runtime_dependency(%q<json>, [">= 0"])
  s.add_runtime_dependency(%q<aws-sdk>, ["~> 1.12", ">= 1.12.0"])
  s.add_runtime_dependency(%q<thread>, ["~> 0.1.3"])
  s.add_development_dependency(%q<rspec>, ["~> 2.12.0"])
  s.add_development_dependency(%q<rdoc>, ["~> 3.12"])
  s.add_development_dependency(%q<bundler>, [">= 0"])
end

