# frozen_string_literal: true

module SidekiqPrometheus::Metrics
  module_function

  UNKNOWN = 'unknown'

  VALID_TYPES = %i[counter gauge histogram summary].freeze
  JOB_LABELS = %i[class queue].freeze
  SIDEKIQ_GLOBAL_METRICS = [
    { name:      :sidekiq_workers_size,
      type:      :gauge,
      docstring: 'Total number of workers processing jobs', },
    { name:      :sidekiq_dead_size,
      type:      :gauge,
      docstring: 'Total Dead Size', },
    { name:      :sidekiq_enqueued,
      type:      :gauge,
      docstring: 'Total Size of all known queues',
      labels:    %i[queue], },
    { name:      :sidekiq_queue_latency,
      type:      :summary,
      docstring: 'Latency (in seconds) of all queues',
      labels:    %i[queue], },
    { name:      :sidekiq_failed,
      type:      :gauge,
      docstring: 'Number of job executions which raised an error', },
    { name:      :sidekiq_processed,
      type:      :gauge,
      docstring: 'Number of job executions completed (success or failure)', },
    { name:      :sidekiq_retry_size,
      type:      :gauge,
      docstring: 'Total Retries Size', },
    { name:      :sidekiq_scheduled_size,
      type:      :gauge,
      docstring: 'Total Scheduled Size', },
    { name:      :sidekiq_redis_connected_clients,
      type:      :gauge,
      docstring: 'Number of clients connected to Redis instance for Sidekiq', },
    { name:      :sidekiq_redis_used_memory,
      type:      :gauge,
      docstring: 'Used memory from Redis.info', },
    { name:      :sidekiq_redis_used_memory_peak,
      type:      :gauge,
      docstring: 'Used memory peak from Redis.info', },
    { name:      :sidekiq_redis_keys,
      type:      :gauge,
      docstring: 'Number of redis keys',
      labels:     %i[database], },
    { name:      :sidekiq_redis_expires,
      type:      :gauge,
      docstring: 'Number of redis keys with expiry set',
      labels:     %i[database], },
  ].freeze
  SIDEKIQ_JOB_METRICS = [
    { name:      :sidekiq_job_count,
      type:      :counter,
      docstring: 'Count of Sidekiq jobs',
      labels:    JOB_LABELS, },
    { name:      :sidekiq_job_duration,
      type:      :histogram,
      docstring: 'Sidekiq job processing duration',
      labels:    JOB_LABELS, },
    { name:      :sidekiq_job_failed,
      type:      :counter,
      docstring: 'Count of failed Sidekiq jobs',
      labels:    JOB_LABELS, },
    { name:      :sidekiq_job_success,
      type:      :counter,
      docstring: 'Count of successful Sidekiq jobs',
      labels:    JOB_LABELS, },
  ].freeze
  SIDEKIQ_GC_METRIC = {
    name:      :sidekiq_job_allocated_objects,
    type:      :histogram,
    docstring: 'Count of ruby objects allocated by a Sidekiq job',
    buckets:   [10, 50, 100, 500, 1_000, 2_500, 5_000, 10_000, 50_000, 100_000, 500_000, 1_000_000, 5_000_000, 10_000_000, 25_000_000],
    labels:    JOB_LABELS,
  }.freeze
  SIDEKIQ_WORKER_GC_METRICS = [
    { name:      :sidekiq_allocated_objects,
      type:      :counter,
      docstring: 'Count of ruby objects allocated by a Sidekiq worker', },
    { name:      :sidekiq_heap_free_slots,
      type:      :gauge,
      docstring: 'Sidekiq worker GC.stat[:heap_free_slots]', },
    { name:      :sidekiq_heap_live_slots,
      type:      :gauge,
      docstring: 'Sidekiq worker GC.stat[:heap_live_slots]', },
    { name:      :sidekiq_major_gc_count,
      type:      :counter,
      docstring: 'Sidekiq worker GC.stat[:major_gc_count]', },
    { name:      :sidekiq_minor_gc_count,
      type:      :counter,
      docstring: 'Sidekiq worker GC.stat[:minor_gc_count]', },
    { name:      :sidekiq_rss,
      type:      :gauge,
      docstring: 'Sidekiq process RSS', },
  ].freeze

  def registry
    SidekiqPrometheus.registry
  end

  def register_sidekiq_job_metrics
    register_metrics SIDEKIQ_JOB_METRICS
  end

  def register_sidekiq_gc_metric
    register(**SIDEKIQ_GC_METRIC)
  end

  def register_sidekiq_worker_gc_metrics
    register_metrics SIDEKIQ_WORKER_GC_METRICS
  end

  def register_sidekiq_global_metrics
    register_metrics SIDEKIQ_GLOBAL_METRICS
  end

  def register_metrics(metrics)
    metrics.each do |metric|
      register(**metric)
    end
  end

  ##
  # Fetch a metric from the registry
  # @param name [Symbol] name of metric to fetch
  def [](name)
    registry.get(name.to_sym)
  end

  class << self
    alias get []
  end

  ##
  # Register a new metric
  # @param types [Symbol] type of metric to register. Valid types: %w(counter gauge summary histogram)
  # @param name [Symbol] name of metric
  # @param docstring [String] help text for metric
  # @param labels [Array] Optionally an array of labels to configure for every instance of this metric
  # @param preset_labels [Hash] Optionally a Hash of labels to use for every instance of this metric
  # @param buckets [Hash] Optional hash of bucket values. Only used for histogram metrics.
  def register(type:, name:, docstring:, labels: [], preset_labels: {}, buckets: nil)
    raise InvalidMetricType, type unless VALID_TYPES.include? type

    # Aggregate all preset labels
    all_preset_labels = preset_labels.dup
    all_preset_labels.merge!(SidekiqPrometheus.preset_labels) if SidekiqPrometheus.preset_labels

    # Aggregate all labels
    all_labels = labels | SidekiqPrometheus.custom_labels.fetch(name, []) | all_preset_labels.keys

    options = { docstring: docstring,
                labels: all_labels,
                preset_labels: all_preset_labels, }

    options[:buckets] = buckets if buckets

    registry.send(type, name.to_sym, **options)
  end

  def unregister(name:)
    registry.unregister(name.to_sym)
  end

  class InvalidMetricType < StandardError; end
end
