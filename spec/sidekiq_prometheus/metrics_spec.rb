# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SidekiqPrometheus::Metrics do
  let(:registry) { Prometheus::Client::Registry.new }
  before { SidekiqPrometheus.registry = registry }

  describe '.registry' do
    it 'returns the SidekiqPrometheus.registry' do
      expect(described_class.registry).to eq(SidekiqPrometheus.registry)
    end
  end

  describe '.get' do
    it 'fetches a metric from the client registry' do
      registry.counter(:somecounter, docstring: 'somecounter')

      expect(described_class.get(:somecounter)).not_to be_nil
    end
  end

  describe '.register' do
    it 'registers a metric in the client registry' do
      metric = {
        type: :counter,
        name: :metric,
        docstring: 'this is a metric',
      }

      described_class.register(**metric)

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
      expect { described_class.register(**metric) }.to raise_error(SidekiqPrometheus::Metrics::InvalidMetricType)
    end

    context 'with preset_labels' do
      before do
        SidekiqPrometheus.preset_labels = { service1: 'hello world', service2: 'hello world 2' }

        metric = {
          type: :counter, name: :a_metric, docstring: 'something better',
          labels: %i[label1 label2],
        }

        @registered_metric = described_class.register(**metric)
      end

      after { SidekiqPrometheus.preset_labels = {} }

      subject { described_class.get(:a_metric) }

      it 'registers a metric with aggregated labels from preset_labels and the method parameter labels' do
        expect(subject.instance_variable_get(:@labels)).to be == %i[label1 label2 service1 service2]
      end

      it 'raises InvalidLabelSetError error if any required label is missing' do
        expect { subject.increment }.to raise_error(Prometheus::Client::LabelSetValidator::InvalidLabelSetError)
      end

      it 'records a new data' do
        subject.increment(labels: { label1: 'label1', label2: 'label2' })
      end
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
