---
layout: post
title: >
  Gotta go fast with Docker on macOS
---

### containerd

Using containerd for pulling images is way faster.

> Settings > Features in development > Use containerd for pulling and storing images

### VirtioFS

By default, the Docker desktop uses gRPC. Switching to VirtioFS brings improved I/O performance.

> Settings > General > VirtioFS

### Rosetta

Instead of using QEMU for x86 and amd64 containers, in the newest version of Docker is possible to use Rosetta 2.

> Settings > Features in development > Use Rosetta for x86/amd64 emulation on Apple Silicon

![sanic](/public/2023-01-19-gotta-go-fast-with-docker-on-macos/sanic.jpg){: .center }
