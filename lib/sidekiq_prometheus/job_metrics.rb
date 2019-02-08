# frozen_string_literal: true

class SidekiqPrometheus::JobMetrics
  def call(worker, _job, queue)
    before = GC.stat(:total_allocated_objects) if SidekiqPrometheus.gc_metrics_enabled?

    labels = { class: worker.class.to_s, queue: queue }

    begin
      labels.merge!(custom_labels(worker))

      result = nil
      duration = Benchmark.realtime { result = yield }

      # In case the labels have changed after the worker perform method has been called
      labels.merge!(custom_labels(worker))

      registry[:sidekiq_job_duration].observe(labels, duration)
      registry[:sidekiq_job_success].increment(labels)

      if SidekiqPrometheus.gc_metrics_enabled?
        allocated = GC.stat(:total_allocated_objects) - before
        registry[:sidekiq_job_allocated_objects].observe(labels, allocated)
      end

      result
    rescue StandardError => e
      registry[:sidekiq_job_failed].increment(labels)
      raise e
    ensure
      registry[:sidekiq_job_count].increment(labels)
    end
  end

  private

  def registry
    SidekiqPrometheus
  end

  def custom_labels(worker)
    worker.respond_to?(:prometheus_labels) ? worker.prometheus_labels : {}
  end
end
