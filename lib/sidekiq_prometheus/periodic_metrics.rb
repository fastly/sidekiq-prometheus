# frozen_string_literal: true

##
# Report Sidekiq::Stats to prometheus on a defined interval
#
# Global Metrics reporting requires Sidekiq::Enterprise as it uses the leader
# election functionality to ensure that the global metrics are only reported by
# one worker.
#
# @see https://github.com/mperham/sidekiq/wiki/Ent-Leader-Election
# @see https://github.com/mperham/sidekiq/blob/master/lib/sidekiq/api.rb

class SidekiqPrometheus::PeriodicMetrics
  # @return [Boolean] When +true+ will stop the reporting loop.
  attr_accessor :done

  # @return [Integer] Interval in seconds to record metrics. Default: [SidekiqPrometheus.periodic_reporting_interval]
  attr_reader :interval
  attr_reader :senate, :sidekiq_stats, :sidekiq_queue

  GLOBAL_STATS = %i[failed processed retry_size dead_size scheduled_size workers_size].freeze
  GC_STATS = {
    counters: %i[major_gc_count minor_gc_count total_allocated_objects],
    gauges: %i[heap_live_slots heap_free_slots],
  }.freeze
  REDIS_STATS = %w[connected_clients used_memory used_memory_peak].freeze

  ##
  # Instance of SidekiqPrometheus::PeriodicMetrics
  # @return [SidekiqPrometheus:PeriodicMetrics]
  def self.reporter
    @reporter ||= new
  end

  ##
  # @param interval [Integer] Interval in seconds to record metrics.
  # @param sidekiq_stats [Sidekiq::Stats]
  # @param senate [#leader?] Sidekiq::Senate
  def initialize(interval: SidekiqPrometheus.periodic_reporting_interval, sidekiq_stats: Sidekiq::Stats, sidekiq_queue: Sidekiq::Queue, senate: nil)
    self.done = false
    @interval = interval

    @sidekiq_stats = sidekiq_stats
    @sidekiq_queue = sidekiq_queue
    @senate = if senate.nil?
                if Object.const_defined?('Sidekiq::Senate')
                  Sidekiq::Senate
                else
                  Senate
                end
              else
                senate
              end
  end

  ##
  # Start the period mettric reporter
  def start
    Sidekiq.logger.info('SidekiqPrometheus: Starting periodic metrics reporting')
    @thread = Thread.new(&method(:run))
  end

  ##
  ## Stop the periodic metric reporter
  def stop
    self.done = true
  end

  ##
  # Record GC and RSS metrics
  def report_gc_metrics
    stats = GC.stat
    GC_STATS[:counters].each do |stat|
      SidekiqPrometheus["sidekiq_#{stat}"]&.increment({}, stats[stat])
    end
    GC_STATS[:gauges].each do |stat|
      SidekiqPrometheus["sidekiq_#{stat}"]&.set({}, stats[stat])
    end

    SidekiqPrometheus[:sidekiq_rss]&.set({}, rss)
  end

  ##
  # Records Sidekiq global metrics
  def report_global_metrics
    current_stats = sidekiq_stats.new
    GLOBAL_STATS.each do |stat|
      SidekiqPrometheus["sidekiq_#{stat}"]&.set({}, current_stats.send(stat))
    end

    sidekiq_queue.all.each do |queue|
      SidekiqPrometheus[:sidekiq_enqueued]&.set({ queue: queue.name }, queue.size)
      SidekiqPrometheus[:sidekiq_queue_latency]&.observe({ queue: queue.name }, queue.latency)
    end
  end

  ##
  # Records metrics from Redis
  def report_redis_metrics
    redis_info = begin
      Sidekiq.redis_info
    rescue Redis::BaseConnectionError
      nil
    end

    return if redis_info.nil?

    REDIS_STATS.each do |stat|
      SidekiqPrometheus["sidekiq_redis_#{stat}"]&.set({}, redis_info[stat].to_i)
    end

    db_stats = redis_info.select { |k, _v| k.match(/^db/) }
    db_stats.each do |db, stat|
      label = { database: db }
      values = stat.scan(/\d+/)
      SidekiqPrometheus[:sidekiq_redis_keys]&.set(label, values[0].to_i)
      SidekiqPrometheus[:sidekiq_redis_expires]&.set(label, values[1].to_i)
    end
  end

  ##
  # Fetch rss from proc filesystem
  # @see https://github.com/discourse/prometheus_exporter/blob/v0.3.3/lib/prometheus_exporter/instrumentation/process.rb#L39-L42
  def rss
    pid = Process.pid
    @pagesize ||= `getconf PAGESIZE`.to_i rescue 4096
    File.read("/proc/#{pid}/statm").split(' ')[1].to_i * @pagesize rescue 0
  end

  ##
  # Report metrics and sleep for @interval seconds in a loop.
  # Runs until @done is true
  def run
    until done
      begin
        report_global_metrics if SidekiqPrometheus.global_metrics_enabled? && senate.leader?
        report_redis_metrics if SidekiqPrometheus.global_metrics_enabled? && senate.leader?
        report_gc_metrics if SidekiqPrometheus.gc_metrics_enabled?
      rescue StandardError => e
        Sidekiq.logger.error e
      ensure
        sleep interval
      end
    end
  end

  ##
  # Fake Senate class to guard against undefined constant errors.
  # @private
  class Senate
    def leader?
      false
    end
  end
end
