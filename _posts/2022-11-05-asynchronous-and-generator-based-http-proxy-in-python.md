---
layout: post
title: >
  Asynchronous and generator-based HTTP proxy in Python
---

I was excited to use [Starlette](https://www.starlette.io/) ASGI framework, which is ideal for building async web services in Python and an _HTTP proxy_ is a good exercise to practice.

My proxy should do two things: proxy the request and count how many calls its have.

* For doing the HTTP request I choose [httpx](https://www.python-httpx.org/), which is an asynchronous HTTP client.
* For counting how many requests the proxy had, I choose Redis, Redis has the `incr` _operation_ which is perfect.

> My proxy has something special, it makes use of generators, because of this, it can handle any size of payload with a minimal memory footprint!

```python
@app.route("/{path}", methods=["GET", "POST", "PATCH", "PUT", "DELETE", "OPTIONS"])
async def proxy(request: Request) -> Response:
    response, _ = await asyncio.gather(
        http.send(
            http.build_request(
                method=request.method,  # repass the method
                headers=dict(request.headers.raw),  # repass the headers
                url=request.url.path,  # repass the path
            ),
            stream=True,  # Note this, this will enable the request to be processed
            # into chunks, allowing us to use generators in the next step
        ),
        redis.incr(COUNTER_KEY),  # At the same time, increment the key on Redis
    )

    return StreamingResponse(
        response.aiter_raw(),  # returns a generator which will be used by StreamingResponse
        headers=response.headers,  # repass the headers
        status_code=response.status_code,  # repass the status code
        background=BackgroundTask(response.aclose),  # close at the end of the transfer
    )
```

* `asyncio.gather` [allows us to run tasks concurrently](https://docs.python.org/3/library/asyncio-task.html#id7)
* `aiter_raw` [returns a generator iterator](https://github.com/encode/httpx/blob/8152c4facd0f71e0f376287e41a0810a60fec9c6/httpx/_models.py#L963-L1002)
* `StreamingResponse` [takes an async generator or a normal generator/iterator and streams the response body](https://www.starlette.io/responses/#streamingresponse)

And finally, the proxy has an endpoint to get the status

```python
@app.route("/status", methods=["GET"])
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

Full source-code [github.com/skhaz/async-generator-based-http-proxy](https://github.com/skhaz/async-generator-based-http-proxy)
