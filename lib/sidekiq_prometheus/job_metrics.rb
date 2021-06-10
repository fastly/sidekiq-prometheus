# frozen_string_literal: true

class SidekiqPrometheus::JobMetrics
  def call(worker, job, queue)
    before = GC.stat(:total_allocated_objects) if SidekiqPrometheus.gc_metrics_enabled?

    # If we're using a wrapper class, like ActiveJob, use the "wrapped"
    # attribute to expose the underlying thing.
    labels = {
      class: job['wrapped'] || worker.class.to_s,
      queue: queue,
    }

    begin
      labels.merge!(custom_labels(worker))

      result = nil
      duration = Benchmark.realtime { result = yield }

      # In case the labels have changed after the worker perform method has been called
      labels.merge!(custom_labels(worker))

      registry[:sidekiq_job_duration].observe(duration, labels: labels)
      registry[:sidekiq_job_success].increment(labels: labels)

      if SidekiqPrometheus.gc_metrics_enabled?
        allocated = GC.stat(:total_allocated_objects) - before
        registry[:sidekiq_job_allocated_objects].observe(allocated, labels: labels)
      end

      result
    rescue StandardError => e
      err_label = { :error_class => e.class.to_s }
      registry[:sidekiq_job_failed].increment(labels: err_label.merge(labels))
      raise e
    ensure
      registry[:sidekiq_job_count].increment(labels: labels)
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
