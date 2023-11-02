# frozen_string_literal: true

require "spec_helper"

class FakeWork
  def prometheus_labels
    {foo: "bar"}
  end
end

RSpec.describe SidekiqPrometheus::JobMetrics do
  let(:middleware) { described_class.new }
  let(:registry) { instance_double Prometheus::Client::Registry }
  let(:metric) { double "Metric", increment: true, observe: true }
  let(:worker) { FakeWork.new }
  let(:queue) { "bbq" }
  let(:job) { {} }
  let(:labels) { {class: worker.class.to_s, queue: queue, foo: "bar"} }
  let(:failed_labels) { labels.merge(error_class: RuntimeError.to_s) }

  after do
    SidekiqPrometheus.registry = SidekiqPrometheus.client.registry
  end

  describe "#call" do
    context "when Sidekiq::Limiter module is not defined" do
      before do
        # Ensure that if this module _is_ defined (depending on random spec
        # execution order) that we remove it so we can test the fallback
        # behavior.
        if defined?(Sidekiq::Limiter)
          Sidekiq.send(:remove_const, :Limiter)
        end
      end

      it "handles other errors with the fallback sidekiq_job_failed metric" do
        SidekiqPrometheus.registry = registry
        allow(registry).to receive(:get).and_return(metric)

        expect { middleware.call(worker, job, queue) { raise StandardError } }.to raise_error(StandardError)

        expect(registry).not_to have_received(:get).with(:sidekiq_job_over_limit)
        expect(registry).to have_received(:get).with(:sidekiq_job_count)
        expect(registry).to have_received(:get).with(:sidekiq_job_failed)

        expect(registry).not_to have_received(:get).with(:sidekiq_job_duration)
        expect(registry).not_to have_received(:get).with(:sidekiq_job_success)

        expect(metric).to have_received(:increment).once.with(labels: labels)
        expect(metric).to have_received(:increment).once.with(labels: labels.merge(error_class: "StandardError"))
        expect(metric).not_to have_received(:observe)
      end
    end

    context "when Sidekiq::Limiter::OverLimit class is defined" do
      before do
        unless defined?(Sidekiq::Limiter::OverLimit)
          module Sidekiq::Limiter
            class OverLimit < StandardError
            end
          end
        end
      end

      it "records the expected metrics" do
        SidekiqPrometheus.registry = registry
        allow(registry).to receive(:get).and_return(metric)

        expect { |b| middleware.call(worker, job, queue, &b) }.to yield_control

        expect(registry).to have_received(:get).with(:sidekiq_job_count)
        expect(registry).to have_received(:get).with(:sidekiq_job_duration)
        expect(registry).to have_received(:get).with(:sidekiq_job_success)
        expect(registry).to have_received(:get).with(:sidekiq_job_allocated_objects)

        expect(metric).to have_received(:increment).twice.with(labels: labels)
        expect(metric).to have_received(:observe).twice.with(kind_of(Numeric), labels: labels)
      end

      it "returns the result from the yielded block" do
        SidekiqPrometheus.registry = registry
        allow(registry).to receive(:get).and_return(metric)
        expected = "Zoot Boot"

        result = middleware.call(worker, job, queue) { expected }

        expect(result).to eq(expected)
      end

      it "increments the sidekiq_job_failed metric on error and raises" do
        SidekiqPrometheus.registry = registry
        allow(registry).to receive(:get).and_return(metric)

        expect { middleware.call(worker, job, queue) { raise "no way!" } }.to raise_error(StandardError)

        expect(registry).to have_received(:get).with(:sidekiq_job_count)
        expect(registry).to have_received(:get).with(:sidekiq_job_failed)
        expect(registry).not_to have_received(:get).with(:sidekiq_job_duration)
        expect(registry).not_to have_received(:get).with(:sidekiq_job_success)

        expect(metric).to have_received(:increment).once.with(labels: failed_labels)
        expect(metric).to have_received(:increment).once.with(labels: labels)
        expect(metric).not_to have_received(:observe)
      end

      it "handles sidekiq ent Sidekiq::Limiter::OverLimit errors independently of failures" do
        SidekiqPrometheus.registry = registry
        allow(registry).to receive(:get).and_return(metric)

        expect { middleware.call(worker, job, queue) { raise Sidekiq::Limiter::OverLimit } }.to raise_error(Sidekiq::Limiter::OverLimit)

        expect(registry).to have_received(:get).with(:sidekiq_job_count)
        expect(registry).to have_received(:get).with(:sidekiq_job_over_limit)
        expect(registry).not_to have_received(:get).with(:sidekiq_job_failed)
        expect(registry).not_to have_received(:get).with(:sidekiq_job_duration)
        expect(registry).not_to have_received(:get).with(:sidekiq_job_success)

        expect(metric).to have_received(:increment).twice.with(labels: labels)
        expect(metric).not_to have_received(:observe)
      end

      context "when worker class is ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper" do
        let(:wrapped_class) { "WrappedActiveJobClass" }
        let(:job) { {"wrapped" => wrapped_class} }
        let(:labels) { {class: wrapped_class, queue: queue, foo: "bar"} }

        it "sets the metric class attribute to the wrapped class" do
          SidekiqPrometheus.registry = registry
          allow(registry).to receive(:get).and_return(metric)

          expect { |b| middleware.call(worker, job, queue, &b) }.to yield_control

          expect(registry).to have_received(:get).with(:sidekiq_job_count)
          expect(registry).to have_received(:get).with(:sidekiq_job_duration)
          expect(registry).to have_received(:get).with(:sidekiq_job_success)
          expect(registry).to have_received(:get).with(:sidekiq_job_allocated_objects)

          expect(metric).to have_received(:increment).twice.with(labels: labels)
          expect(metric).to have_received(:observe).twice.with(kind_of(Numeric), labels: labels)
        end
      end
    end
  end
end
