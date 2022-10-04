CHANGELOG

<a name="v1.8.0"></a>
## [v1.8.0](https://github.com/fastly/sidekiq-prometheus/compare/v1.7.0...v1.8.0) (2022-10-04)

### Features

* handle rate limiting exceptions distinctly from other exceptions ([#28](https://github.com/fastly/sidekiq-prometheus/issues/28))

### Pull Requests

* Merge pull request [#27](https://github.com/fastly/sidekiq-prometheus/issues/27) from pinkahd/patch-1


<a name="v1.7.0"></a>
## [v1.7.0](https://github.com/fastly/sidekiq-prometheus/compare/v1.6.0...v1.7.0) (2022-09-29)

### Bug Fixes

* s/metrics_server_logging_enabled/metrics_server_logger_enabled/

### Features

* add Sidekiq::Stats processes_size to the periodic metrics

### Pull Requests

* Merge pull request [#30](https://github.com/fastly/sidekiq-prometheus/issues/30) from fastly/add_processes_size


<a name="v1.6.0"></a>
## [v1.6.0](https://github.com/fastly/sidekiq-prometheus/compare/v1.5.0...v1.6.0) (2021-08-03)

### Features

* add option for silencing the WEBrick access logging of /metrics

### Pull Requests

* Merge pull request [#25](https://github.com/fastly/sidekiq-prometheus/issues/25) from fastly/option_for_silencing_webrick


<a name="v1.5.0"></a>
## [v1.5.0](https://github.com/fastly/sidekiq-prometheus/compare/v1.4.0...v1.5.0) (2021-08-02)

### Pull Requests

* Merge pull request [#23](https://github.com/fastly/sidekiq-prometheus/issues/23) from fastly/rainy/add-error-class-label


<a name="v1.4.0"></a>
## [v1.4.0](https://github.com/fastly/sidekiq-prometheus/compare/v1.3.0...v1.4.0) (2021-03-30)

### Pull Requests

* Merge pull request [#21](https://github.com/fastly/sidekiq-prometheus/issues/21) from Kevinrob/patch-1


<a name="v1.3.0"></a>
## [v1.3.0](https://github.com/fastly/sidekiq-prometheus/compare/v1.2.0...v1.3.0) (2021-03-26)

### Pull Requests

* Merge pull request [#22](https://github.com/fastly/sidekiq-prometheus/issues/22) from mirubiri/add-active-job-support
* Merge pull request [#20](https://github.com/fastly/sidekiq-prometheus/issues/20) from fastly/aw/move-to-main

<a name="v1.2.0"></a>
## [v1.2.0](https://github.com/fastly/sidekiq-prometheus/compare/v1.1.0...v1.2.0) (2020-10-01)

### Feature

* allow the metrics host to be disabled with a configuration option
* use prometheus-client ~> 2.0

### Pull Requests

* Merge pull request [#18](https://github.com/fastly/sidekiq-prometheus/issues/18) from jetpks/release-120
* Merge pull request [#15](https://github.com/fastly/sidekiq-prometheus/issues/15) from silicakes/master
* Merge pull request [#17](https://github.com/fastly/sidekiq-prometheus/issues/17) from jetpks/add-option-to-disable-metrics-server

<a name="v1.1.0"></a>
## [v1.1.0](https://github.com/fastly/sidekiq-prometheus/compare/v1.0.1...v1.1.0) (2020-02-12)

### Feature

* allow for configuration of the metrics host (instead of always binding to 127.0.0.1)
* Use prometheus-client ~> 1.0.0

### Pull Requests

* Merge pull request [#13](https://github.com/fastly/sidekiq-prometheus/issues/13) from postmodern/metrics_host
* Merge pull request [#11](https://github.com/fastly/sidekiq-prometheus/issues/11) from rossjones/patch-1
* Merge pull request [#12](https://github.com/fastly/sidekiq-prometheus/issues/12) from fastly/hr

<a name="v1.0.1"></a>
## [v1.0.1](https://github.com/fastly/sidekiq-prometheus/compare/v0.9.2...v1.0.1) (2019-10-30)

### Pull Requests

* Merge pull request [#9](https://github.com/fastly/sidekiq-prometheus/issues/9) from we4tech/features/update-prometheus-client


<a name="v1.0.0"></a>
## [v1.0.0](https://github.com/fastly/sidekiq-prometheus/compare/v0.9.1...v1.0.0) (2019-10-24)

### Pull Requests

* Merge pull request [#9](https://github.com/fastly/sidekiq-prometheus/issues/9) from we4tech/features/update-prometheus-client


<a name="v0.9.2"></a>
## [v0.9.2](https://github.com/fastly/sidekiq-prometheus/compare/v1.0.0...v0.9.2) (2019-10-30)


<a name="v0.9.1"></a>
## [v0.9.1](https://github.com/fastly/sidekiq-prometheus/compare/v0.9.0...v0.9.1) (2019-07-08)

### Bug Fixes

* properly alias configure!


<a name="v0.9.0"></a>
## [v0.9.0](https://github.com/fastly/sidekiq-prometheus/compare/v0.8.1...v0.9.0) (2019-03-18)

### Features

* Custom Metrics

### Pull Requests

* Merge pull request [#4](https://github.com/fastly/sidekiq-prometheus/issues/4) from fastly/custom_metrics-fix[#2](https://github.com/fastly/sidekiq-prometheus/issues/2)
* Merge pull request [#3](https://github.com/fastly/sidekiq-prometheus/issues/3) from fastly/doc_refinement_(fix-[#1](https://github.com/fastly/sidekiq-prometheus/issues/1))


<a name="v0.8.1"></a>
## v0.8.1 (2019-02-08)

