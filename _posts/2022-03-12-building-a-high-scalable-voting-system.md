---
layout: post
title: >
  Building a high scalable voting system
---

Recently on my Twitter _bubble_ much has been said about the voting system of Big Brother Brazil.

> The BBB voting system deals with peaks of millions of requests per minute. How can they handle this traffic?

This kind of challenge always attracted me, quickly I started to think in a highly scalable version.

First of all, all components in the architecture must scale horizontally. We can have N instances of any service.

Then, the frontend of the backend should accept the connection, grab the unique identifier of the vote and put it on a queue, and returns an HTTP response as soon as possible.

I call "frontend of the backend" because it is just an interface to the world.

On the other side, one or more workers pull the data from the queue and increment the unique identifier used as a key on Redis.

More details on the [repository](https://github.com/skhaz/high-scalable-voting-system).

![architeture diagram](/public/2022-03-12-building-a-high-scalable-voting-system/diagram.png){: .center }
