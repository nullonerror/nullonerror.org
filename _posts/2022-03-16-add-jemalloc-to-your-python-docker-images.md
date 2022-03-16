---
layout: post
title: >
  Add jemalloc to your Python Docker images
---


Based on this [blog post](https://zapier.com/engineering/celery-python-jemalloc/), which claims to reduce in 40% the memory usage when using jemalloc, I am bringing an alternative for those who use Docker in production.

In your Dockerfile, before your `CMD`, add this `RUN` command and the `LD_PRELOAD`.

The LD_PRELOAD is important because it allows replacing all calls of _malloc_ and _free_ by [jemalloc](http://jemalloc.net/) ones.

> jemalloc is a general purpose malloc(3) implementation that emphasizes fragmentation avoidance and scalable concurrency support. jemalloc first came into use as the FreeBSD libc allocator in 2005, and since then it has found its way into numerous applications that rely on its predictable behavior.

```dockerfile
FROM python:3.10-slim AS base

...

FROM base

RUN apt-get update \
    && apt-get install --yes --no-install-recommends libjemalloc2 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

ENV LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libjemalloc.so.2

ENTRYPOINT ...

CMD ...
```

[Full example](https://github.com/skhaz/docker-jemalloc-python)