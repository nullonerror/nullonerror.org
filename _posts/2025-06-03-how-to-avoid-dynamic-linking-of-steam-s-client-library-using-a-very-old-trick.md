---
layout: post
title: >
  How to avoid dynamic linking of Steam’s client library using a very old trick
---

As you know, this blog is more focused on sharing code snippets than on teaching, so today I’m going to show you something I recently discovered.

If you’ve been following me, you know I’ve been working in my free time on a 2D game engine where creators can build games using only Lua — and I’d say, even fairly complex ones.

Right now, I’m working on a point-and-click game that you can play here: https://bereprobate.com/. It’s built using this same engine, and I’m publishing builds in parallel to Steam and the Web using GitHub Actions.

The thing is, Steam — which is the main target platform for this game — supports achievements, and I want to include them. But to use achievements, you have to link the Steam library to your engine. The problem is, doing that creates a dependency on that library in the binaries, which I don’t want. I also don’t want to maintain a separate build just for that.

Then I thought: “Why not load the Steam library dynamically? Use LoadLibraryA on Windows and dlopen on macOS. (Sorry Linux — it’s Proton-only for now.)”

I tried the experiment below, and it worked. If the DLL/dylib is present, the Steam features work just fine. If not, everything runs normally.

```cpp
#include "steam.hpp"

#if defined(_WIN32)
  #include <windows.h>
  #define DYNLIB_HANDLE HMODULE
  #define DYNLIB_LOAD(name) LoadLibraryA(name)
  #define DYNLIB_SYM(lib, name) GetProcAddress(lib, name)
  #define STEAM_LIB_NAME "steam_api64.dll"
#elif defined(__APPLE__)
  #include <dlfcn.h>
  #define DYNLIB_HANDLE void*
  #define DYNLIB_LOAD(name) dlopen(name, RTLD_LAZY)
  #define DYNLIB_SYM(lib, name) dlsym(lib, name)
  #define STEAM_LIB_NAME "libsteam_api.dylib"
#endif

#ifndef S_CALLTYPE
  #define S_CALLTYPE __cdecl
#endif

#if defined(DYNLIB_LOAD)

using SteamAPI_InitSafe_t     = bool(S_CALLTYPE *)();
using SteamAPI_Shutdown_t     = void(S_CALLTYPE *)();
using SteamAPI_RunCallbacks_t = void(S_CALLTYPE *)();
using SteamUserStats_t        = void*(S_CALLTYPE *)();
using GetAchievement_t        = bool(S_CALLTYPE *)(void*, const char*, bool*);
using SetAchievement_t        = bool(S_CALLTYPE *)(void*, const char*);
using StoreStats_t            = bool(S_CALLTYPE *)(void*);

static DYNLIB_HANDLE hSteamApi = DYNLIB_LOAD(STEAM_LIB_NAME);

#define LOAD_SYMBOL(name, sym) reinterpret_cast<name>(reinterpret_cast<void*>(DYNLIB_SYM(hSteamApi, sym)))

static const auto pSteamAPI_InitSafe     = LOAD_SYMBOL(SteamAPI_InitSafe_t, "SteamAPI_InitSafe");
static const auto pSteamAPI_Shutdown     = LOAD_SYMBOL(SteamAPI_Shutdown_t, "SteamAPI_Shutdown");
static const auto pSteamAPI_RunCallbacks = LOAD_SYMBOL(SteamAPI_RunCallbacks_t, "SteamAPI_RunCallbacks");
static const auto pSteamUserStats        = LOAD_SYMBOL(SteamUserStats_t, "SteamAPI_SteamUserStats_v013");
static const auto pGetAchievement        = LOAD_SYMBOL(GetAchievement_t, "SteamAPI_ISteamUserStats_GetAchievement");
static const auto pSetAchievement        = LOAD_SYMBOL(SetAchievement_t, "SteamAPI_ISteamUserStats_SetAchievement");
static const auto pStoreStats            = LOAD_SYMBOL(StoreStats_t, "SteamAPI_ISteamUserStats_StoreStats");

bool SteamAPI_InitSafe() {
  return pSteamAPI_InitSafe ? pSteamAPI_InitSafe() : false;
}

void SteamAPI_Shutdown() {
  pSteamAPI_Shutdown ? pSteamAPI_Shutdown() : void();
}

void SteamAPI_RunCallbacks() {
  pSteamAPI_RunCallbacks ? pSteamAPI_RunCallbacks() : void();
}

void* SteamUserStats() {
  return pSteamUserStats ? pSteamUserStats() : nullptr;
}

bool GetAchievement(const char* name) {
  bool achieved = false;
  return pGetAchievement ? (pGetAchievement(SteamUserStats(), name, &achieved) && achieved) : false;
}

bool SetAchievement(const char* name) {
  return pSetAchievement ? pSetAchievement(SteamUserStats(), name) : false;
}

bool StoreStats() {
  return pStoreStats ? pStoreStats(SteamUserStats()) : false;
}

#else

bool SteamAPI_InitSafe()            { return false; }
void SteamAPI_Shutdown()           {}
void SteamAPI_RunCallbacks()       {}
void* SteamUserStats()             { return nullptr; }
bool GetAchievement(const char*)   { return false; }
bool SetAchievement(const char*)   { return false; }
bool StoreStats()                  { return false; }

#endif
```

Achivement class

```cpp
void achievement::unlock(std::string id) {
  if (!SteamUserStats()) {
    return;
  }

  const auto* ptr = id.c_str();

  if (GetAchievement(ptr)) {
    return;
  }

  SetAchievement(ptr);
  StoreStats();
}
```

Binding

```cpp
steam::achievement achievement;

lua.new_usertype<steam::achievement>(
  "Achievement",
  "unlock", &steam::achievement::unlock
);

lua["achievement"] = &achievement;
```

Usage

```lua
achievement:unlock("NEW_ACHIEVEMENT_1_3")
```
