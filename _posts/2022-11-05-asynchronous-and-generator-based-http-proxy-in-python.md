---
layout: post
title: >
  Asynchronous and generator-based HTTP proxy in Python
---

### Intro

I was excited to use [Starlette](https://www.starlette.io/) ASGI framework, which is ideal for building async web services in Python and an _HTTP proxy_ is a good exercise to practice.

My proxy should do two things: proxy the request and count how many calls its have.

* For doing the HTTP request I choose [httpx](https://www.python-httpx.org/), which is an asynchronous HTTP client.
* For counting how many requests the proxy had, I choose Redis, Redis has the `incr` _operation_ which is perfect.

### Features

* Uses multiple asynchronous functions in parallel where is possible
* Small memory footprint, handles well small and big payloads using generators
* Fast, totally asynchronous
* Headers sent are preserved
* Status code is passed through

### Implementation

```python
@app.route("/{path}", methods=ALLOWED_METHODS)
async def proxy(request: Request) -> Response:
    response, _ = await asyncio.gather(
        http.send(
            http.build_request(
                content=request.stream(), # repasses the body
                method=request.method,  # repasses the method
                headers=dict(request.headers.raw),  # repasses the headers
                url=request.url.path,  # repasses the path
            ),
            stream=True,  # this will enable the request to be processed into chunks, allowing us to use generators
        ),
        redis.incr(COUNTER_KEY),  # at the same time, increment the key on Redis
    )

    return StreamingResponse(
        response.aiter_raw(),  # returns a generator which will be used by StreamingResponse
        headers=response.headers,  # repasses the headers
        status_code=response.status_code,  # repasses the status code
        background=BackgroundTask(response.aclose),  # close at the end of the transfer
    )
```

* `asyncio.gather` [allows us to run tasks concurrently](https://docs.python.org/3/library/asyncio-task.html#id7)
* `aiter_raw` [returns a generator iterator](https://github.com/encode/httpx/blob/1aea9539bbe93b26103e3a722ba0c421f7eb7f82/httpx/_models.py#L963-L989)
* `StreamingResponse` [takes an async generator or a normal generator/iterator and streams the response body](https://www.starlette.io/responses/#streamingresponse)

And finally, the proxy has an endpoint to get the status

```python
@app.route("/status")
async def status(_: Request) -> Response:
    counter, uptime = await asyncio.gather(
        redis.get(COUNTER_KEY),
        redis.get(UPTIME_KEY),
    )

    return JSONResponse(
        {
            "counter": as_int_or_zero(counter),
            "uptime": (arrow.utcnow() - arrow.get(str(uptime))).seconds,
        }
    )
```

### Source Code

[github.com/skhaz/async-generator-based-http-proxy](https://github.com/skhaz/async-generator-based-http-proxy)
