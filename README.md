# koino

![Spec Status: 671/671](https://img.shields.io/badge/specs-671%2F671-brightgreen.svg)

Zig port of [Comrak](https://github.com/kivikakk/comrak).  Maintains 100% spec-compatibility with [GitHub Flavored Markdown](https://github.github.com/gfm/).


## Getting started

### Using koino as a library

* Add koino via the zig package manager:
  ```console
  $ zig fetch --save git+https://nossa.ee/~talya/koino
  ```
 
* Add the following to your `build.zig`'s `build` function:
  ```zig
  const koino_pkg = b.dependency("koino", .{ .optimize = optimize, .target = target });
  exe.root_module.addImport("koino", koino_pkg.module("koino"));
  ```

* Have a look at the bottom of [`parser.zig`](src/parser.zig) to see some test usage.


### Using it as a CLI executable

* Clone this repository:
  ```console
  $ git clone https://nossa.ee/~talya/koino
  ```
* Build
  ```console
  $ zig build
  ```
* Use `./zig-out/bin/koino`


### Development

There's a `flake.nix` for building or getting a devShell if you're so-inclined.

* Clone this repository (with submodules for the `cmark-gfm` dependency):
  ```console
  $ git clone --recurse-submodules https://nossa.ee/~talya/koino
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
Usage: koino [-hu] [-e <str>...] [--header-anchors] [--smart] <str>

Options:
    -h, --help
            Display this help and exit

    -u, --unsafe
            Render raw HTML and dangerous URLs

    -e, --extension <str>...
            Enable an extension (table,strikethrough,autolink,tagfilter)

        --header-anchors
            Generate anchors for headers

        --smart
            Use smart punctuation

    <str>
```

Library:

Documentation is TODO — see:

- [LoLa](https://github.com/MasterQ32/LoLa/blob/d02b0e6774fedbe07276d8af51e1a305cc58fb34/src/tools/render-md-page.zig#L157): for an example of use. Note also the [`build.zig`](https://github.com/MasterQ32/LoLa/blob/d02b0e6774fedbe07276d8af51e1a305cc58fb34/build.zig#L41-L50) declaration.
- [Markdown to HTML example](./examples/to-html.zig).

