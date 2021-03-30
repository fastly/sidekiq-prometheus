# frozen_string_literal: true

require 'benchmark'
require 'rack'
require 'prometheus/client'
require 'prometheus/middleware/exporter'
require 'sidekiq'
require 'sidekiq/api'
require 'webrick'

begin
  require 'sidekiq/ent'
rescue LoadError
end

module SidekiqPrometheus
  class << self
    # @return [Hash] Preset labels applied to every registered metric
    attr_accessor :preset_labels

    # @return [Hash{Symbol => Array<Symbol>}] Custom labels applied to specific metrics
    attr_accessor :custom_labels

    # @return [Array] Custom metrics that will be registered on setup.
    # @example
    #   [
    #     {
    #       name: :metric_name,
    #       type: :prometheus_metric_type,
    #       docstring: 'Description of the metric',
    #       preset_labels : { label: 'value' },
    #     }
    #   ]
    # @note Each element of the array is a hash and must have the required keys: `:name`, `:type`, and `:docstring`.
    #   The values for `:name` and `:type` should be symbols and `:docstring` should be a string.
    #   `preset_labels` is optional and, if used, must be a hash of labels that will be included on every instance of this metric.
    attr_accessor :custom_metrics

    # @return [Boolean] Setting to control enabling/disabling GC metrics. Default: true
    attr_accessor :gc_metrics_enabled

    # @return [Boolean] Setting to control enabling/disabling global metrics. Default: true
    attr_accessor :global_metrics_enabled

    # @return [Boolean] Setting to control enabling/disabling periodic metrics. Default: true
    attr_accessor :periodic_metrics_enabled

    # @return [Integer] Interval in seconds to record metrics. Default: 30
    attr_accessor :periodic_reporting_interval

    # @return [Boolean] Setting to control enabling/disabling the metrics server. Default: true
    attr_accessor :metrics_server_enabled

    # @return [String] Host on which the metrics server will listen. Default: localhost
    attr_accessor :metrics_host

    # @return [Integer] Port on which the metrics server will listen. Default: 9357
    attr_accessor :metrics_port

    # Override the default Prometheus::Client
    # @return [Prometheus::Client]
    attr_writer :client

    # Orverride the default Prometheus Metric Registry
    # @return [Prometheus::Client::Registry]
    attr_writer :registry

    # @private
    attr_writer :setup_complete
  end

  self.gc_metrics_enabled = true
  self.periodic_metrics_enabled = true
  self.global_metrics_enabled = true
  self.periodic_reporting_interval = 30
  self.metrics_server_enabled = true
  self.metrics_host = 'localhost'
  self.metrics_port = 9359
  self.custom_labels = {}
  self.custom_metrics = []

  module_function

  ##
  # @return Prometheus::Client
  def client
    @client ||= Prometheus::Client
  end

  ##
  # Configure SidekiqPrometheus and setup for reporting
  # @example
  #   SidekiqPrometheus.configure do |config|
  #     config.preset_labels = { service: 'images_api' }
  #     config.custom_labels = { sidekiq_job_count: [:custom_label_1, :custom_label_2] } }
  #     config.gc_metrics_enabled = true
  #   end
  def configure
    yield self
    setup
  end

  # Helper method for +gc_metrics_enabled+ configuration setting
  # @return [Boolean] defaults to true
  def gc_metrics_enabled?
    gc_metrics_enabled
  end

  ##
  # Helper method for +global_metrics_enabled+ configuration setting
  # Requires +Sidekiq::Enterprise+ as it uses the leader election functionality
  # @return [Boolean] defaults to true if +Sidekiq::Enterprise+ is available
  def global_metrics_enabled?
    Object.const_defined?('Sidekiq::Enterprise') && global_metrics_enabled
  end

  ##
  # Helper method for +periodic_metrics_enabled+ configuration setting
  # Requires +Sidekiq::Enterprise+ as it uses the leader election functionality
  # @return [Boolean] defaults to true if +Sidekiq::Enterprise+ is available
  def periodic_metrics_enabled?
    periodic_metrics_enabled
  end

  ##
  # Helper method for +metrics_server_enabled+ configuration setting
  # @return [Boolean] defaults to true
  def metrics_server_enabled?
    metrics_server_enabled
  end

  ##
  # Get a metric from the registry
  # @param metric [Symbol] name of metric to fetch
  # @return [Prometheus::Client::Metric]
  def [](metric)
    registry.get(metric.to_sym)
  end

  class << self
    alias configure! configure
    alias get []
  end

  ##
  # Prometheus client metric registry
  # @return [Prometheus::Client::Registry]
  def registry
    @registry ||= client::Registry.new
  end

  ##
  # Register custom metrics
  # Internal method called by +setup+. This method should not be called from application code in most cases.
  def register_custom_metrics
    return if custom_metrics.empty?

    raise SidekiqPrometheus::Error, 'custom_metrics is not an array.' unless custom_metrics.is_a?(Array)

    SidekiqPrometheus::Metrics.register_metrics(custom_metrics)
  end

  ##
  # register metrics and instrument sidekiq
  def setup
    return false if @setup_complete
    SidekiqPrometheus::Metrics.register_sidekiq_job_metrics
    SidekiqPrometheus::Metrics.register_sidekiq_gc_metric if gc_metrics_enabled?
    SidekiqPrometheus::Metrics.register_sidekiq_worker_gc_metrics if gc_metrics_enabled? && periodic_metrics_enabled?
    SidekiqPrometheus::Metrics.register_sidekiq_global_metrics if global_metrics_enabled? && periodic_metrics_enabled?
    register_custom_metrics

    sidekiq_setup

    self.setup_complete = true
  end

  ##
  # Add Prometheus instrumentation to sidekiq
  def sidekiq_setup
    Sidekiq.configure_server do |config|
      config.server_middleware do |chain|
        chain.add SidekiqPrometheus::JobMetrics
      end

      if periodic_metrics_enabled?
        config.on(:startup)  { SidekiqPrometheus::PeriodicMetrics.reporter.start }
        config.on(:shutdown) { SidekiqPrometheus::PeriodicMetrics.reporter.stop }
      end

      if metrics_server_enabled?
        config.on(:startup)  { SidekiqPrometheus.metrics_server }
        config.on(:shutdown) { SidekiqPrometheus.metrics_server.kill }
      end
    end
  end

  ##
  # Start a new Prometheus exporter in a new thread.
  # Will listen on SidekiqPrometheus.metrics_host and
  # SidekiqPrometheus.metrics_port
  def metrics_server
    @_metrics_server ||= Thread.new do
      Rack::Handler::WEBrick.run(
        Rack::Builder.new {
          use Prometheus::Middleware::Exporter, registry: SidekiqPrometheus.registry
          run ->(_) { [301, { 'Location' => '/metrics' }, []] }
        },
        Port: SidekiqPrometheus.metrics_port,
        Host: SidekiqPrometheus.metrics_host,
      )
    end
  end
end

class SidekiqPrometheus::Error < StandardError; end

require 'sidekiq_prometheus/job_metrics'
require 'sidekiq_prometheus/metrics'
require 'sidekiq_prometheus/periodic_metrics'
require 'sidekiq_prometheus/version'
