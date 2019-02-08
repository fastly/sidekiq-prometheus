# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SidekiqPrometheus::Metrics do
  describe '.registry' do
    it 'returns the SidekiqPrometheus.registry' do
      expect(described_class.registry).to eq(SidekiqPrometheus.registry)
    end
  end

  describe '.get' do
    it 'fetches a metric from the client registry' do
      Prometheus::Client.registry.counter(:somecounter, 'somecounter')

      expect(described_class.get(:somecounter)).not_to be nil
    end
  end

  describe '.register' do
    it 'registers a metric in the client registry' do
      metric = {
        type: :counter,
        name: :metric,
        docstring: 'this is a metric',
      }

      described_class.register(metric)

      expected = described_class.get(:metric)
      expect(expected).not_to be nil
      expect(expected).to be_kind_of(Prometheus::Client::Counter)
    end

    it 'raises an error when the metric type is invalid' do
      metric = {
        type: :zootboot,
        name: :metric,
        docstring: 'this is a metric',
      }
      expect { described_class.register(metric) }.to raise_error(SidekiqPrometheus::Metrics::InvalidMetricType)
    end
  end

  describe 'register_sidekiq_job_metrics' do
    it 'registers job metrics' do
      described_class.register_sidekiq_job_metrics

      described_class::SIDEKIQ_JOB_METRICS.each do |metric|
        expect(described_class.get(metric[:name])).not_to be nil
      end
    end
  end

  describe 'register_sidekiq_gc_metric' do
    it 'registers a GC metric' do
      described_class.register_sidekiq_gc_metric

      expect(described_class.get(described_class::SIDEKIQ_GC_METRIC[:name])).not_to be nil
    end
  end

  describe 'register_sidekiq_global_metrics' do
    it 'registers global metrics' do
      described_class.register_sidekiq_global_metrics

      described_class::SIDEKIQ_GLOBAL_METRICS.each do |metric|
        expect(described_class.get(metric[:name])).not_to be nil
      end
    end
  end
end
