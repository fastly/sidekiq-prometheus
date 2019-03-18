# frozen_string_literal: true

require 'benchmark'
require 'rack'
require 'prometheus/client'
require 'prometheus/middleware/exporter'
require 'sidekiq'
require 'sidekiq/api'

begin
  require 'sidekiq/ent'
rescue LoadError
end

module SidekiqPrometheus
  class << self
    # @return [Hash] Base labels applied to every registered metric
    attr_accessor :base_labels

    # @return [Hash] Custom labels applied to specific metrics
    attr_accessor :custom_labels

    # @return [Boolean] Setting to control enabling/disabling GC metrics. Default: true
    attr_accessor :gc_metrics_enabled

    # @return [Boolean] Setting to control enabling/disabling global metrics. Default: true
    attr_accessor :global_metrics_enabled

    # @return [Boolean] Setting to control enabling/disabling periodic metrics. Default: true
    attr_accessor :periodic_metrics_enabled

    # @return [Integer] Interval in seconds to record metrics. Default: 30
    attr_accessor :periodic_reporting_interval

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
  self.metrics_port = 9359
  self.custom_labels = {}

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
  #     config.base_labels = { service: 'images_api' }
  #     config.custom_labels = { sidekiq_job_count: { object_klass: nil } }
  #     config.gc_metrics_enabled = true
  #   end
  def configure
    yield self
    setup
  end

  alias configure! configure

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
  # Get a metric from the registry
  # @param metric [Symbol] name of metric to fetch
  # @return [Prometheus::Client::Metric]
  def [](metric)
    registry.get(metric.to_sym)
  end

  class << self
    alias get []
  end

  ##
  # Prometheus client metric registry
  # @return [Prometheus::Client::Registry]
  def registry
    @registry ||= client::Registry.new
  end

  ##
  # register metrics and instrument sidekiq
  def setup
    return false if @setup_complete
    SidekiqPrometheus::Metrics.register_sidekiq_job_metrics
    SidekiqPrometheus::Metrics.register_sidekiq_gc_metric if gc_metrics_enabled?
    SidekiqPrometheus::Metrics.register_sidekiq_worker_gc_metrics if gc_metrics_enabled? && periodic_metrics_enabled?
    SidekiqPrometheus::Metrics.register_sidekiq_global_metrics if global_metrics_enabled? && periodic_metrics_enabled?
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

      config.on(:startup)  { SidekiqPrometheus.metrics_server }
      config.on(:shutdown) { SidekiqPrometheus.metrics_server.kill }
    end
  end

  ##
  # Start a new Prometheus exporter in a new thread.
  # Will listen on SidekiqPrometheus.metrics_port
  def metrics_server
    @_metrics_server ||= Thread.new do
      Rack::Handler::WEBrick.run(
        Rack::Builder.new {
          use Prometheus::Middleware::Exporter, registry: SidekiqPrometheus.registry
          run ->(_) { [301, { 'Location' => '/metrics' }, []] }
        },
        Port: SidekiqPrometheus.metrics_port,
        BindAddress: '127.0.0.1',
      )
    end
  end
end

require 'sidekiq_prometheus/job_metrics'
require 'sidekiq_prometheus/metrics'
require 'sidekiq_prometheus/periodic_metrics'
require 'sidekiq_prometheus/version'
