---
layout: post
title: >
  Mastering Atomic Complex Operations in Redis: Unlocking High-Performance Data Handling With Lua
---

I have been using Redis for its most basic operations such as caching with expiration and counters, as well as slightly more complex operations like [zsets](https://redis.io/docs/data-types/sorted-sets/), [zrangebyscore](https://redis.io/commands/zrangebyscore/), and [scan](https://redis.io/commands/scan/), or as a [queue](https://redis.io/commands/rpoplpush/) for probably more than 6 years on a daily basis.

I won't discuss Postgres today, as we can achieve similar results. Today, I will introduce something different: the possibility of scripting Redis with [Lua](https://en.wikipedia.org/wiki/Lua_%28programming_language%29).

Months ago, I found myself facing the following problem: I needed to retrieve a JSON string from Redis using a specific key, merge it with the local JSON, and then submit it back to Redis as a string.

This would have been a trivial task if not for the following scenario: On the "other" side, there was a process that consumed the same JSON and then, in an atomic pipeline operation, deleted it.

Given this context, I could not perform the JSON merge on the client side, as it would not be atomic. This is where my native language, Lua (incidentally, I have a dog with the same name, and another dog named Python, yes, I'm a nerd, how did you guess?), comes into play.

With Lua, operations are atomic and accelerated with JIT, making it possible to do a myriad of things, one very classic example being a rate limiter by IP address.

Let's see how my solution turned out:

```typescript
const script = `
    local key = KEYS[1]
    local input = ARGV[1]
    local existing = redis.call('GET', key)

    if existing then
      local existingJson = cjson.decode(existing)
      local inputJson = cjson.decode(input)
      for _, v in ipairs(inputJson) do
        table.insert(existingJson, v)
      end
      input = cjson.encode(existingJson)
    end

    redis.call('SET', key, input)
    return input
  `;

const key = "...";

await redis.eval(script, {
  keys: [key],
  arguments: [JSON.stringify(schema.parse(data))],
});
```

And on the other side, the consumer can retrieve the JSON and delete it, atomically within a pipeline:

```typescript
const pipeline = redis.multi();
pipeline.get("...");
pipeline.del("...");
const [jsonStr] = pipeline.exec();
```

In this way, all operations are atomic.

![Elmo reacting to the atomicity of combining Lua with Redis](/public/2024-03-06-mastering-atomic-complex-operations-in-redis-unlocking-high-performance-data-handling-with-lua/elmo.jpg){: .center }
