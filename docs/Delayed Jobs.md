# Delayed Jobs, Backoffs and SQS

We handle delays in SQS by changing the `VisiblityTimeout` of the in flight message. This operation is *additive*,
meaning if you have a Queue with a default `VisiblityTimeout` of 5 minutes, the message is processed then fails 1
minute after the message is sent, and the step function returns 60 seconds, the new `VisiblityTimeout` of the message
will be at 5 minutes.

This means small steps will not behave as you might expect, unless you have a `VisiblityTimeout` of 0. However, a
`VisiblityTimeout` of 0 would cause the message to never remain in flight and would likely break the entire world. You
want the default `VisiblityTimeout` to be as low as possible, but not low enough that it could be waiting in a Chore
batch when the timeout hits 0 (causing the job to process twice!).

Something else to consider is the `RetentionPeriod` of a queue. If the `RetentionPeriod` is 1 hour, and an initial
message continues to retry through that hour, it will suddenly disappear! That is to say: the `Retentionperiod` starts
counting down from the moment the message is *first* sent, and does not reset.

And finally, if the queue has a `DeliveryDelay` configured any delay applied by the backoff function will be *in
addition* to the `DeliveryDelay` when the message is removed from its "in flight" status.

All of this should be taken into consideration when using this feature. In general, any queue requiring this will likely
need to run as its own Facet and not share workers with other queues.

### Further Reading

 * [Expanded Documentation](docs/Delayed Jobs.md)
 * [SQS VisiblityTimeout](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-visibility-timeout.html)
 * [SQS Delay Queues](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-delay-queues.html)
 * [SQS Message Lifecycle](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-basic-architecture.html)
