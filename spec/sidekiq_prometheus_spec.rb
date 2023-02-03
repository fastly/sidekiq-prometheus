# frozen_string_literal: true

require "net/http"
require "spec_helper"

# this will allow us to call Sidekiq.configure_server
require "sidekiq/cli"

RSpec.describe SidekiqPrometheus do
  before do
    described_class.registry = Prometheus::Client::Registry.new
    described_class.setup_complete = false
  end

  it "has a version number" do
    expect(SidekiqPrometheus::VERSION).not_to be nil
  end

  describe ".configure" do
    it "yields self" do
      expect { |c| described_class.configure(&c) }.to yield_control
    end

    it "configures" do
      base = {label: "label"}
      described_class.configure do |c|
        c.preset_labels = base
      end

      expect(described_class.preset_labels).to eq base
    end

    it "calls setup" do
      allow(described_class).to receive(:setup)

      described_class.configure {}

      expect(described_class).to have_received(:setup)
    end
  end

  describe ".gc_metrics_enabled?" do
    it "returns true by default" do
      expect(described_class.gc_metrics_enabled).to be true
      expect(described_class.gc_metrics_enabled?).to be true
    end

    it "returns false when gc_metrics_enabled == false" do
      described_class.gc_metrics_enabled = false
      expect(described_class.gc_metrics_enabled?).to be false
    end
  end

  describe ".periodic_metrics_enabled?" do
    it "returns true by default" do
      expect(described_class.periodic_metrics_enabled).to be true
      expect(described_class.periodic_metrics_enabled?).to be true
    end

    it "returns false when periodic_metrics_enabled == false" do
      described_class.periodic_metrics_enabled = false
      expect(described_class.periodic_metrics_enabled?).to be false
    end
  end

  describe ".metrics_server_enabled?" do
    it "returns true by default" do
      expect(described_class.metrics_server_enabled).to be true
      expect(described_class.metrics_server_enabled?).to be true
    end

    it "returns false when metrics_server_enabled == false" do
      described_class.metrics_server_enabled = false
      expect(described_class.metrics_server_enabled?).to be false
    end
  end

  describe ".metrics_server_logger_enabled?" do
    it "returns true by default" do
      expect(described_class.metrics_server_logger_enabled).to be true
      expect(described_class.metrics_server_logger_enabled?).to be true
    end

    it "returns false when metrics_server_logger_enabled == false" do
      described_class.metrics_server_logger_enabled = false
      expect(described_class.metrics_server_logger_enabled?).to be false
    end
  end

  describe ".register_custom_metrics" do
    after do
      described_class.custom_metrics = []
    end

    it "does nothing if no custom metrics are defined" do
      allow(SidekiqPrometheus::Metrics).to receive(:register_metrics)

      expect(described_class.custom_metrics).to eq []
      expect(described_class.register_custom_metrics).to be nil
      expect(SidekiqPrometheus::Metrics).not_to have_received(:register_metrics)
    end

    it "raises an error if custom_metrics is not an Array" do
      allow(SidekiqPrometheus::Metrics).to receive(:register_metrics)

      described_class.custom_metrics = {name: :foo, type: :gauge, docstring: "asd"}

      expect { described_class.register_custom_metrics }.to raise_error(SidekiqPrometheus::Error)
    end

    it "registers the custom metrics" do
      custom = [
        {
          name: :rpm,
          type: :gauge,
          docstring: "revolutions per minute"
        }
      ]

      described_class.custom_metrics = custom
      described_class.register_custom_metrics

      expect(described_class.get(:rpm)).to be_kind_of(Prometheus::Client::Gauge)
    end
  end

  describe ".setup" do
    it "registers metrics and instruments sidekiq for prometheus" do
      allow(Object).to receive(:const_defined?).with("Sidekiq::Enterprise").and_return(true)
      described_class.gc_metrics_enabled = true
      described_class.periodic_metrics_enabled = true

      described_class.setup

      expect(Sidekiq.default_configuration.server_middleware.entries.last.klass).to eq(SidekiqPrometheus::JobMetrics)

      events = Sidekiq.default_configuration[:lifecycle_events]
      expect(events[:startup].first).to be_kind_of(Proc)
      expect(events[:shutdown].first).to be_kind_of(Proc)
    end

    it "registers custom metrics" do
      custom = [{name: :rpm, type: :gauge, docstring: "rpm"}]

      described_class.custom_metrics = custom
      described_class.setup

      expect(described_class.get(:rpm)).to be_kind_of(Prometheus::Client::Gauge)

      described_class.custom_metrics = []
    end

    it "can only be called once" do
      allow(Object).to receive(:const_defined?).with("Sidekiq::Enterprise").and_return(true)
      allow(SidekiqPrometheus::Metrics).to receive(:register_sidekiq_job_metrics)

      described_class.setup
      result = described_class.setup

      expect(result).to be false
      expect(SidekiqPrometheus::Metrics).to have_received(:register_sidekiq_job_metrics).once
    end
  end

  describe ".metrics_server" do
    it "starts a rack server in a new thread" do
      silence do
        SidekiqPrometheus::Metrics.register_sidekiq_job_metrics
        thread = described_class.metrics_server

        sleep 1

        http = Net::HTTP.new(SidekiqPrometheus.metrics_host, SidekiqPrometheus.metrics_port)
        res = http.request(Net::HTTP::Get.new("/metrics"))

        expect(res.code).to eq "200"
        expect(res.body).to match(/sidekiq_job_count/)

        thread.kill
      end
    end
  end
end
