# Sidekiq Prometheus


[![Status](https://travis-ci.org/fastly/sidekiq-prometheus.svg?branch=main)](https://travis-ci.org/fastly/sidekiq-prometheus)
![Gem](https://img.shields.io/gem/v/sidekiq_prometheus.svg?color=blue)
[![MIT license](http://img.shields.io/badge/license-MIT-brightgreen.svg)](http://opensource.org/licenses/MIT)

Prometheus Instrumentation for Sidekiq. This gem provides:

* Sidekiq server middleware for reporting job metrics
* Global metrics reporter that uses the Sidekiq API for reporting Sidekiq cluster stats (*requires Sidekiq::Enterprise*)
* Sidecar Rack server to provide scrape-able endpoint for Prometheus. This allows for metrics to be reported without having to run a separate prometheus exporter process.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'sidekiq_prometheus'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install sidekiq_prometheus

## Usage

To run with the defaults add this to your Sidekiq initializer

```
SidekiqPrometheus.setup
```

This will register metrics, start the global reporter (if available), and start the Rack server for scraping. The default port is 9359 but this is easily configurable.

Once Sidekiq server is running you can see your metrics or scrape them with Prometheus:

```
$curl http://localhost:9359/metrics

# TYPE sidekiq_job_count counter
# HELP sidekiq_job_count Count of Sidekiq jobs
# TYPE sidekiq_job_duration histogram
# HELP sidekiq_job_duration Sidekiq job processing duration

[etc]
```

[Full documentation](https://www.rubydoc.info/gems/sidekiq_prometheus)

## Configuration

You can configure the gem by calling `configure`:

```ruby
SidekiqPrometheus.configure do |config|
  config.preset_labels = { service: 'kubernandos_api' }
end
```

`configure` will automatically call setup so

If you are running multiple services that will be reporting Sidekiq metrics you will want to take advantage of the `preset_labels` configuration option. For example:

```ruby
SidekiqPrometheus.configure do |config|
  config.preset_labels  = { service: 'image_api' }
  config.metrics_port = 9090
end
```

#### Configuration options

* `preset_labels`: Hash of labels that will be included with every metric when they are registered. `Hash{Symbol (label name) => String (label value)}`
* `custom_labels`: Hash of metrics and labels that can be applied to specific metrics. The metric name must be a registered metric. `Hash{Symbol (metric name) => Array<Symbol> (label names)}`
* `gc_metrics_enabled`: Boolean that determines whether to record object allocation metrics per job. The default is `true`. Setting this to `false` if you don't need this metric.
* `global_metrics_enabled`: Boolean that determines whether to report global metrics from the PeriodicMetrics reporter. When `true` this will report on a number of stats from the Sidekiq API for the cluster. This requires Sidekiq::Enterprise as the reporter uses the leader election functionality to ensure that only one worker per cluster is reporting metrics.
* `init_label_sets`: Hash of metrics and label sets that are initialized by calling `metric.init_label_set` after the metric is registered. See[ prometheus-client docs](https://github.com/prometheus/client_ruby/tree/e144d6225d3c346e9a4dd0a11f41f8acde386dd8#init_label_set) for details. `Hash{Symbol (metric name) => Array<Hash> (label sets)}`.
* `periodic_metrics_enabled`: Boolean that determines whether to run the periodic metrics reporter. `PeriodicMetrics` runs a separate thread that reports on global metrics (if enabled) as well worker GC stats (if enabled). It reports metrics on the interval defined by `periodic_reporting_interval`. Defaults to `true`.
* `periodic_reporting_interval`: interval in seconds for reporting periodic metrics. Default: `30`
* `metrics_server_enabled`: Boolean that determines whether to run the rack server. Defaults to `true`
* `metrics_server_logger_enabled`: Boolean that determines if the metrics server will log access logs. Defaults to `true`
* `metrics_host`: Host on which the rack server will listen. Defaults to
  `localhost`
* `metrics_port`: Port on which the rack server will listen. Defaults to `9359`
* `registry`: An instance of `Prometheus::Client::Registry`. If you have a registry with defined metrics you can use this option to pass in your registry.

```ruby
SidekiqPrometheus.configure do |config|
  config.preset_labels                 = { service: 'myapp' }
  config.custom_labels                 = { sidekiq_job_count: [:worker_class, :job_type, :any_other_label] }
  config.gc_metrics_enabled            = false
  config.global_metrics_enabled        = true
  config.init_label_sets               = { sidekiq_job_count: [{worker_class: "class", job_type: "single", any_other_label: "value"}, {worker_class: "class", job_type: "batch", any_other_label: "other-value"}] }
  config.periodic_metrics_enabled      = true
  config.periodic_reporting_interval   = 20
  config.metrics_server_enabled        = true
  config.metrics_port                  = 8675
end
```

Custom labels may be added by defining the `prometheus_labels` method in the worker class,
prior you need to register the custom labels as of the above example:

```ruby
class SomeWorker
  include Sidekiq::Worker

  def prometheus_labels
    { some: 'label' }
  end
end
```

## Metrics

### JobMetrics

All Sidekiq job metrics are reported with these labels:

* `class`: Sidekiq worker class name
* `queue`: Sidekiq queue name

| Metric | Type | Description |
|--------|------|-------------|
| sidekiq_job_count | counter | Count of Sidekiq jobs |
| sidekiq_job_duration | histogram | Sidekiq job processing duration |
| sidekiq_job_success | counter | Count of successful Sidekiq jobs |
| sidekiq_job_allocated_objects | histogram | Count of ruby objects allocated by a Sidekiq job |
| sidekiq_job_failed | counter | Count of failed Sidekiq jobs |
| sidekiq_job_over_limit | counter | Count of over limit Sidekiq jobs |


Notes:

* when a job fails only `sidekiq_job_count` and `sidekiq_job_failed` will be reported.
* when a job fails due to Sidekiq::Limiter::OverLimit error, only `sidekiq_job_count` and `sidekiq_job_over_limit` will be reported.
* `sidekiq_job_allocated_objects` will only be reported if `SidekiqPrometheus.gc_metrics_enabled? == true`

### Periodic GC Metrics

These require `SidekiqPrometheus.gc_metrics_enabled? == true` and `SidekiqPrometheus.periodic_metrics_enabled? == true`

| Metric | Type | Description |
|--------|------|-------------|
| sidekiq_allocated_objects | counter | Count of allocated objects by the worker |
| sidekiq_heap_free_slots | gauge | Number of free heap slots as reported by GC.stat |
| sidekiq_heap_live_slots | gauge | Number of live heap slots as reported by GC.stat |
| sidekiq_major_gc_count | counter | Count of major GC runs |
| sidekiq_minor_gc_count | counter | Count of minor GC runs |
| sidekiq_rss | gauge | RSS memory usage for worker process |

### Periodic Global Metrics

These require `SidekiqPrometheus.global_metrics_enabled? == true` and `SidekiqPrometheus.periodic_metrics_enabled? == true`

Periodic metric reporting relies on Sidekiq Enterprise's leader election functionality ([Ent Leader Election ](https://github.com/mperham/sidekiq/wiki/Ent-Leader-Election))
which ensures that metrics are only reported once per cluster.

| Metric | Type | Description |
|--------|------|-------------|
| sidekiq_workers_size | gauge | Total number of workers processing jobs |
| sidekiq_dead_size | gauge | Total Dead Size |
| sidekiq_enqueued | gauge | Total Size of all known queues |
| sidekiq_queue_latency | summary | Latency (in seconds) of all queues |
| sidekiq_failed | gauge | Number of job executions which raised an error |
| sidekiq_processed | gauge | Number of job executions completed (success or failure) |
| sidekiq_retry_size | gauge | Total Retries Size |
| sidekiq_scheduled_size | gauge | Total Scheduled Size |
| sidekiq_redis_connected_clients | gauge | Number of clients connected to Redis instance for Sidekiq |
| sidekiq_redis_used_memory | gauge | Used memory from Redis.info
| sidekiq_redis_used_memory_peak | gauge | Used memory peak from Redis.info |
| sidekiq_redis_keys | gauge | Number of redis keys |
| sidekiq_redis_expires | gauge | Number of redis keys with expiry set |

The global metrics are reported with the only the `preset_labels` with the exception of `sidekiq_enqueued` which will add a `queue` label and record a metric per Sidekiq queue.

## Custom Worker Metrics

There are a few different ways to register custom metrics with SidekiqPrometheus. Each custom metric should be defined as a Hash with the following form:

```ruby
{
  name:        :metric_name,
  type:        :gauge,
  docstring:   'description',
  preset_labels: { label_name: 'label_text' },
}
```

* `:name` (required) - Unique name of the metric and should be a symbol.
* `:type` (required) - Prometheus metric type. Supported values are: `:counter`, `:gauge`, `:histogram`, and `:summary`.
* `:docstring` (required) - Human readable description of the metric.
* `:preset_labels` (optional) - Hash of labels that will be applied to every instance of this metric.

#### Registering custom metrics:

Registering a set of custom metrics is done by defining `custom_metrics` in the `configure` block:

```ruby
SidekiqPrometheus.configure do |config|
  config.custom_metrics = [
    { name: :imported_records, type: :counter, docstring: 'Count of successfully imported records' },
    { name: :failed_records,   type: counter:, docstring: 'Count of failed records' },
  ]
end
```

Metrics can also be registered directly. This must done *after* `SidekiqPrometheus.configure` or `setup` has been run.

```ruby
SidekiqPrometheus::Metrics.register(name: :logged_in_users, type: :gauge, docstring: 'Logged in users')
```

There is also a method to register more than one metric at a time:

```ruby
customer_worker_metrics = [
  {
    name: :file_count, type: :counter, docstring: 'Number of active files',
    name: :file_size,  type: :gauge,   docstring: 'Size of files in bytes',
  }
]

SidekiqPrometheus::Metrics.register_metrics(customer_worker_metrics)
```

#### Using custom metrics:

Once metrics are registered they can be used in your Sidekiq workers.

```ruby
class ImportWorker
  include Sidekiq::Worker

  LABELS = {}

  def perform(*args)
    # worker code

    SidekiqPrometheus[:file_count].increment(LABELS, new_file_count)
    SidekiqPrometheus[:file_size].set(LABELS, total_file_size)
  end

end
```

See the [documentation of the Prometheus::Client library](https://github.com/prometheus/client_ruby) for all of the available options for setting metric values.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`.

## Contributors

See: https://github.com/fastly/sidekiq-prometheus/graphs/contributors

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/fastly/sidekiq-prometheus. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct.

## Copyright

Copyright 2019 Fastly, Inc.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the SidekiqPrometheus project’s codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/fastly/sidekiq-prometheus/blob/main/CODE_OF_CONDUCT.md).

# Metadata

- Ignore
