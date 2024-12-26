---
layout: post
title: >
  My First Game with Carimbo, My Homemade Engine, For my Son
---

[![MegaRick Game](/public/2024-10-08-my-first-game-with-carimbo/megarick.webp){: .center }](https://youtu.be/nVRzCstyspQ)
[https://youtu.be/nVRzCstyspQ](https://youtu.be/nVRzCstyspQ)

### TL;DR

After a while, I decided to resume work on [my game engine](https://github.com/carimbolabs/carimbo).

I made a game for my son. I could have used an existing engine, but I chose to write everything from scratch because code is like pasta—it’s much better and more enjoyable when homemade.

This actually reminds me of when my father used to build my toys, from kites to wooden slides. Good memories. I have decided to do the same using what I know: programming.

You can watch it here or [play it here](https://carimbo.run), (runs in the browser thanks to WebAssembly), use `A` and `D` for moving around and `space` to shoot.

The engine was written in C++17, and the games are in Lua. The engine exposes some primitives to the Lua VM, which in turn coordinates the entire game.

[Game source code](https://github.com/willtobyte/megarick) and [engine source code](https://github.com/willtobyte/carimbo).

Artwork by [Aline Cardoso @yuugenpixie](https://www.fiverr.com/yuugenpixie).

### Result

![Henrique Playing](/public/2024-10-08-my-first-game-with-carimbo/play.jpeg){: .center }

### Going Deep

The entire game is scripted in [Lua](https://www.lua.org).

First, we create the engine itself.

```lua
local engine = EngineFactory.new()
    :set_title("Mega Rick")
    :set_width(1920)
    :set_height(1080)
    :set_fullscreen(false)
    :create()
```

Then we point to some resources for asset prefetching; they are loaded lazily to avoid impacting the _game loop_.

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

We created the postal service, which is something I borrowed from languages like _Erlang_, where an entity can send messages to any other. As we’ll see below, the bullet sends a hit message when it collides with the octopus, and the octopus, upon receiving the hit, decrements its own health.

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

The `on_update` method is a callback called each loop in the engine. In the case of the bullet, I check if it has approached the green octopus. If so, I send a message to it indicating that it received a hit.

```lua
for _ = 1, 3 do
    local bullet = entitymanager:spawn("bullet")
    bullet.placement:set(-128, -128)
    bullet:on_collision("octopus", function(self)
      self.action:unset()
      self.placement:set(-128, -128)
      postalservice:post(Mail.new(octopus, "bullet", "hit"))
      table.insert(bullet_pool, self)
    end)
    table.insert(bullet_pool, bullet)
  end
```

On the octopus’s side, when it receives a “hit” message, the entity triggers an explosion animation, switches to attack mode, and decreases its health by 1. If it reaches 0, it changes the animation to “dead”.

```lua
octopus = entitymanager:spawn("octopus")
octopus.kv:set("life", 16)
octopus.placement:set(1200, 622)
octopus.action:set("idle")
octopus:on_mail(function(self, message)
  local behavior = behaviors[message]
  if behavior then
    behavior(self)
  end
end)
octopus.kv:subscribe("life", function(value)
  vitality:set(string.format("%02d-", math.max(value, 0)))

  if value <= 0 then
    octopus.action:set("dead")
    if not timer then
      timemanager:singleshot(3000, function()
        local function destroy(pool)
          for i = #pool, 1, -1 do
            entitymanager:destroy(pool[i])
            table.remove(pool, i)
            pool[i] = nil
          end
        end

        destroy(bullet_pool)
        destroy(explosion_pool)
        destroy(jet_pool)

        entitymanager:destroy(octopus)
        octopus = nil

        entitymanager:destroy(player)
        player = nil

        entitymanager:destroy(princess)
        princess = nil

        entitymanager:destroy(candle1)
        candle1 = nil

        entitymanager:destroy(candle2)
        candle2 = nil

        entitymanager:destroy(floor)
        floor = nil

        overlay:destroy(vitality)
        vitality = nil

        overlay:destroy(online)
        online = nil

        scenemanager:set("gameover")

        collectgarbage("collect")

        resourcemanager:flush()
      end)
      timer = true
    end
  end
end)
octopus:on_animationfinished(function(self)
  self.action:set("idle")
end)
```

And finally, the player’s `on_update`, where I apply the velocity if any movement keys are pressed, or set the animation to idle if none are pressed.

We also have the projectile firing, where the fire function is called, taking an instance of a bullet from the pool, placing it in a semi-random position, and applying velocity.

```lua
function loop()
  if not player then
    return
  end

  player.velocity.x = 0

  if statemanager:is_keydown(KeyEvent.left) then
    player.reflection:set(Reflection.horizontal)
    player.velocity.x = -360
  elseif statemanager:is_keydown(KeyEvent.right) then
    player.reflection:unset()
    player.velocity.x = 360
  end

  player.action:set(player.velocity.x ~= 0 and "run" or "idle")

  if statemanager:is_keydown(KeyEvent.space) then
    if not key_states[KeyEvent.space] then
      key_states[KeyEvent.space] = true

      -- player.velocity.y = -360

      if octopus.kv:get("life") <= 0 then
        return
      end

      if #bullet_pool > 0 then
        local bullet = table.remove(bullet_pool)
        local x = (player.x + player.size.width) + 100
        local y = player.y + 10
        local offset_y = (math.random(-2, 2)) * 30

        bullet.placement:set(x, y + offset_y)
        bullet.action:set("default")
        bullet.velocity.x = 800

        local sound = "bomb" .. math.random(1, 2)
        soundmanager:play(sound)
      end
    end
  else
    key_states[KeyEvent.space] = false
  end
end
```

### In The End

In the end, he requested some _minor_ tweaks, such as the projectile being the princess sprite, the target being the player, and the entity that shoots being the green octopus. 🤷‍♂️

![Tweaks](/public/2024-10-08-my-first-game-with-carimbo/tweaks.jpeg){: .center }
