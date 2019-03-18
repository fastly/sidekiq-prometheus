# frozen_string_literal: true

require 'net/http'
require 'spec_helper'

# this will allow us to call Sidekiq.configure_server
require 'sidekiq/cli'

RSpec.describe SidekiqPrometheus do
  before do
    described_class.registry = Prometheus::Client::Registry.new
    described_class.setup_complete = false
  end

  it 'has a version number' do
    expect(SidekiqPrometheus::VERSION).not_to be nil
  end

  describe '.configure' do
    it 'yields self' do
      expect { |c| described_class.configure(&c) }.to yield_control
    end

    it 'configures' do
      base = { label: 'label' }
      described_class.configure do |c|
        c.base_labels = base
      end

      expect(described_class.base_labels).to eq base

      described_class.configure do |c|
        c.base_labels = nil
      end
    end
  end

  describe '.gc_metrics_enabled?' do
    it 'returns true by default' do
      expect(described_class.gc_metrics_enabled).to be true
      expect(described_class.gc_metrics_enabled?).to be true
    end

    it 'returns false when gc_metrics_enabled == false' do
      described_class.gc_metrics_enabled = false
      expect(described_class.gc_metrics_enabled?).to be false
    end
  end

  describe '.periodic_metrics_enabled?' do
    it 'returns true by default' do
      expect(described_class.periodic_metrics_enabled).to be true
      expect(described_class.periodic_metrics_enabled?).to be true
    end

    it 'returns false when periodic_metrics_enabled == false' do
      described_class.periodic_metrics_enabled = false
      expect(described_class.periodic_metrics_enabled?).to be false
    end
  end

  describe '.setup' do
    it 'registers metrics and instruments sidekiq for prometheus' do
      allow(Object).to receive(:const_defined?).with('Sidekiq::Enterprise').and_return(true)
      described_class.gc_metrics_enabled = true
      described_class.periodic_metrics_enabled = true

      described_class.setup

      expect(Sidekiq.server_middleware.entries.last.klass).to eq(SidekiqPrometheus::JobMetrics)

      events = Sidekiq.options[:lifecycle_events]
      expect(events[:startup].first).to be_kind_of(Proc)
      expect(events[:shutdown].first).to be_kind_of(Proc)
    end

    it 'can only be called once' do
      allow(Object).to receive(:const_defined?).with('Sidekiq::Enterprise').and_return(true)
      allow(SidekiqPrometheus::Metrics).to receive(:register_sidekiq_job_metrics)

      described_class.setup
      result = described_class.setup

      expect(result).to be false
      expect(SidekiqPrometheus::Metrics).to have_received(:register_sidekiq_job_metrics).once
    end
  end

  describe '.metrics_server' do
    it 'starts a rack server in a new thread' do
      silence do
        SidekiqPrometheus::Metrics.register_sidekiq_job_metrics
        thread = described_class.metrics_server

        sleep 0.5

        http = Net::HTTP.new('127.0.0.1', SidekiqPrometheus.metrics_port)
        res = http.request(Net::HTTP::Get.new('/metrics'))

        expect(res.code).to eq '200'
        expect(res.body).to match(/sidekiq_job_count/)

        thread.kill
      end
    end
  end
end
