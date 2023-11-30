# frozen_string_literal: true

lib = File.expand_path("lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "sidekiq_prometheus/version"

Gem::Specification.new do |spec|
  spec.name = "sidekiq_prometheus"
  spec.version = SidekiqPrometheus::VERSION
  spec.authors = ["Lukas Eklund", "NHM Tanveer Hossain Khan"]
  spec.email = ["leklund@fastly.com"]

  spec.summary = "Prometheus Instrumentation for Sidekiq"
  spec.homepage = "https://github.com/fastly/sidekiq-prometheus"
  spec.license = "MIT"

  spec.files = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler"
  spec.add_development_dependency "pry"
  spec.add_development_dependency "rake", "~> 12.3.3"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "standard"

  spec.add_runtime_dependency "prometheus-client", ">= 2.0"
  spec.add_runtime_dependency "rack", " ~> 3.0"
  spec.add_runtime_dependency "redis"
  spec.add_runtime_dependency "sidekiq", "> 5.1"
  spec.add_runtime_dependency "puma"
end
