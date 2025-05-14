---
layout: post
title: >
  I’ve built an IoT device to let my family know when I’m in a meeting
---

# Introducing the IoT device Tabajara: “I’m in a meeting.”

Do you work from home, and do people in your household always show up at the worst possible moments?

Let me introduce the “I’m in Meeting” IoT device: it lights up at your office door whenever you turn on your webcam.

It consists of an ESP32 with `mDNS` connected to Wi-Fi, using the Arduino framework for simplicity. The ESP32 exposes an HTTP server that handles a PATCH request on the /camera endpoint. This endpoint receives a JSON payload with a status of "on" or "off", and turns the LED panel red or blue accordingly.

For those who don’t know, mDNS (or Bonjour on Apple platforms) is a way to assign an IP address to a .local hostname for the device, so I don’t need to figure out its IP manually—just use the local domain.

Super convenient, right?

On the other side, I have a Python daemon that periodically queries Apple’s API to check if any cameras are in use, and then sends a PATCH request with "on" or "off" to http://esp32.local/camera.

Very simple, but quite useful.

See in action here [https://youtu.be/c-cD_JLuCuQ](https://youtu.be/c-cD_JLuCuQ)

Source code [https://github.com/skhaz/onair](https://github.com/skhaz/onair)

See you!
