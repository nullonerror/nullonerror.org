---
layout: post
title: >
  Docker multi-stage build with Poetry
---

### File structure

```
.
├── Dockerfile
├── Makefile
├── app
│   └── main.py
├── poetry.lock
└── pyproject.toml
```

### Virtualenv

First, select a base image:

```Dockerfile
FROM python:3.11-slim AS base
```

Add the _virtualenv's_ binary directory to the search path

```Dockerfile
ENV PATH /opt/venv/bin:$PATH
```

### Poetry

Now install poetry using pip inside the virtualenv

```Dockerfile
WORKDIR /opt
RUN python -m venv venv
RUN pip install poetry
COPY pyproject.toml poetry.lock ./
RUN poetry config virtualenvs.create false
RUN poetry install --no-interaction --no-root --only main
```

Please note the flags used; first, we tell poetry not to create any virtualenv. Secondly, during the installation, we disable the installation of the root package (our project) and only the main dependencies, excluding the development one.

With these three flags, it is possible to install the dependencies using Poetry inside the docker environment.

### Multi-stage build

We only want the dependencies and our app, a clean image. For this, we copy from the builder layer the virtualenv directory and add the app directory. With this, we only rebuild the builder layer when there is any dependency change.

```Dockerfile
FROM base
WORKDIR /opt
COPY --from=builder /opt/venv venv
COPY app app
CMD exec gunicorn --bind :$PORT app.main:app
```

### Bonus

This `Makefile` has a fall-back for new installations of docker-compose.

In some systems, it is Docker's plugin, and in others, it is a separate program.

This Makefile solves this issue.

```Makefile
.PHONY: help run

.SILENT:

SHELL := bash -eou pipefail

ifeq ($(shell command -v docker-compose;),)
  COMPOSE := docker compose
else
  COMPOSE := docker-compose
endif

help:
  awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

run: ## Run the project using docker-compose
  $(COMPOSE) up --build
```

### Source Code

[github.com/skhaz/poetry-on-docker](https://github.com/skhaz/poetry-on-docker)
