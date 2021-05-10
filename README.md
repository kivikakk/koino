# koino

![Build status](https://github.com/kivikakk/koino/workflows/Zig/badge.svg)
![Spec Status: 671/671](https://img.shields.io/badge/specs-671%2F671-brightgreen.svg)

Zig port of [Comrak](https://github.com/kivikakk/comrak).  Maintains 100% spec-compatibility with [GitHub Flavored Markdown](https://github.github.com/gfm/).


## Getting started

* Clone the repository with submodules, as we have quite a few dependencies.

  ```console
  $ git clone --recurse-submodules https://github.com/kivikakk/koino
  ```
  
* [Follow the `libpcre.zig` dependency install instructions](https://github.com/kivikakk/libpcre.zig/blob/main/README.md) for your operating system.

* Build and run the spec suite.

  ```console
  $ zig build test
  $ make spec
  ```

* Have a look at the bottom of [`parser.zig`](https://github.com/kivikakk/koino/blob/main/src/parser.zig) to see some test usage.


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

