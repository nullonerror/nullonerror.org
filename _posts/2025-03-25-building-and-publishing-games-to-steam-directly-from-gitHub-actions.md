---
layout: post
title: >
  Building and Publishing Games to Steam Directly from GitHub Actions
---

I have been using GitHub Actions extensively both at work and in personal projects, as shown in this post [What I’ve been automating with GitHub Actions, an automated life](https://nullonerror.org/2023/11/01/what-i-ve-been-automating-with-github-actions-an-automated-life/).

In my free time, I’m working on a 2D hide-and-seek game, and as you might expect, I’ve automated the entire release pipeline for publishing on Steam. After a few attempts, when it finally worked, it felt like magic: all I had to do was create a new tag, and within minutes, the Steam client was downloading the update.

As I mentioned earlier, I have a 2D engine that, while simple, is quite comprehensive. With each new tag, I compile it in parallel for Windows, macOS, Linux, and WebAssembly. Once compilation is complete, I create a release and publish it on GitHub. [Releases · willtobyte/carimbo](https://github.com/willtobyte/carimbo/releases)

This way

```yaml
name: Release

on:
  push:
    tags:
      - "v*.*.*"

jobs:
  release:
    runs-on: ${{ matrix.config.os }}

    permissions:
      contents: write

    strategy:
      fail-fast: true

      matrix:
        config:
          - name: macOS
            os: macos-latest
          - name: Ubuntu
            os: ubuntu-latest
          - name: WebAssembly
            os: ubuntu-latest
          - name: Windows
            os: windows-latest

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Cache Dependencies
        uses: actions/cache@v4
        with:
          path: |
            ~/.conan2/p
            C:/Users/runneradmin/.conan2/p
          key: ${{ matrix.config.name }}-${{ hashFiles('**/conanfile.py') }}
          restore-keys: |
            ${{ matrix.config.name }}-

      - name: Prepare Build Directory
        run: mkdir build

      - name: Setup Python
        uses: actions/setup-python@v5
        with:
          python-version: "3.12"

      - name: Install Conan
        run: pip install conan

      - name: Detect Conan Profile
        run: conan profile detect --force

      - name: Set Conan Center
        run: conan remote update conancenter --url https://center2.conan.io

      - name: Detect WebAssembly Conan Profile
        if: matrix.config.name == 'WebAssembly'
        run: |
          cat > ~/.conan2/profiles/webassembly <<EOF
          include(default)

          [settings]
          arch=wasm
          os=Emscripten

          [tool_requires]
          *: emsdk/3.1.73
          EOF

      - name: Install Windows Or macOS Dependencies
        if: matrix.config.name == 'Windows' || matrix.config.name == 'macOS'
        run: conan install . --output-folder=build --build=missing --settings compiler.cppstd=20 --settings build_type=Release

      - name: Install Ubuntu Dependencies
        if: matrix.config.name == 'Ubuntu'
        run: conan install . --output-folder=build --build=missing --settings compiler.cppstd=20 --settings build_type=Release --conf "tools.system.package_manager:mode=install" --conf "tools.system.package_manager:sudo=True"

      - name: Install WebAssembly Dependencies
        if: matrix.config.name == 'WebAssembly'
        run: conan install . --output-folder=build --build=missing --profile=webassembly --settings compiler.cppstd=20 --settings build_type=Release

      - name: Configure
        run: cmake .. -DCMAKE_TOOLCHAIN_FILE="conan_toolchain.cmake" -DCMAKE_BUILD_TYPE=Release
        working-directory: build

      - name: Build
        run: cmake --build . --parallel 8 --config Release --verbose
        working-directory: build

      - name: Create Artifacts Directory
        run: mkdir artifacts

      - name: Compress Artifacts
        if: matrix.config.name == 'macOS'
        working-directory: build
        run: |
          chmod -R a+rwx carimbo
          tar -cpzvf macOS.tar.gz carimbo
          mv macOS.tar.gz ../artifacts

      - name: Compress Artifacts
        if: matrix.config.name == 'Ubuntu'
        working-directory: build
        run: |
          chmod +x carimbo
          tar -czvf Ubuntu.tar.gz --mode='a+rwx' carimbo
          mv Ubuntu.tar.gz ../artifacts

      - name: Compress Artifacts
        if: matrix.config.name == 'WebAssembly'
        working-directory: build
        run: |
          zip -jr WebAssembly.zip carimbo.wasm carimbo.js
          mv WebAssembly.zip ../artifacts

      - name: Compress Artifacts
        if: matrix.config.name == 'Windows'
        working-directory: build
        shell: powershell
        run: |
          Compress-Archive -LiteralPath 'Release/carimbo.exe' -DestinationPath "../artifacts/Windows.zip"

      - name: Release
        uses: softprops/action-gh-release@v1
        with:
          tag_name: ${{ github.event.inputs.tagName }}
          prerelease: ${{ github.events.inputs.prerelease }}
          files: artifacts/*
```

Publishing on Steam is quite simple. First, you need a developer account with the correct documentation and fees paid.

After that, you’ll need to generate some secret keys as follows:

```shell
steamcmd +login <username> <password> +quit
```

If you don’t have the steamcmd application installed, you’ll need to install it using:

```shell
cast install --cask steamcmd
```

Copy the contents of the authentication file:

```shell
cat ~/Library/Application\ Support/Steam/config/config.vdf | base64 | pbcopy
```

**Note:** You must have MFA enabled. After logging in, run the command below and copy the output into a GitHub Action variable named `STEAM_CONFIG_VDF`.

Also, create the variables `STEAM_USERNAME` with your username and `STEAM_APP_ID` with your game’s ID.

Additionally, the Action downloads the latest Carimbo release for Windows only (sorry Linux and macOS users, my time is limited). Ideally, I should pin the runtime version (the Carimbo version) using something like a runtime.txt file. Maybe I’ll implement this in the future, but for now, everything runs on the bleeding edge. :-)

```yaml
on:
  push:
    tags:
      - "v*.*.*"

jobs:
  publish:
    runs-on: ubuntu-latest
    env:
      CARIMBO_TAG: "v1.0.65"

    permissions:
      contents: write

    steps:
      - name: Clone the repository
        uses: actions/checkout@v4

      - name: Install 7zip
        run: sudo apt install p7zip-full

      - name: Create bundle
        run: 7z a -xr'!.git/*' -xr'!.git' -xr'!.*' -t7z -m0=lzma -mx=6 -mfb=64 -md=32m -ms=on bundle.7z .

      - name: Download Carimbo runtime
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: gh release download ${{ env.CARIMBO_TAG }} --repo willtobyte/carimbo --pattern "Windows.zip"

      - name: Extract Carimbo runtime
        run: 7z x Windows.zip -o.

      - name: Copy files
        run: |
          mkdir -p output
          mv bundle.7z output/
          mv carimbo.exe output/

      - name: Upload build to Steam
        uses: game-ci/steam-deploy@v3
        with:
          username: ${{ secrets.STEAM_USERNAME }}
          configVdf: ${{ secrets.STEAM_CONFIG_VDF }}
          appId: ${{ secrets.STEAM_APP_ID }}
          rootPath: output
          depot1Path: "."
          releaseBranch: prerelease
```

Boom! If everything is correct, your game should appear in your Steam client under the list of owned games.
