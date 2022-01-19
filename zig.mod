id: qqo54zxu6pnza9tw4n9r0yrfjrs353genlx4grwd7cef30m9
name: koino
main: src/koino.zig
license: MIT
description: CommonMark + GFM compatible Markdown parser and renderer
dependencies:
  - src: git https://github.com/kivikakk/htmlentities.zig
  - src: git https://github.com/kivikakk/libpcre.zig
  - src: git https://github.com/kivikakk/zunicode

root_dependencies:
  - src: git https://github.com/Hejsil/zig-clap branch-zig-master
