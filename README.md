# Overview

The goal of these expreiments is to find a more efficient coordination pattern with less communication, resulting in less contention, fewer race conditions, and less duplicate work.

The secondary goals
- make this faster
- detecting when the system is overloaded
- redistribution of work when the number of workers changes.
- removing our `put_unless_exists`
- move upfront worker configuration to discovery

To get more consistent resulst:
- The duration of work for all workers is constant (we could vary with an algorithm)
- The queue, database, and spawner are in memory and take no time.

# Text Diagram

The current process is relatively straight forward.

```
coordinator/producer:
  every 3 minutes:
    get all objects that are relevant (~cheap)
    determine threshold for each object (expensive)
    determine objects that need to be captured
    submit objects => queue (if they are not already on the queue)

collector/consumer:
  while (get message from queue)
    fetch object from db
    fetch data from provider
    update last_perf_capture_on

def determine_threshold(object)
  if alerts are enabled, threshold is every 10 minutes
  if no alerting, threshold is every 50 minutes
```

# Problems that shaped this experiment

## Coordinator determines work

We currently segregate our work and put a work message per item.
Now that some providers need to fetch data in a different way, it is not possible

#### Questions

Can we put work onto the queue that gives workers flexibility?
Can we find a way to fetch work off the queue that more work centric?

#### Goal

Put work onto queue in a way that allows batching and flexibility

## Duplicate work

The first pass through needs to submit work for every record.
The timer goes off before all records are submitted.
The second pass through generates a bunch of requests for records already submitted (the last_perf_capture_on is not yet set)

#### Questions

So... How do you not do the same work twice?
How can you reduce duplicates, without using `put_unless_exists` on the queue - it will no longer be available.
How do you determine how much work needs to be done?
Why are we even using a timer with arbitray values?
Can we put processing optimizations in the collector not the coordinator

#### Goal

Reduce the number of duplicates generated.

## Unknown workload

We currently do not know when we need to add more controllers nor how frequently we can handle collecting metrics.

#### Questions

How can we know when we have too many or too few workers?
Can we auto adjust this?

#### Goal

Provide feedback regards to how processing is working

## Determining alerts

There is a lot of work to determine if an object needs to be collected. It takes many database queries and a lot of filtering. Sometimes, queries are not properly setup and it can take minutes and transfer megabytes when it feels like we should just skip this process and collect all metrics.

#### Questions

How can we reduce the number of records fetched from the database?
How can we not work so hard just to find out that the records have been 
How can we avoid bringing back records that need to be processed (while they are processed) so thinking that they still need to be processed? (overlaps duplicate story above)

#### Goal

Reduce queries in the coordinator

## Overload the queue

We put hundreds of thousands of records onto the queue and swamp it.
In the end, the collector still needs to fetch these records anyway

#### Question

Can we get away with 10 messages instead of 100,000 messages for 10,000 VMs?
Is there a different pattern that doesn't require a queue item per vm?
Can we not fetch records in the coordinator?
Can we pass queries/filters instead of record ids?

#### Goal

Reduce queue messages
Put filters onto queue

# current examples

There are a number of approaches to reducing the duplicates.
Starting with example 6, the definition of a producer and consumer has changed:

1. calculate work - do work (inline single)
2. calculate work - spawn work (wait till they are done)
3. put unless exists
4. filter on client (time where requests will be blocked)
5. filter on server (same algorithm as 4)
6. fixed collectors
7. fixed collectors with supervisor that sets filter
8. fixed collector with supervisor that coordinates filters (http / events)
---
?. queue for collectors, queue for writers
?. separate collectors for processing alerts or non-alert objects (sleep full 10min or 50min)
?. queue params separate from actual (queue need refresh, vms to refresh in a separate set)
?. "shopping list" a queue consumers (for outside interface), more db like queue for work.

# "Fixed collectors" Diagram

```
Supervisor
  knows each collector's filter
  publishes filters as configuration map or HTTP
  receives events for new/deleted collectors and adjusts filters

Collector 1:
  filter = "objects.id mod 2 == 0"
  loop:
    fetch filter changes (or use events)
    fetch objects using filter
      hit provider
      save metrics
      provide_scale_information
      sleep(nice)
Collector 2:
  filter = "objects.id mod 2 == 1"
```

# Potential Goals

- allow workload to be consistent across
- ? separate collector and persister
- handle collectors adding, restarting, removing
- handle collaborator restarting


