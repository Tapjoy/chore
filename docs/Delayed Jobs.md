# Delayed Jobs, Backoffs and SQS

We handle delays in SQS by changing the `VisibilityTimeout` of the in-flight message. This operation is *additive*,
meaning a queue has a default `VisibilityTimeout` of 5 minutes, the message is processed then fails 1 minute after the
message is sent, and the step function returns 60 seconds, the new `VisibilityTimeout` of the message will be at 5
(rather than 4) minutes.

This means small steps will not behave as one might expect, unless `VisibilityTimeout` is set to 0. However, a
 `VisibilityTimeout` of 0 would cause the message to never remain in flight and would likely break the entire world
when every worker tries to work a copy of the same job. The default `VisibilityTimeout` should be set as low as possible
given the expected execution duration of the job code, but not so low that the message might be still be waiting to be
scheduled on a Chore worker when the timeout hits 0 (causing the job to process twice!).

Something else to consider is the `RetentionPeriod` of a queue. If the `RetentionPeriod` is 1 hour, and an initial
message continues to retry through that hour, it will suddenly disappear! That is to say: the `RetentionPeriod` starts
counting down from the moment the message is *first* sent, and does not reset.

Finally, if the queue has a `DeliveryDelay` configured any delay applied by the backoff function will be *in addition*
to the `DeliveryDelay` when the message is removed from its "in flight" status.

All of this should be taken into consideration when using this feature. In general, any queue requiring this will likely
need to run as its own Facet and not share workers with other queues.

### Further Reading

 * [SQS Message Lifecycle](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-basic-architecture.html)
 * [SQS VisibilityTimeout](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-visibility-timeout.html)
 * [SQS Delay Queues](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-delay-queues.html)
