---
layout: post
title: >
  Flipping bits whilst updating pixels
---

> I have less than 16 milliseconds to do more than thousands of operations.

Roughly 15 years ago, during an extended summer holiday, in a shared room of a student residence, I found myself endeavoring to port [my 2D game](https://github.com/skhaz/wintermoon) engine built on top of [SDL](https://en.wikipedia.org/wiki/Simple_DirectMedia_Layer) to the [Google Native Client \(NaCl\)](https://en.wikipedia.org/wiki/Google_Native_Client). NaCl served as a sandboxing mechanism for Chrome, enabling the execution of native code within the browser, specifically within the Chrome browser. It's safe to assert that NaCl can be considered the progenitor of WebAssembly.

A considerable amount of time has elapsed, and many changes have transpired. I transitioned from game development to web development, yet low-level programming has always coursed through my veins. Consequently, I resolved to revive the dream of crafting my own game engine running on the web. Today, with the advent of WebAssembly, achieving this goal is significantly more feasible and portable.

Therefore, I created Carimbo 🇧🇷, meaning "stamp" in English. The name encapsulates the notion that 2D engines are continually stamping sprites onto the screen.

![](/public/2023-11-12-flipping-bits-whilst-updating-pixels/carimbo.png)

This engine shares the foundational principles of _Wintermoon_; it is built upon the SDL library, employs Lua for scripting, and consolidates all assets within a compressed LZMA file, which is unpacked when the engine initializes.

In essence, it operates as follows: video, audio, joystick, network, and file system components are initialized. Then, the 'bundle.zip' file is mounted. When I say 'mounted,' I employ a library that makes read and write operations within the compressed file entirely transparent, eliminating the need for decompression, which is excellent. Subsequently, the 'main.lua' file is executed. This file should utilize the factory to construct the engine, which is the cornerstone. Following this, the script must spawn entities and other objects to be used within the game. Finally, with the game defined, the script should invoke the 'run' method of the engine, which will block and initiate the event loop.

However, this time around, the tooling for C++ has significantly improved compared to that era. Numerous package managers now exist, and compilers, along with the standard library, have matured considerably. Notably, there's no longer a necessity to employ Boost for advanced features; many functionalities, including smart pointers and others formerly associated with Boost, are now integral parts of the standard library.

Speaking of package managers, in Carimbo, I opted for [Conan](https://conan.io/), which, in my opinion, is an excellent package manager.

It was during this exploration that I discovered Conan's support for various toolings, including `[emsdk](https://github.com/emscripten-core/emsdk)`—the Software Development Kit (SDK) and compiler for the Emscripten project. Emscripten is an LLVM/Clang-based compiler designed to translate C and C++ source code into WebAssembly.

With the `emsdk`, I could finally fulfill my long-held aspiration.

![](/public/2023-11-12-flipping-bits-whilst-updating-pixels/blank.jpeg)

Yes, a black screen and an overwhelming sense of victory. I had successfully ported my code to run in the browser. Now, all that remained was to figure out how to load the assets. However, the event loop was running just a tad below 60 frames per second due to a bug in the counter.

And you might be wondering, 'How do you debug this?' Firstly, for various reasons that can burden the final binary, a lot is stripped away. Therefore, we need to recompile everything and all dependencies with sanitizers and debugging symbols. Secondly, WebAssembly should be linked with **sASSERTIONS=2**, **-sRUNTIME_DEBUG**, and **--profiling**. This way, it's possible to see the stack trace in the browser console as if by magic. Additionally, [Chrome has a debugger](https://developer.chrome.com/blog/wasm-debugging-2020/) that allows you to insert breakpoints within your source code and inspect step by step.

By the way, a binary and all its dependencies compiled with all sanitizers and debugging symbols can easily surpass 300 megabytes! So, I recommend compiling with -Os or -O1.

<iframe src="https://trial.carimbo.cloud/" width="800%" height="600px" frameborder="0"></iframe>

[The source code for the Carimbo](https://github.com/carimbolabs/carimbo)
