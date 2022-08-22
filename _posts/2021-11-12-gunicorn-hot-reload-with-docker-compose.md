---
layout: post
title: >
  Gunicorn hot reload with Docker Compose
---

Let's suppose you want to use the same `Dockerfile` to run in production and in development mode, and want to use _Docker Compose_ to set up the development environment.

The trick here is to pass an argument to Docker during the build called `options`, and inside this argument is possible to pass `--reload` responsible to reload the code on each change.

```dockerfile
ARG options
ENV OPTIONS $options

CMD exec gunicorn $OPTIONS --bind :$PORT --workers 1 --threads 8 --timeout 0 main:app
```

And on `docker-compose.yaml` will be need two things:

- Pass `--reload` as a Docker argument to the container, using args.
- Mount the local directory inside the container, using the volumes.

```yaml
version: "3"
services:
  app:
    build:
      context: .
      args:
        options: --reload
    volumes:
      - ./:/app
```

Full example [github.com/skhaz/docker-compose-gunicorn-hot-reload](https://github.com/skhaz/docker-compose-gunicorn-hot-reload)
