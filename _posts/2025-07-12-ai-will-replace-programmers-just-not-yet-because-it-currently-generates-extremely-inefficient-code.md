---
layout: post
title: >
  AI will replace programmers—just not yet, because it still generates very extremely inefficient code.
---

I was working on my engine, which includes a sort of canvas where Lua code can generate chunks of pixels and send them in batches for the C++ engine to render.
This worked very well and smoothly at 60 frames per second with no frame drops at low resolutions (240p, which is the screen size of my games).
However, when I happened to try 1080p, the frame rate dropped.

Since I was in a rush and a bit lazy—because I can’t afford to spend too much time on personal projects—I decided to use AI to optimize it, and this was the best solution I could squeeze out.
It went from 40 FPS down to 17, much worse than the initial implementation!

AI Code:

```c++
[](graphics::canvas& canvas, sol::table table) {
  const auto n = table.size();
  static std::vector<uint32_t> buffer;

  if (buffer.size() != n) [[unlikely]] {
    buffer.resize(n);
  }

  const auto L = table.lua_state();

  table.push();
  const int table_idx = lua_gettop(L);

  uint32_t* const data = buffer.data();

  constexpr std::size_t batch_size = 8;
  const std::size_t full_batches = n / batch_size;

  for (std::size_t batch = 0; batch < full_batches; ++batch) {
    const std::size_t start_idx = batch * batch_size;

    for (std::size_t j = 0; j < batch_size; ++j) {
      lua_rawgeti(L, table_idx, static_cast<int>(start_idx + j + 1));
    }

    for (std::size_t j = batch_size; j > 0; --j) {
      data[start_idx + j - 1] = static_cast<uint32_t>(lua_tointeger(L, -1));
      lua_pop(L, 1);
    }
  }

  const std::size_t remaining_start = full_batches * batch_size;
  for (std::size_t i = remaining_start; i < n; ++i) {
    lua_rawgeti(L, table_idx, static_cast<int>(i + 1));
    data[i] = static_cast<uint32_t>(lua_tointeger(L, -1));
    lua_pop(L, 1);
  }

  lua_pop(L, 1);
  canvas.set_pixels(buffer);
}
```

Naturally, the code was not just complex, but also way slower.

That’s when I decided to take my brain off the shelf and came up with this solution:

```cpp
[](graphics::canvas& canvas, const char* data) {
  canvas.set_pixels(reinterpret_cast<const uint32_t*>(data));
}
```

Kabum! Smooth 60 frames per second, even at 8K resolution or higher.
