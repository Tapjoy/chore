# Chore: Job processing... for the future!

## About

Chore is a pluggable, multi-backend job processor. It was built from the ground up to be extremely flexible. We hope that you
will find integrating and using Chore to be as pleasant as we do.

The full docs for Chore can always be found at http://tapjoy.github.io/chore.

## Configuration

Chore can be integrated with any Ruby-based project by following these instructions:

    gem 'chore-core', '~> 1.6.0'

If you also plan on using SQS, you must also bring in dalli to use for memcached:

    gem 'dalli'

Create a `Chorefile` file in the root of your project directory. While you can configure Chore itself from this file, it's primarly used to direct the Chore binary toward the root of your application, so that it can locate all of the depdendencies and required code.

    --require=./<FILE_TO_LOAD>

Make sure that `--require` points to the main entry point for your app. If integrating with a Rails app, just point it to the directory of your application and it will handle loading the correct files on its own.

Other options include:

    --concurrency 16 # number of concurrent worker processes, if using forked worker strategy
    --worker-strategy Chore::Strategy::ForkedWorkerStrategy # which worker strategy class to use
    --consumer Chore::Queues::SQS::Consumer # which consumer class to use Options are SQS::Consumer and Filesystem::Consumer. Filesystem is recommended for local and testing purposes only.
    --consumer-strategy Chore::Queues::Strategies::Consumer::ThreadedConsumerStrategy # which consuming strategy to use. Options are SingleConsumerStrategy and ThreadedConsumerStrategy. Threaded is recommended for better tuning your consuming profile
    --consumer-sleep-interval 1.0 # The amount of time in seconds to sleep when a consumer doesn't receive any messages. Sub-second values are accepted. The default varies by consumer implementation. This is a weak form of backoff for when there is no work to do.
    --threads-per-queue 4 # number of threads per queue for consuming from a given queue.
    --dedupe-servers # if using SQS or similiar queue with at-least once delivery and your memcache is running on something other than localhost
    --batch-size 50 # how many messages are batched together before handing them to a worker
    --queue_prefix prefixy # A prefix to prepend to queue names, mainly for development and qa testing purposes
    --max-attempts 100 # The maximum number of times a job can be attempted
    --dupe-on-cache-failure # Determines the deduping behavior when a cache connection error occurs. When set to `false`, the message is assumed not to be a duplicate. Defaults to `false`.
    --queue-polling-size 10 # If your particular queueing system supports responding with messages in batches of a certain size, you can control that with this flag. SQS has a built in upper-limit of 10, but other systems will vary.

If you're using SQS, you'll want to add AWS keys so that Chore can authenticate with AWS.

    --aws-access-key=<AWS KEY>
    --aws-secret-key=<AWS SECRET>

By default, Chore will run over all queues it detects among the required files. If you wish to change this behavior, you can use:

    --queues QUEUE1,QUEUE2... # a list of queues to process
    --except-queues QUEUE1,QUEUE2... # a list of queues _not_ to process

Note that you can use one or the other but not both. Chore will quit and make fun of you if both options are specified.

### Tips for configuring Chore

