# frozen_string_literal: true

require "spec_helper"
RSpec.describe SidekiqPrometheus::PeriodicMetrics do
  let(:senate) { double "Sidekiq::Senate", leader: true }
  let(:stats_class) { double "Sidekiq::Stats" }
  let(:sidekiq_queue) { double "Sidekiq::Queue" }
  let(:registry) { instance_double Prometheus::Client::Registry }
  let(:metric) { double "Metric", set: true, increment: true, observe: true }
  let(:num) { rand(100) }
  let(:reporter) { described_class.new(sidekiq_stats: stats_class, sidekiq_queue: sidekiq_queue, senate: senate) }

  after do
    SidekiqPrometheus.registry = SidekiqPrometheus.client.registry
  end

  describe "contructor" do
    it "creates a reporter" do
      r = described_class.new(sidekiq_stats: stats_class)
      expect(r.senate).to eq(SidekiqPrometheus::PeriodicMetrics::Senate)

      expect(r.done).to be false
    end

    it "sets done to false" do
      r = described_class.new(sidekiq_stats: stats_class)
      expect(r.done).to be false
    end

    it "sets leader to false" do
      r = described_class.new(sidekiq_stats: stats_class)
      expect(r.leader).to be false
    end
  end

  describe "#start" do
    it "starts a reporter in a new thread" do
      allow(Thread).to receive(:new)

      reporter.start

      expect(Thread).to have_received(:new) { |&block| expect(block).to be_kind_of(Proc) }
    end
  end

  describe "#stop" do
    it "sets done to true" do
      reporter.stop

      expect(reporter.done).to be true
    end
  end

  describe "#report_gc_metrics" do
    it "records gc metrics" do
      SidekiqPrometheus.registry = registry
      allow(registry).to receive(:get).and_return(metric)

      reporter.report_gc_metrics

      expect(metric).to have_received(:increment).with(by: kind_of(Numeric), labels: {}).exactly(described_class::GC_STATS[:counters].size).times
      # plus one because rss
      expect(metric).to have_received(:set).with(kind_of(Numeric), labels: {}).exactly(described_class::GC_STATS[:gauges].size + 1).times
    end
  end

  describe "#report_global_metrics" do
    let(:sidekiq_stats) { double "Sidekiq::Stats.new" }
    let(:queue) { double "instance of Sidekiq::Queue", name: "critical", size: 42, latency: 1 }
    let(:another_queue) { double "another Sidekiq::Queue", name: "low", size: 0, latency: 0 }

    before do
      allow(stats_class).to receive(:new).and_return(sidekiq_stats)
      allow(sidekiq_queue).to receive(:all).and_return([queue, another_queue])
    end

    it "records global sidekiq stat metrics" do
      SidekiqPrometheus.registry = registry
      allow(registry).to receive(:get).and_return(metric)

      described_class::GLOBAL_STATS.each do |stat|
        allow(sidekiq_stats).to receive(stat).and_return(num)
      end

      reporter.report_global_metrics

      described_class::GLOBAL_STATS.each do |stat|
        expect(sidekiq_stats).to have_received(stat)
      end

      expect(metric).to have_received(:set).with(num, labels: {}).exactly(described_class::GLOBAL_STATS.size).times

      expect(metric).to have_received(:set).with(queue.size, labels: {queue: queue.name})
      expect(metric).to have_received(:observe).with(queue.latency, labels: {queue: queue.name})
      expect(metric).to have_received(:set).with(another_queue.size, labels: {queue: another_queue.name})
      expect(metric).to have_received(:observe).with(another_queue.latency, labels: {queue: another_queue.name})
    end
  end

  describe "#report_redis_metrics" do
    let(:fake_info) do
      {
        "connected_clients" => "1",
        "used_memory" => "1024",
        "used_memory_peak" => "2048",
        "db0" => "keys=1,expires=0,avg_ttl=0",
        "db1" => "keys=100,expires=10,avg_ttl=1000"
      }
    end

    it "returns nil if there is no connection to redis" do
      allow(Sidekiq).to receive(:redis_info).and_raise(Redis::BaseConnectionError)

      expect(reporter.report_redis_metrics).to be nil
    end

    it "records redis metrics" do
      SidekiqPrometheus.registry = registry
      allow(registry).to receive(:get).and_return(metric)
      allow(Sidekiq).to receive(:redis_info).and_return(fake_info)

      reporter.report_redis_metrics

      expect(metric).to have_received(:set).with(1, labels: {})
      expect(metric).to have_received(:set).with(1024, labels: {})
      expect(metric).to have_received(:set).with(2048, labels: {})
      expect(metric).to have_received(:set).with(1, labels: {database: "db0"})
      expect(metric).to have_received(:set).with(0, labels: {database: "db0"})
      expect(metric).to have_received(:set).with(100, labels: {database: "db1"})
      expect(metric).to have_received(:set).with(10, labels: {database: "db1"})
    end
  end

  describe "#handle_leader_state" do
    it "registers metrics and updates local state when the instance is elected leader" do
      r = described_class.new(sidekiq_stats: stats_class)
      expect(r.leader).to be false
      allow(SidekiqPrometheus::Metrics).to receive(:register_sidekiq_global_metrics)

      senate_leader = true
      r.handle_leader_state(senate_leader)

      expect(r.leader).to be true
      expect(SidekiqPrometheus::Metrics).to have_received(:register_sidekiq_global_metrics)
    end

    it "unregisters metrics and updates local state when the instance is demoted" do
      r = described_class.new(sidekiq_stats: stats_class)
      r.leader = true
      allow(SidekiqPrometheus::Metrics).to receive(:unregister_sidekiq_global_metrics)

      senate_leader = false
      r.handle_leader_state(senate_leader)

      expect(r.leader).to be false
      expect(SidekiqPrometheus::Metrics).to have_received(:unregister_sidekiq_global_metrics)
    end

    it "it does nothing if senate.leader? is true and the instance is already leader" do
      r = described_class.new(sidekiq_stats: stats_class)
      r.leader = true
      allow(SidekiqPrometheus::Metrics).to receive(:register_sidekiq_global_metrics)
      allow(SidekiqPrometheus::Metrics).to receive(:unregister_sidekiq_global_metrics)
      expect(r.leader).to be true

      senate_leader = true
      r.handle_leader_state(senate_leader)

      #expect(r.leader).to be true
      expect(SidekiqPrometheus::Metrics).not_to have_received(:register_sidekiq_global_metrics)
      expect(SidekiqPrometheus::Metrics).not_to have_received(:unregister_sidekiq_global_metrics)
    end

    it "does nothing if senate.leader? is false and the instance is not the leader" do
      r = described_class.new(sidekiq_stats: stats_class)
      allow(SidekiqPrometheus::Metrics).to receive(:unregister_sidekiq_global_metrics)

      senate_leader = false
      r.handle_leader_state(senate_leader)

      expect(r.leader).to be false
      expect(SidekiqPrometheus::Metrics).not_to have_received(:unregister_sidekiq_global_metrics)
    end
  end
end
