# Chore: Async Job Processing Framework For Ruby

[![Build Status](https://travis-ci.org/Tapjoy/chore.svg?branch=master)](https://travis-ci.org/Tapjoy/chore)

## About

Chore is a pluggable, multi-backend job processing framework. It was built from the ground up to be extremely flexible.
We hope that you find integrating and using Chore to be as pleasant as we do.

The full docs for Chore can always be found at https://tapjoy.github.io/chore.

## Configuration

Chore can be integrated with any Ruby-based project by following these instructions:

1. Add `chore-core` to the Gemfile

    ```ruby
    gem 'chore-core', '~> 4.0.0'
    ```

    When using SQS, also add `dalli` to use for `memcached`-based deduplication:

    ```ruby
    gem 'dalli'
    ```

1. Create a `Chorefile` file in the root of the project directory. While Chore itself can be configured from this file,
it's primarily used to direct the Chore binstub toward the root of the application so that it can locate all of the
dependencies and required code.

    ```
    --require=./<FILE_TO_LOAD>
    ```

    Make sure that `--require` points to the main entry point for the application. If integrating with a Rails app,
    point it to the application directory and Chore will handle loading the correct files on its own.

1. When using SQS, ensure that AWS credentials exist in the environment (e.g. but not limited to `AWS_ACCESS_KEY_ID` &
`AWS_SECRET_ACCESS_KEY` environment variables) and an AWS region is set (e.g. `AWS_REGION` environment variable) so that
Chore can authenticate with AWS.

    By default, Chore will run over all queues it detects among the required files. If different behavior is desired,
    use one of the following flags:

    ```
    # Note that only one of these options may be used, not both. Chore will quit
    # if both options are specified.
    --queues QUEUE1,QUEUE2... # a list of queues to process
    --except-queues QUEUE1,QUEUE2... # a list of queues _not_ to process
    ```

1. Chore has many more options, which can be viewed by executing `bundle exec chore --help`

### Tips For Configuring Chore

For Rails, it can be necessary to add the jobs directory to the eager loading path, found in `application.rb`. A similar
approach for most apps using jobs is likely needed, unless the jobs are placed into a directory that is already eager
loaded by the application. One example of this might be:

```ruby
config.eager_load_paths += File.join(config.root, "app", "jobs")
```

However, due to the way `eager_load_paths` works in Rails, this may only solve the issue in the production environment.
It can also be useful useful for other environments to have something like this in an `config/initializers/chore.rb`
file, although the job files can be loaded in just about any way.

```ruby
if !Rails.env.production?
  Dir["#{Rails.root}/app/jobs/**/*"].each do |file|
    require file unless File.directory?(file)
  end
end
```

### Producing & Consuming Jobs

When it comes to configuring Chore, there are 2 main use configurations - as a producer of messages, or as a consumer of
messages. The consuming context may also messages if necessary, as it is running as its own isolated instance of the
application.

For producers, all of the Chore configuration must be in an initializer.

For consumers, a Chorefile must be used. A Chorefile _plus_ an initializer is also a good pattern.

Here's example of how to configure chore via an initializer:

```ruby
Chore.configure do |c|
  c.concurrency = 16
  c.worker_strategy = Chore::Strategy::ForkedWorkerStrategy
  c.max_attempts = 100
  ...
  c.batch_size = 50
  c.batch_timeout = 20
end
```

Because it is like that the same application serves as the basis for both producing and consuming messages, and there
will already be a considerable amount of configuration in the Producer, it makes sense to use Chorefile to simply
provide the `require` option and stick to the initializer for the rest of the configuration to keep things DRY.

However, like many aspects of Chore, it is ultimately up to the developer to decide which use case fits their needs
best. Chore is happy to be configured in almost any way a developer desires.

## Integration

This section assumes `foreman` is being used to execute (or export the run commands of) the application, but it is not
 strictly necessary.

1. Add an appropriate line to the `Procfile`:

    ```
    jobs: bundle exec chore -c config/chore.config
    ```

1. If the queues do not exist, they must be created before the application can produce/consume Chore jobs:

    ```ruby
    require 'aws-sdk-sqs'
    sqs = Aws::SQS::Client.new
    sqs.create_queue(queue_name: "test_queue")
    ```

1. Finally, start the application as usual

    ```
    bundle exec foreman start
    ```

## `Chore::Job`

A `Chore::Job` is any class with `include Chore::Job` and implements a `perform(*args)` instance method. Here is an
example job class:

```ruby
class TestJob
  include Chore::Job
  queue_options :name => 'test_queue'

  def perform(args={})
    Chore.logger.debug "My first async job"
  end
end
```

This job declares that the name of the queue it uses is `test_queue`, set in the `queue_options` method.

### `Chore::Job` & `perform` Signatures

The perform method signature can have explicit argument names, but in practice this makes changing the signature more
difficult later on. Once a `Chore::Job` is in production and being used at a constant rate, it becomes problematic to
begin mixing versions of the job with non-matching signatures.

While this is able to be overcome with a number of techniques, such as versioning jobs/queues, it increases the
complexity of making changes.

The simplest way to structure job signatures is to treat the arguments as a hash. This enables maintaining forwards and
backwards compatibility between signature changes with the same job class.

However, Chore is ultimately agnostic in this regard and will allow explicit arguments in signatures as easily as using
a simple hash; the choice is left to the developer.

### `Chore::Job` & Publishing Jobs

Now that there's a test job, publishing an instance of the job is as simple as:

```ruby
TestJob.perform_async({"message"=>"YES, DO THAT THING."})
```

It's advisable to specify the Publisher Chore uses to send messages globally, so that it can easily be modified based on
the environment. To do this, add a configuration block to an initializer:

```ruby
Chore.configure do |c|
  c.publisher = Some::Other::Publisher
end
```

It is worth noting that any option that can be set via config file or command-line args can also be set in a configure
block.

If a global publisher is set, it can be overridden on a per-job basis by specifying the publisher in `queue_options`.

## Retry Backoff Strategy

Chore has basic support for delaying retries of a failed job using a step function. Currently the only queue that
supports this functionality is SQS; all others will simply ignore the delay setting.

### Setup

The `:backoff` option for a queue expects a lambda that takes a single `UnitOfWork` argument. The return should be a
number of seconds to delay the next attempt.

```ruby
queue_options :name => 'nameOfQueue',
  :backoff => lambda { |work| work.current_attempt ** 2 } # Exponential backoff
```

### Using The Backoff

If there is a `:backoff` option supplied, any failures will delay the next attempt by the result of that lambda.

### Notes On SQS & Delays

Read more details about SQS and Delays [here](docs/Delayed%20Jobs.md)

## Hooks

A number of hooks, both global and per-job, exist in Chore for flexibility and convencience. Hooks should be named
`hook_name_identifier` where `identifier` is a descriptive string of chosen by the developer.

### Global Hooks

* `before_start`
* `before_first_fork`
* `before_fork`
* `after_fork`
* `around_fork`
* `within_fork`
  * behaves similarly to `around_fork`, except that it is called _after_ the worker process has been forked.
    In contrast, `around_fork` is called by the parent process ( chore-master`)
* `before_shutdown`

## Filesystem Consumer/Publisher Hooks

* `on_fetch(job_file, job_json)`

#### SQS Consumer Hooks

* `on_fetch(handle, body)`

### Per Job

* `before_publish`
* `after_publish`
* `before_perform(message)`
* `after_perform(message)`
* `on_rejected(message)`
* `on_failure(message, error)`
* `on_permanent_failure(queue_name, message, error)`
* `around_publish`
* `around_perform`

All per-job hooks can also be global hooks.

Hooks can be added to a job class like so:

```ruby
class TestJob
  include Chore::Job
  queue_options :name => 'test_queue'

  def perform(args={})
    # Do something cool
  end

  def before_perform_log(message)
    Chore.logger.debug "About to do something cool with: #{message.inspect}"
  end
end
```

Global hooks can also be registered like so:

```ruby
Chore.add_hook :after_publish do
  # Add handler code here
end
```

## Signals

Signal handling can get complicated when there are multiple threads, process forks, and both signal handlers and
application code making use of mutexes.

To simplify the complexities around this, Chore introduces some additional behaviors on top of Ruby's default
`Signal.trap` implementation.  This functionality is primarily inspired by `sidekiq`'s signal handling @
https://github.com/mperham/sidekiq/blob/master/lib/sidekiq/cli.rb.

In particular Chore handles signals in a separate thread, and does so sequentially instead of being interrupt-driven.
See `Chore::Signal` for more details on the differences between Ruby's `Signal.trap` and Chore's `Chore::Signal.trap`.

Chore will respond to the following signals:

* `INT` , `TERM`, `QUIT` - Chore will begin shutting down, taking steps to safely terminate workers and not interrupt
  jobs in progress unless it believes they may be hung
* `USR1` - Re-opens logfiles, useful for handling log rotations

## Timeouts

When using the forked worker strategy for processing jobs, inevitably there are cases in which child processes become
stuck.  This could result from deadlocks, hung network calls, tight loops, etc.  When these jobs hang, they consume
resources and can affect throughput.

To mitigate this, Chore has built-in monitoring of forked child processes. When a fork is created to process a batch of
work, that fork is assigned an expiration time -- if it doesn't complete by that time, the process is sent a `KILL`
signal.

Fork expiration times are determined from one of two places:

1. The timeout associated with the queue.  For SQS queues, this is the visibility timeout.
1. The default queue timeout configured for Chore. For filesystem queues, this is the value used.

For example, if a worker is processing a batch of 5 jobs and each job's queue has a timeout of 60s, then the expiration
time will be 5 minutes for the worker.

To change the default queue timeout (when one can't be inferred), do the following:

```ruby
Chore.configure do |c|
  c.default_queue_timeout = 3600
end
```

A reasonable timeout would be based on the maximum amount of time any job in the system is expected to run.  Keep in
mind that the process running the job may get killed if the job is running for too long.

## Plugins

Chore has several plugin gems available, which extend its core functionality

[New Relic](https://github.com/Tapjoy/chore-new_relic) - Integrating Chore with New Relic

[Airbrake](https://github.com/Tapjoy/chore-airbrake) - Integrating Chore with Airbrake

## Managing Chore Processes

### Sample Upstart

There are lots of ways to create upstart scripts, so it's difficult to give a prescriptive example of the "right" way to
do it. However, here are some ideas from how we run it in production at Tapjoy:

For security reasons, a specific user should be specified that the process runs as. Switch to this user at the beginning
of the exec line

```bash
su - $USER --command '...'
```

For the command to run Chore itself keeping all of the necessary environment variables in an env file that Upstart can
source on it's exec line, to prevent having to mix changing environment variables with having to change the upstart
script itself

```bash
source $PATHTOENVVARS ;
```

After that, ensure Chore is running under the right ruby version. Additionally, `STDOUT` and `STDERR` can be redirected
to `logger` with an app name. This makes it easy to find information in syslog later on. Putting that all together looks
like:

```bash
rvm use $RUBYVERSION do  bundle exec chore -c Chorefile  2>&1 | logger -t $APPNAME
```

There are many other ways to manage the Upstart file, but these are a few of the ways we prefer to do it. Putting it all
together, it looks something like:

```bash
exec su - special_user --command '\
  source /the/path/to/env ;\
  rvm use 2.4.1 do bundle exec chore -c Chorefile 2>&1 | logger chore-app ;'
```

### Locating Processes

As Chore does not keep a PID file, and has both a master and a potential number of workers, it may be difficult to
isolate the exact PID for the master process.

To find Chore master processes via `ps`, run the following:

```bash
ps aux | grep bin/chore
```

or

```bash
pgrep -f bin/chore
```

To find a list of only Chore worker processes:

```bash
ps aux | grep chore-worker
```

or

```bash
pgrep -f chore-worker
```

## Copyright

Copyright (c) 2013 - 2023 Tapjoy. See [LICENSE.txt](LICENSE.txt) for further details.
