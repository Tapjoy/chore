# Chore: Job processing... for the future!

## About

Chore is a pluggable, multi-backend job processor. It was built from the ground up to be extremely flexible. We hope that you
will find integrating and using Chore to be as pleasant as we do.

The full docs for Chore can always be found at http://tapjoy.github.io/chore.

## Configuration

Chore can be integrated with any Ruby-based project by following these instructions:

Add the chore gem to your gemfile and run `bundle install` (at some point we'll have a proper gem release):

    gem 'chore', :git => 'git@github.com:Tapjoy/chore.git'

If you also plan on using SQS, you must also bring in dalli to use for memcached:

    gem 'dalli'

Create a `chore.config` file in a suitable place, e.g. `./config`. This file controls how the consumer end of chore will operate. 

    --require=./<FILE_TO_LOAD>
    --verbose
    --concurrency 10

Make sure that `--require` points to the main entry point for your app. If integrating with a Rails app, just point it to the directory of your application and it will handle loading the correct files on its own. See the help options for more details on the other settings.

If you're using SQS, you'll want to add AWS keys so that Chore can authenticate with AWS.

    --aws-access-key=<AWS KEY>
    --aws-secret-key=<AWS SECRET>

Other options include:

    --stats-port 9090 # port to run the stats HTTP server on
    --concurrency 16 # number of concurrent worker processes, if using forked worker strategy
    --worker-strategy Chore::ForkedWorkerStrategy # which worker strategy class to use
    --consumer Chore::Queues::SQS::Consumer # which consumer class to use
    --dedupe-servers # if using SQS and your memcache is running on something other than localhost
    --fetcher-strategy Chore::ThreadedConsumerStrategy # fetching strategy class, are you seeing a theme here?
    --batch-size 50 # how many messages are batched together before handing them to a worker
    --threads-per-queue 4 # number of threads per queue for fetching from queue

By default, Chore will run over all queues it detects among the required files. If you wish to change this behavior, you can use:

    --queues QUEUE1,QUEUE2... # a list of queues to process
    --except-queues QUEUE1,QUEUE2... # a list of queues _not_ to process

Note that you can use one or the other but not both. Chore will quit and make fun of you if both options are specified.

## Integration

Add an appropriate line to your `Procfile`:

    jobs: bundle exec chore -c config/chore.config

Don't forget to start memcached if you're using SQS:

    memcached &


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
  queue_options :name => 'test_queue', :publisher => Chore::Queues::SQS::Publisher

  def perform(*args)
    Chore.logger.debug "My first async job"
  end

end
```

This job uses the included `Chore::Queues::SQS::Publisher` to remove the message from the queue once the job is completed.
It also declares that the name of the queue it uses is `test_queue` seconds.

Now that you've got a test job, if you wanted to publish to that job it's as simple as:
```ruby
TestJob.perform_async("YES, DO THAT THING.")
```


If you wish to specify a global publisher for all of your job classes, you can add a configuration block to an initializer like so:

```ruby
Chore.configure do |c|
  c.publisher = Some::Other::Publisher
end
```

It is worth noting that any option that can be set via config file or command-line args can also be set in a configure block.

If a global publisher is set, it can be overridden on a per-job basis by specifying the publisher in `queue_options`.


## Hooks

A number of hooks, both global and per-job, exist in Chore for your convenience.

Global Hooks:

* before_first_fork
* before_fork
* after_fork

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

All per-job hooks can also be global hooks.

Hooks can be added to a job class as so:

```ruby
class TestJob 
  include Chore::Job
  queue_options :name => 'test_queue', :publisher => Chore::Queues::SQS::Publisher

  def perform(*args)
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

## Contributing to chore
 
* Check out the latest master to make sure the feature hasn't been implemented or the bug hasn't been fixed yet.
* Check out the issue tracker to make sure someone already hasn't requested it and/or contributed it.
* Fork the project.
* Start a feature/bugfix branch.
* Commit and push until you are happy with your contribution.
* Make sure to add tests for it. This is important so I don't break it in a future version unintentionally.
* Please try not to mess with the Rakefile, version, or history. If you want to have your own version, or is otherwise necessary, that is fine, but please isolate to its own commit so I can cherry-pick around it.

## Copyright

Copyright (c) 2013 Tapjoy. See LICENSE.txt for
further details.
