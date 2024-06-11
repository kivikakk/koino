# [koino](https://github.com/kivikakk/koino)

![Build status](https://github.com/kivikakk/koino/workflows/Zig/badge.svg)
![Spec Status: 671/671](https://img.shields.io/badge/specs-671%2F671-brightgreen.svg)

Zig port of [Comrak](https://github.com/kivikakk/comrak).  Maintains 100% spec-compatibility with [GitHub Flavored Markdown](https://github.github.com/gfm/).


## Getting started

## Using koino as a library

* Get Zig 0.12 https://ziglang.org/
  * Using Zig 0.13? See [`zig-0.13.0`](https://github.com/kivikakk/koino/tree/zig-0.13.0) branch.
* Start a new project with `zig init-exe` / `zig init-lib`
* Add koino via the zig package manager:
  ```console
  $ zig fetch --save https://github.com/kivikakk/koino/archive/<commit hash>.tar.gz
  ```
 
* [Follow the `libpcre.zig` dependency install instructions](https://github.com/kivikakk/libpcre.zig/blob/main/README.md) for your operating system.
* Add the following to your `build.zig`'s `build` function:
  ```zig
  const koino_pkg = b.dependency("koino", .{ .optimize = optimize, .target = target });
  exe.root_module.addImport("koino", koino_pkg.module("koino"));
  ```

* Have a look at the bottom of [`parser.zig`](https://github.com/kivikakk/koino/blob/main/src/parser.zig) to see some test usage.

### Using it as a CLI executable

* Clone this repository:
  ```console
  $ git clone https://github.com/kivikakk/koino
  ```
* Build
  ```console
  $ zig build
  ```
* Use `./zig-out/bin/koino`

### For development purposes

* Clone this repository with submodules for the `cmark-gfm` dependency:
  ```console
  $ git clone --recurse-submodules https://github.com/kivikakk/koino
  $ cd koino
  ```

* Build and run the spec suite.

  ```console
  $ zig build test
  $ make spec
  ```


## Usage

Command line:

```console
$ koino --help
Usage: koino [-hu] [-e <EXTENSION>...] [--smart]

Options:
        -h, --help                      Display this help and exit
        -u, --unsafe                    Render raw HTML and dangerous URLs
        -e, --extension <EXTENSION>...  Enable an extension. (table,strikethrough,autolink,tagfilter)
            --smart                     Use smart punctuation.
```

Library:

Documentation is TODO — see [LoLa](https://github.com/MasterQ32/LoLa/blob/d02b0e6774fedbe07276d8af51e1a305cc58fb34/src/tools/render-md-page.zig#L157) for an example of use. Note also the [`build.zig`](https://github.com/MasterQ32/LoLa/blob/d02b0e6774fedbe07276d8af51e1a305cc58fb34/build.zig#L41-L50) declaration.

