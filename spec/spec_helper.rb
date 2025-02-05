# frozen_string_literal: true

require "bundler/setup"
require "sidekiq_prometheus"

Bundler.require(:test)

RSpec.configure do |config|
  config.example_status_persistence_file_path = ".rspec_status"
  config.disable_monkey_patching!
  config.filter_run :focus
  config.run_all_when_everything_filtered = true
end

def silence
  original_stderr = $stderr
  original_stdout = $stdout

  # Redirect stderr and stdout
  $stderr = $stdout = StringIO.new

  yield

  $stderr = original_stderr
  $stdout = original_stdout
end

Sidekiq.configure_server do |cfg|
  cfg.logger = Logger.new(File::NULL)
end
