# Purpose

We currently have a producer consumer paradigm.
In this process, we sometimes generate work requests that are duplicates.

This is from the context of our C&U processing.
But `put_unless_exists` is common place and removing duplicate requests is pretty common.


This could setup a database, use ActiveMQ, and use Redis, but this implementation attempted
to simplify everything.

# The Problem

The first pass through needs to submit work for every record.
The timer goes off before all records are submitted.

When trying to detect which records need work to be done, a bunch of false positivies show up.
These are then inserted again.


So... How do you not do the same work twice?

Sure, you could increase the number of workers, or you could change the way you determine what work needs to be done.

Our goal here is to accept that duplicates may be requested, and instead reduce the amount of work done

dedup examples:

1. calculate work - do work (inline single)
2. calculate work - spawn work (wait till they are done)
3. put unless exists
4. filter on client (time where requests will be blocked)
5. filter on server (same algorithm as 4)
6. fixed collectors
---
?. queue for collectors, queue for writers
?. queue params separate from actual (queue need refresh, vms to refresh in a separate set)
?. "shopping list" a queue consumers (for outside interface), more db like queue for work.

problem set:
currently handle occasonal duplicate records (so capture / delay / broadcast not viable)
what about many many duplicates
what about running 2 producers ("oops")
what about work that takes a long time
what about sending deletes, and retries?
