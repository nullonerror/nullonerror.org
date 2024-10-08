---
layout: post
title: >
  My First Game with Carimbo, My Homemade Engine
---

[![MegaRick](https://img.youtube.com/vi/nVRzCstyspQ/0.jpg)](https://youtu.be/nVRzCstyspQ)

### TL;DR

After a while, I decided to resume work on my game engine.

I made a game for my son. I could have used an existing engine, but I chose to write everything from scratch because code is like pasta—it’s much better and more enjoyable when homemade.

This actually reminds me of when my father used to build my toys, from kites to wooden slides. Good memories. I have decided to do the same using what I know: programming.

You can watch it here or [play it here](https://play.carimbo.cloud/1.0.10/carimbolabs/megarick/1.0.7/720p) (runs in the browser thanks to WebAssembly).

The engine was written in C++17, and the games are in Lua. The engine exposes some primitives to the Lua VM, which in turn coordinates the entire game.

[Game source code](https://github.com/carimbolabs/megarick) and [engine source code](https://github.com/carimbolabs/carimbo).

### Going Deep

The entire game is scripted in Lua.

First, we create the engine itself.

```lua
local engine = EngineFactory.new()
    :set_title("Mega Rick")
    :set_width(1920)
    :set_height(1080)
    :set_fullscreen(false)
    :create()
```

Then we point to some resources for asset prefetching; they are loaded lazily to avoid impacting the game loop.

```lua
engine:prefetch({
  "blobs/bomb1.ogg",
  "blobs/bomb2.ogg",
  "blobs/bullet.png",
  "blobs/candle.png",
  "blobs/explosion.png",
  "blobs/octopus.png",
  "blobs/player.png",
  "blobs/princess.png",
  "blobs/ship.png"
})
```

We created the postal service, which is something I borrowed from languages like Erlang, where an entity can send messages to any other. As we’ll see below, the bullet sends a hit message when it collides with the octopus, and the octopus, upon receiving the hit, decrements its own health.

We also obtain the SoundManager to play sounds and spawn the main entities.

```lua
local postal = PostalService.new()
local soundmanager = engine:soundmanager()
local octopus = engine:spawn("octopus")
local player = engine:spawn("player")
local princess = engine:spawn("princess")
local candle1 = engine:spawn("candle")
local candle2 = engine:spawn("candle")
```

It’s not a triple-A title, but I’m very careful with resource management. A widely known technique is to create an object pool that you can reuse. In the code below, we limit it to a maximum of 3 bullets present on the screen.

The on_update method is a callback called each loop in the engine. In the case of the bullet, I check if it has approached the green octopus. If so, I send a message to it indicating that it received a hit.

```lua
for _ = 1, 3 do
  local bullet = engine:spawn("bullet")
  bullet:set_placement(-128, -128)
  bullet:on_update(function(self)
    if self.x > 1200 then
      postal:post(Mail.new(0, "bullet", "hit")) -- id 0 is the octopus
      bullet:unset_action()
      bullet:set_placement(-128, -128) -- move to ouside the screen
      table.insert(bullet_pool, bullet) -- back to the pool
    end
  end)
  table.insert(bullet_pool, bullet)
end
```

On the octopus’s side, when it receives a “hit” message, the entity triggers an explosion animation, switches to attack mode, and decreases its health by 1. If it reaches 0, it changes the animation to “dead”.

```lua
octopus:set_action("idle")
octopus:set_placement(1200, 620)
octopus:on_mail(function(self, message)
  if message == 'hit' then
    bomb()
    octopus:set_action("attack")
    life = life - 1
    if life <= 0 then
      self:set_action("dead")
    end
  end
end)
```