When it comes to configuring Chore, you have 2 main use cases - as a producer of messages, or as a consumer of messages (the consumer is also able to produce messages if need be, but is running as it's own isolated instance of your application).

For producers, you must do all of your Chore configuration in an intializer.

For consumers, you need to either Chorefile or Chorefile + an initializer.

Because you are likely to use the same app as the basis for both producing and consuming messages, you'll already have a considerable amount of configuration in your Producer - it makes sense to use Chorefile to simply provide the `require` option, and stick to the initializer for the rest of the configuration to keep things DRY.

However, like many aspects of Chore, it is ultimately up to the developer to decide which use case fits their needs best. Chore is happy to let you configure it in almost any way you want.

An example of how to configure chore via an initializer:

```ruby
Chore.configure do |c|
  c.concurrency = 16
  c.worker_strategy = Chore::Strategy::ForkedWorkerStrategy
  c.max_attempts = 100
  ...
  c.batch_size = 50
end
```

## Integration

Add an appropriate line to your `Procfile`:

    jobs: bundle exec chore -c config/chore.config

If your queues do not exist, you must create them before you run the application:

```ruby
require 'aws-sdk'
sqs = AWS::SQS.new
sqs.queues.create("test_queue")
```

Finally, start foreman as usual

    bundle exec foreman start

## Chore::Job

A Chore::Job is any class that includes `Chore::Job` and implements `perform(*args)` Here is an example job class:

```ruby
class TestJob
  include Chore::Job
  queue_options :name => 'test_queue'

  def perform(args={})
    Chore.logger.debug "My first async job"
  end

end
```

This job declares that the name of the queue it uses is `test_queue`, set in the queue_options method.

### Chore::Job and perform signatures

The perform method signature can have explicit argument names, but in practice this makes changing the signature more difficult later on. Once a Job is in production and is being used at a constant rate, it becomes problematic to begin mixing versions of jobs which have non-matching signatures.

While this is able to be overcome with a number of techniques, such as versioning your jobs/queues, it increases the complexity of making changes.

The simplest way to structure job signatures is to treat the arguments as a hash. This will allow you to maintain forwards and backwards compatibility between signature changes with the same job class.

However, Chore is ultimately agnostic to your particular needs in this regard, and will let you use explicit arguments in your signatures as easily as you can use a simple hash - the choice is left to you, the developer.

### Chore::Job and publishing Jobs

Now that you've got a test job, if you wanted to publish to that job it's as simple as:
```ruby
TestJob.perform_async({"message"=>"YES, DO THAT THING."})
```

It's advisable to specify the Publisher chore uses to send messages globally, so that you can change it easily for local and test environments. To do this, you can add a configuration block to an initializer like so:

```ruby
Chore.configure do |c|
  c.publisher = Some::Other::Publisher
end
```

It is worth noting that any option that can be set via config file or command-line args can also be set in a configure block.

If a global publisher is set, it can be overridden on a per-job basis by specifying the publisher in `queue_options`.

## Retry Backoff Strategy

Chore has basic support for delaying retries  of a failed job using a step function. Currently the only queue that
supports this functionality is SQS, all others will simply ignore the delay setting.

### Setup

The `:backoff` option for a queue expects a lambda that takes a single `UnitOfWork` argument. The return should be a
number of seconds to delay the next attempt.

```ruby
queue_options :name => 'nameOfQueue',
  :backoff => lambda { |work| work.current_attempt ** 2 } # Exponential backoff
```

### Using the Backoff

If there is a `:backoff` option supplied, any failures will delay the next attempt by the result of that lambda.

### Notes on SQS and Delays

Read more details about SQS and Delays [here](docs/Delayed Jobs.md)

## Hooks

A number of hooks, both global and per-job, exist in Chore for your convenience.

Global Hooks:

* before_first_fork
* before_fork
* after_fork
* around_fork
* within_fork

("within_fork" behaves similarly to around_fork, except that it is called after the worker process has been forked. In contrast, around_fork is called by the parent process.)

Filesystem Consumer/Publisher

* on_fetch(job_file, job_json)

SQS Consumer

* on_fetch(handle, body)

Per Job:

* before_publish
* after_publish
* before_perform(message)
* after_perform(message)
* on_rejected(message)
* on_failure(message, error)
* on_permanent_failure(queue_name, message, error)

All per-job hooks can also be global hooks.

Hooks can be added to a job class as so:

```ruby
class TestJob
  include Chore::Job
  queue_options :name => 'test_queue'

  def perform(args={})
    Chore.logger.debug "My first sync job"
  end
end
```
Global hooks can also be registered like so:

```ruby
Chore.add_hook :after_publish do
  # your special handler here
end
```

## Signals

Signal handling can get complicated when you have multiple threads, process
forks, and both signal handlers and application code making use of mutexes.

To simplify the complexities around this, Chore introduces some additional
behaviors on top of Ruby's default Signal.trap implementation.  This
functionality is primarily inspired by sidekiq's signal handling @
https://github.com/mperham/sidekiq/blob/master/lib/sidekiq/cli.rb.

In particular, Chore handles signals in a separate thread and does so
sequentially instead of interrupt-driven.  See Chore::Signal for more details
on the differences between Ruby's `Signal.trap` and Chore's `Chore::Signal.trap`.

Chore will respond to the following Signals:

* INT , TERM, QUIT - Chore will begin shutting down, taking steps to safely terminate workers and not interrupt jobs in progress unless it believes they may be hung
* USR1 - Re-opens logfiles, useful for handling log rotations

## Timeouts

When using the forked worker strategy for processing jobs, inevitably there are
cases in which child processes become stuck.  This could result from deadlocks,
hung network calls, tight loops, etc.  When these jobs hang, they consume
resources and can affect throughput.

To mitigate this, Chore has built-in monitoring of forked child processes.
When a fork is created to process a batch of work, that fork is assigned an
expiration time -- if it doesn't complete by that time, the process is sent
a KILL signal.

Fork expiration times are determined from one of two places:
1. The timeout associated with the queue.  For SQS, this is the visibility
   timeout.
2. The default queue timeout configured for Chore.  For Filesystem queues,
   this is the value used.

For example, if a worker is processing a batch of 5 jobs and each job's queue
has a timeout of 60s, then the expiration time will be 5 minutes for the worker.

To change the default queue timeout (when one can't be inferred), you can do
the following:

```ruby
Chore.configure do |c|
  c.default_queue_timeout = 3600
end
```

A reasonable timeout would be based on the maximum amount of time you expect any
job in your system to run.  Keep in mind that the process running the job may
get killed if the job is running for too long.

## Plugins

Chore has several plugin gems available, which extend it's core functionality

[New Relic](https://github.com/Tapjoy/chore-new_relic) - Integrating Chore with New Relic

[Airbrake](https://github.com/Tapjoy/chore-airbrake) - Integrating Chore with Airbrake

## Copyright

Copyright (c) 2013 - 2014 Tapjoy. See LICENSE.txt for
further details.
