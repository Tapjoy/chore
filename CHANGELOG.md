# Change Log

## [master](https://github.com/Tapjoy/chore/tree/master)

**Features**
- N/A

**Fixed bugs**
- N/A

**Cleanups**
- N/A

## [v4.0.0](https://github.com/Tapjoy/chore/tree/v4.0.0)

**Features**

- AWS SDK library has been updated to support AWS authentication via
[Web Federated Identity](https://docs.aws.amazon.com/sdk-for-javascript/v2/developer-guide/loading-browser-credentials-federated-id.html)
  - The API has jumped ahead 2 major versions, so some of the internals (e.g.
    [`Chore::UnitOfWork`](lib/chore/unit_of_work.rb)) had to be changed to accommodate its changes. In the end, however,
    this update is designed to function as a drop-in replacement for earlier versions of Chore

**Fixed bugs**

- Some of the SQS specs were not actually testing output values

**Cleanups**

- Many more YARD docs
- Documented the release process
- Mild overhaul of the base README

## [v3.1.0](https://github.com/Tapjoy/chore/tree/v3.1.0) (2017-09-15)

**Features**
- N/A

**Fixed bugs**
- Fix the filesystem publisher potentially leaving job files locked for process's lifetime

**Cleanups**
- N/A

## [v3.0.2](https://github.com/Tapjoy/chore/tree/v3.0.2) (2017-09-07)

**Features**
- N/A

**Fixed bugs**
- Fix the filesystem consumer processing incomplete job files

**Cleanups**
- N/A

## [v3.0.1](https://github.com/Tapjoy/chore/tree/v3.0.1) (2017-09-07)

**Features**
- N/A

**Fixed bugs**
- Fix performance regression when listing files in the filesystem queue

**Cleanups**
- N/A

## [v3.0.0](https://github.com/Tapjoy/chore/tree/v3.0.0) (2017-09-06)

**Features**
- Improve filesystem consumer speed by allowing configuration of time between filesystem lookups
- Limit the number of files pulled from the filesystem queue on each iteration
  to avoid performance impact with large queue backlogs
- Reduce number of open files in the filesystem consumer
- Improve filesystem consumer speed by using non-blocking locks on new jobs
- Support running multiple threaded consumers with the filesystem queue
- Improve performance of filesystem queue deletions
- Support recovery of expired jobs in the filesystem queue (this allows for
  multi-master or forked worker strategies)
- Allow master / worker proclines to be customized

**Fixed bugs**
- N/A

**Cleanups**
- N/A

## [v2.0.5](https://github.com/Tapjoy/chore/tree/v2.0.5) (2017-08-15)

**Features**
- N/A

**Fixed bugs**
- N/A

**Cleanups**
- Improved performance of running hooks

## [v2.0.4](https://github.com/Tapjoy/chore/tree/v2.0.4) (2017-03-27)
**Features**
- N/A

**Fixed bugs**
- Master process hangs if consumer threads block shutdown.

**Cleanups**
- Added more logging to the shutdown path


## [v2.0.3](https://github.com/Tapjoy/chore/tree/v2.0.3) (2017-01-10)
**Features**
- Added Travis CI Testing

**Fixed bugs**
- Added socket cleanup for reaped workers in preforked worker configuration.

**Cleanups**
- Added better exception logging for debugging

## [v2.0.2](https://github.com/Tapjoy/chore/tree/v2.0.2) (2016-06-16)
**Fixed bugs**
- Added handling for USR1 signal for Preforked worker strategy

**Cleanups**
- Changed log statements for startup protocol for better debugging

[Full Changelog](https://github.com/Tapjoy/chore/compare/v2.0.1...v2.0.2)

## [v2.0.1](https://github.com/Tapjoy/chore/tree/v2.0.1) (2016-06-09)

**Fixed bugs**
- Added handling for after_fork hook for Preforked worker strategy

[Full Changelog](https://github.com/Tapjoy/chore/compare/v2.0.0...v2.0.1)

## [v2.0.0](https://github.com/Tapjoy/chore/tree/v2.0.0) (2016-06-03)

**Features**
- Added preforked worker strategy
- Added throttled consumer strategy

[Full Changelog](https://github.com/Tapjoy/chore/compare/v1.10.0...v2.0.0)

## [v1.10.0](https://github.com/Tapjoy/chore/tree/v1.10.0) (2016-03-24)
[Full Changelog](https://github.com/Tapjoy/chore/compare/v1.9.0...v1.10.0)

## [v1.9.0](https://github.com/Tapjoy/chore/tree/v1.9.0) (2016-03-09)
[Full Changelog](https://github.com/Tapjoy/chore/compare/v1.8.4...v1.9.0)

## [v1.8.4](https://github.com/Tapjoy/chore/tree/v1.8.4) (2016-02-02)
[Full Changelog](https://github.com/Tapjoy/chore/compare/v1.8.3...v1.8.4)

## [v1.8.3](https://github.com/Tapjoy/chore/tree/v1.8.3) (2016-02-01)
[Full Changelog](https://github.com/Tapjoy/chore/compare/v1.8.2...v1.8.3)

## [v1.8.2](https://github.com/Tapjoy/chore/tree/v1.8.2) (2016-01-28)
[Full Changelog](https://github.com/Tapjoy/chore/compare/v1.8.1...v1.8.2)

## [v1.8.1](https://github.com/Tapjoy/chore/tree/v1.8.1) (2016-01-22)
[Full Changelog](https://github.com/Tapjoy/chore/compare/v1.8.0...v1.8.1)

## [v1.8.0](https://github.com/Tapjoy/chore/tree/v1.8.0) (2015-12-15)
[Full Changelog](https://github.com/Tapjoy/chore/compare/v1.7.2...v1.8.0)

## [v1.7.2](https://github.com/Tapjoy/chore/tree/v1.7.2) (2015-12-08)
[Full Changelog](https://github.com/Tapjoy/chore/compare/v1.5.10...v1.7.2)

## [v1.5.10](https://github.com/Tapjoy/chore/tree/v1.5.10) (2015-07-08)
[Full Changelog](https://github.com/Tapjoy/chore/compare/v1.5.2...v1.5.10)

## [v1.5.2](https://github.com/Tapjoy/chore/tree/v1.5.2) (2014-09-29)
[Full Changelog](https://github.com/Tapjoy/chore/compare/v1.5.1...v1.5.2)

## [v1.5.1](https://github.com/Tapjoy/chore/tree/v1.5.1) (2014-08-25)
[Full Changelog](https://github.com/Tapjoy/chore/compare/v1.5.0...v1.5.1)

## [v1.5.0](https://github.com/Tapjoy/chore/tree/v1.5.0) (2014-07-09)
[Full Changelog](https://github.com/Tapjoy/chore/compare/v1.4.0...v1.5.0)

## [v1.4.0](https://github.com/Tapjoy/chore/tree/v1.4.0) (2014-05-23)
[Full Changelog](https://github.com/Tapjoy/chore/compare/v1.3.0...v1.4.0)

## [v1.3.0](https://github.com/Tapjoy/chore/tree/v1.3.0) (2014-04-25)
[Full Changelog](https://github.com/Tapjoy/chore/compare/v1.2.11...v1.3.0)

## [v1.2.11](https://github.com/Tapjoy/chore/tree/v1.2.11) (2014-03-11)
[Full Changelog](https://github.com/Tapjoy/chore/compare/v1.2.10...v1.2.11)

## [v1.2.10](https://github.com/Tapjoy/chore/tree/v1.2.10) (2014-01-15)
[Full Changelog](https://github.com/Tapjoy/chore/compare/v1.2.9...v1.2.10)

## [v1.2.9](https://github.com/Tapjoy/chore/tree/v1.2.9) (2014-01-03)
[Full Changelog](https://github.com/Tapjoy/chore/compare/v1.2.8...v1.2.9)

## [v1.2.8](https://github.com/Tapjoy/chore/tree/v1.2.8) (2013-12-03)
[Full Changelog](https://github.com/Tapjoy/chore/compare/v1.2.7...v1.2.8)

## [v1.2.7](https://github.com/Tapjoy/chore/tree/v1.2.7) (2013-11-22)
[Full Changelog](https://github.com/Tapjoy/chore/compare/v1.2.6...v1.2.7)

## [v1.2.6](https://github.com/Tapjoy/chore/tree/v1.2.6) (2013-11-06)
[Full Changelog](https://github.com/Tapjoy/chore/compare/v1.2.5...v1.2.6)

## [v1.2.5](https://github.com/Tapjoy/chore/tree/v1.2.5) (2013-11-01)
[Full Changelog](https://github.com/Tapjoy/chore/compare/v1.2.4...v1.2.5)

## [v1.2.4](https://github.com/Tapjoy/chore/tree/v1.2.4) (2013-10-31)
[Full Changelog](https://github.com/Tapjoy/chore/compare/v1.2.3...v1.2.4)

## [v1.2.3](https://github.com/Tapjoy/chore/tree/v1.2.3) (2013-10-17)
[Full Changelog](https://github.com/Tapjoy/chore/compare/v1.2.2...v1.2.3)

## [v1.2.2](https://github.com/Tapjoy/chore/tree/v1.2.2) (2013-10-10)
[Full Changelog](https://github.com/Tapjoy/chore/compare/v1.2.1...v1.2.2)

## [v1.2.1](https://github.com/Tapjoy/chore/tree/v1.2.1) (2013-10-08)
[Full Changelog](https://github.com/Tapjoy/chore/compare/v1.2.0...v1.2.1)

## [v1.2.0](https://github.com/Tapjoy/chore/tree/v1.2.0) (2013-10-08)
[Full Changelog](https://github.com/Tapjoy/chore/compare/v1.1.8...v1.2.0)

## [v1.1.8](https://github.com/Tapjoy/chore/tree/v1.1.8) (2013-10-01)
[Full Changelog](https://github.com/Tapjoy/chore/compare/v1.1.7...v1.1.8)

## [v1.1.7](https://github.com/Tapjoy/chore/tree/v1.1.7) (2013-09-30)
[Full Changelog](https://github.com/Tapjoy/chore/compare/v1.1.6...v1.1.7)

## [v1.1.6](https://github.com/Tapjoy/chore/tree/v1.1.6) (2013-09-26)
[Full Changelog](https://github.com/Tapjoy/chore/compare/v1.1.5...v1.1.6)

## [v1.1.5](https://github.com/Tapjoy/chore/tree/v1.1.5) (2013-09-13)
[Full Changelog](https://github.com/Tapjoy/chore/compare/v1.1.4...v1.1.5)

## [v1.1.4](https://github.com/Tapjoy/chore/tree/v1.1.4) (2013-09-06)
[Full Changelog](https://github.com/Tapjoy/chore/compare/v1.1.3...v1.1.4)

## [v1.1.3](https://github.com/Tapjoy/chore/tree/v1.1.3) (2013-09-05)
[Full Changelog](https://github.com/Tapjoy/chore/compare/v1.1.2...v1.1.3)

## [v1.1.2](https://github.com/Tapjoy/chore/tree/v1.1.2) (2013-09-03)
[Full Changelog](https://github.com/Tapjoy/chore/compare/v1.1.1...v1.1.2)

## [v1.1.1](https://github.com/Tapjoy/chore/tree/v1.1.1) (2013-08-26)
[Full Changelog](https://github.com/Tapjoy/chore/compare/v1.1.0...v1.1.1)

## [v1.1.0](https://github.com/Tapjoy/chore/tree/v1.1.0) (2013-08-20)
[Full Changelog](https://github.com/Tapjoy/chore/compare/v1.0.2...v1.1.0)

## [v1.0.2](https://github.com/Tapjoy/chore/tree/v1.0.2) (2013-08-20)
[Full Changelog](https://github.com/Tapjoy/chore/compare/v1.0.1...v1.0.2)

## [v1.0.1](https://github.com/Tapjoy/chore/tree/v1.0.1) (2013-07-25)
[Full Changelog](https://github.com/Tapjoy/chore/compare/v1.0.0...v1.0.1)

## [v1.0.0](https://github.com/Tapjoy/chore/tree/v1.0.0) (2013-07-25)
[Full Changelog](https://github.com/Tapjoy/chore/compare/v0.10.0...v1.0.0)

## [v0.10.0](https://github.com/Tapjoy/chore/tree/v0.10.0) (2013-07-11)
[Full Changelog](https://github.com/Tapjoy/chore/compare/v0.9.0...v0.10.0)

## [v0.9.0](https://github.com/Tapjoy/chore/tree/v0.9.0) (2013-06-26)
[Full Changelog](https://github.com/Tapjoy/chore/compare/v0.8.0...v0.9.0)

## [v0.8.0](https://github.com/Tapjoy/chore/tree/v0.8.0) (2013-05-09)
[Full Changelog](https://github.com/Tapjoy/chore/compare/v0.7.0...v0.8.0)

## [v0.7.0](https://github.com/Tapjoy/chore/tree/v0.7.0) (2013-05-06)


\* *This Change Log was automatically generated by [github_changelog_generator](https://github.com/skywinder/Github-Changelog-Generator)*
