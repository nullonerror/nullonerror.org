---
layout: post
title: >
  Poor's Man Shaders
---

>Spoiler: it’s not shaders

I’m waiting for a universal solution that the SDL developers are working on — cross-platform, multi-API shaders, the [SDL_shadercross](https://github.com/libsdl-org/SDL_shadercross). The idea is that you write shaders in a single language, and at runtime, they get compiled for the target GPU. Unfortunately, it’s a large and complex project, and it will take time before it becomes stable.

In the meantime, in my [Carimbo](https://github.com/willtobyte/carimbo)  engine, I was wondering if I could implement something similar to shaders — something that would allow Lua code to write arbitrary pixels into a buffer and stream that buffer into a texture.

So I created what I call a canvas, which is basically a texture the same size as the screen, rendered after certain elements.

```cpp
canvas::canvas(std::shared_ptr<renderer> renderer)
    : _renderer(std::move(renderer)) {
  int32_t lw, lh;
  SDL_RendererLogicalPresentation mode;
  SDL_GetRenderLogicalPresentation(*_renderer, &lw, &lh, &mode);

  float_t sx, sy;
  SDL_GetRenderScale(*_renderer, &sx, &sy);

  const auto width = static_cast<int32_t>(std::lround(static_cast<float>(lw) / sx));
  const auto height = static_cast<int32_t>(std::lround(static_cast<float>(lh) / sy));

  SDL_Texture *texture = SDL_CreateTexture(*_renderer, SDL_PIXELFORMAT_ARGB8888, SDL_TEXTUREACCESS_STREAMING, width, height);
  if (!texture) [[unlikely]] {
    throw std::runtime_error(std::format("[SDL_CreateTexture] {}", SDL_GetError()));
  }

  SDL_SetTextureBlendMode(texture, SDL_BLENDMODE_BLEND);

  _framebuffer.reset(texture);
}

void canvas::set_pixels(const uint32_t* pixels) noexcept {
  const auto ptr = _framebuffer.get();
  const auto pitch = static_cast<int>(static_cast<size_t>(ptr->w) * sizeof(uint32_t));

  SDL_UpdateTexture(ptr, nullptr, pixels, pitch);
}
```

The set_pixel function receives a pointer to a uint32_t buffer that exactly matches the texture size. This pointer is actually a Lua string, which I found to be the most performant way to transfer data between Lua and C++ without relying on preallocated buffers.

This way:

```cpp
lua.new_usertype<graphics::canvas>(
  "Canvas",
  sol::no_constructor,
  "pixels", sol::property(
    [](const graphics::canvas&) {
      return nullptr;
    },
    [](graphics::canvas& canvas, const char* data) {
      canvas.set_pixels(reinterpret_cast<const uint32_t*>(data));
    }
  )
);
```

On Lua side:

```lua
function Effect:new(width, height)
  local w, h = width or 480, height or 270
  local canvas = engine:canvas()
  local self = setmetatable({
    canvas = canvas,
    w = w,
    h = h,
  }, Effect)

  return self
end

function Light:loop()
  self.canvas.pixels = rep(char(0, 0, 0, 220), self.w * self.h)
end

```

Some effects I’ve created so far:

[https://youtu.be/GUWTWRQuzxw](https://youtu.be/GUWTWRQuzxw)

[https://youtu.be/usJ9QM7V8BI](https://youtu.be/usJ9QM7V8BI)
