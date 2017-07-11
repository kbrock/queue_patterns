# Purpose

We currently have a producer consumer paradigm.
In this process, we sometimes generate work requests that are duplicates.

This is from the context of our C&U processing.
But `put_unless_exists` is common place and removing duplicate requests is pretty common.


This could setup a database, use ActiveMQ, and use Redis, but this implementation attempted
to simplify everything.
