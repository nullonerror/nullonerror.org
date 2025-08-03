---
layout: post
title: >
  Replacing Lua’s math.random module with the Xorshift algorithm
---

I recently discovered that _V8_, the engine behind _Node.js_ and _Chrome_, has been using `xorshift128+` since ***2014***. Out of curiosity, I checked what the _Lua VM_ uses, and to my surprise, it relies on the standard C library, which is extremely slow.

You can find more details here: [v8/src/numbers/math-random.cc at main · v8/v8](https://github.com/v8/v8/blob/main/src/numbers/math-random.cc)

I’m currently working on a [game](https://reprobate.site/) that uses random in the main loop, which is quite slow. So to work around that, I implemented a pseudo-random function.

```lua
local seed = os.time()
local function random()
  seed = (1103515245 * seed + 12345) % 2147483648
  return seed
end
```

This is a *Linear Congruential Generator (LCG)* — one of the oldest and simplest methods for generating pseudorandom numbers.
For the noise effect, I end up calling random up to 6 times per loop, which is extremely costly, and not even the C++ implementation of `xorshift128+` below could save me.

Anyway, I ended up replacing Lua’s implementation with the one below, because optimizations are always welcome — especially when the gain in randomness is significantly higher.

```cpp
static std::array<uint64_t, 2> prng_state;

void seed(uint64_t value) {
  constexpr uint64_t mix = 0xdeadbeefcafebabeULL;
  if (value == 0) value = 1;
  prng_state[0] = value;
  prng_state[1] = value ^ mix;
}

uint64_t xorshift128plus() {
  const auto s1 = prng_state[0];
  const auto s0 = prng_state[1];
  const auto result = s0 + s1;

  prng_state[0] = s0;
  prng_state[1] = (s1 ^ (s1 << 23)) ^ s0 ^ ((s1 ^ (s1 << 23)) >> 18) ^ (s0 >> 5);

  return result;
}

double xorshift_random_double() {
  static constexpr const auto inv_max = 1.0 / static_cast<double>(std::numeric_limits<uint64_t>::max());

  return static_cast<double>(xorshift128plus()) * inv_max;
}

lua_Integer xorshift_random_int(const lua_Integer low, const lua_Integer high) {
  const auto ulow = static_cast<uint64_t>(low);
  const auto range = static_cast<uint64_t>(high - low + 1);
  return static_cast<lua_Integer>(ulow + (xorshift128plus() % range));
}

const auto now = std::chrono::high_resolution_clock::now().time_since_epoch().count();
seed(static_cast<uint64_t>(now));

lua["math"]["random"] = sol::overload(
  []() -> double {
    return xorshift_random_double();
  },
  [](lua_Integer upper) -> lua_Integer {
    return xorshift_random_int(1, upper);
  },
  [](lua_Integer lower, lua_Integer upper) -> lua_Integer {
    return xorshift_random_int(lower, upper);
  }
);

lua["math"]["randomseed"] = [](lua_Integer seed_value) {
  seed(static_cast<uint64_t>(seed_value));
};
```
