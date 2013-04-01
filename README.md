# chore

## Integration

Chore can be integrated with any Ruby-based project by following these instructions:

Add the chore gem to your gemfile and run `bundle install` (at some point we'll have a proper gem release):

    gem 'chore', :git => 'git://github.com/Tapjoy/chore.git'

If you also plan on using SQS, you must also bring in dalli to use for memcached:

    gem 'dalli'

Create a `chore.config` file in a suitable place, e.g. `./config`. This file controls how the consumer end of chore will operate. 

    --require=./<FILE_TO_LOAD>
    --aws-access-key=<AWS KEY>
    --aws-secret-key=<AWS SECRET>
    --verbose
    --concurrency 10

Make sure that `--require` points to the main entry point for your app. If integrating with a Rails app, just point it to the directory of your application and it will handle loading the correct files on its own. See the help options for more details on the other settings.

Now add a configuration block inside your apps configuration to configure the producer end. 

    Chore.configure do |c|
      c.aws_access_key = <AWS KEY>
      c.aws_secret_key = <AWS SECRET>
    end

Add an appropriate line to your `Procfile`:

    jobs: bundle exec chore -c config/chore.config

Create a new test job in your application:

    class TestJob 
      include Chore::Job
      queue_options :name => 'test_queue', :publisher => Chore::SQSPublisher

      def perform(*args)
        puts "My first sync job"
      end

    end

Don't forget to start memcached if you're using SQS:

    memcached &


If your queues do not exist, you must create them before you run the application:

     require 'aws-sdk'
     sqs = AWS::SQS.new
     sqs.queues.create("test_queue")

Finally, start foreman as usual

    bundle exec foreman start

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
