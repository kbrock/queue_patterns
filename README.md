# Purpose

We currently have a producer consumer paradigm.
This repo focuses on the orchestration of the work
it punts on the queue, database, and spawner.

Also, random numbers were not used because the goal was to make these as repeatable as possible.
You can compare the sqme input across different solutions.


This is from the context of our C&U processing.
We are using `put_unless_exists` to make sure we don't ask for the same work to be done multiple times


# Text Diagram

```
coordinator/producer:
  every 3 minutes:
    get all possible objects (~cheap)
    determine threshold for each object: (expensive)
      if alerts enabled, threshold is every 10 minutes
      if no alerting, threshold is every 50 minutes
    keep objects where last_perf_capture_on is over threshold
    submit objects => queue 

collector/consumer:
  while (get message from queue)
    fetch object from db
    fetch data from provider
    update last_perf_capture_on
```

# The Problem

The first pass through needs to submit work for every record.
The timer goes off before all records are submitted.
The second pass through generates a bunch of requests for records already submitted (the last_perf_capture_on is not yet set)


So... How do you not do the same work twice?
How can you reduce duplicates, without using `put_unless_exists` on the queue - it will no longer be available.
How do you determine how much work needs to be done?
Why are we even using a timer with arbitray values?
Can we put processing optimizations in the collector not the coordinator


Do note, that increasing the number of workers will fix this problem. But there is a generalized problem of needing to
request work that others are also requesting.

Our goal here is to reduce the number of duplicates generated.

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
?. collector just processing alerts or non-alert objects (sleep full 10min or 50min)
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
