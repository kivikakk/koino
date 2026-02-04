
# CommonMark + GitHub Flavored Markdown (GFM) — Feature demo

This file demonstrates CommonMark core features and common GFM extensions
(tables, task lists, strikethrough, autolinks, mentions, emoji, collapsible
sections, etc.).

---

## Headings

ATX-style headings:

```md
# H1
## H2
### H3
#### H4
##### H5
###### H6
```

Setext-style (underline) headings:

```md
Heading level 1
================

Heading level 2
----------------
```
---

## Paragraphs and line breaks

A paragraph is one or more lines of text separated by one or more blank lines.

Soft line break (CommonMark):
This is a soft line break
that becomes a space in HTML.

Hard line break (add two spaces at end of line)  
This is a hard line break (two spaces then newline).

---

## Thematic break

---  

***

___

---

## Emphasis and strong

- Emphasis: *italic* or _italic_
- Strong: **bold** or __bold__
- Combined: **This is _bold and italic_ together**

Escaped characters: \*not italic\* → `*not italic*`

---

## Strikethrough (GFM)

This is ~~deleted~~ text.

---

## Inline code and code blocks

Inline code: `std.debug.pring("hello\n", .{});`

Fenced code block (backticks) with language hint (syntax highlighting on GitHub):

```zig
const std = @import("std");

pub fn main() !void {
    std.debug.print("Hello, World!\n", .{});
}
```

Fenced code block (tildes):

~~~text
This is a plain fenced block using tildes.
~~~

Code span with backticks in content: use `` `code with `backticks` inside` ``

Indented code blocks (CommonMark): four-space indent
    indented code line 1
    indented code line 2

---

## Blockquotes

### Plain

> This is a blockquote.
>
> > Nested blockquote.
> >
> > - Nested list item inside blockquote
> > - Another item
>
> Inline code in quote: `example()`

### Alerts

> [!NOTE]  
> Highlights information that users should take into account, even when skimming.

> [!TIP]
> Optional information to help a user be more successful.

> [!IMPORTANT]  
> Crucial information necessary for users to succeed.

> [!WARNING]  
> Critical content demanding immediate user attention due to potential risks.

> [!CAUTION]
> Negative potential consequences of an action.

---

## Lists

Unordered list:
- Item A
- Item B
  - Subitem B.1
  - Subitem B.2

Ordered list (starts at 1):
1. First
2. Second
   1. Sub-first
   2. Sub-second

Ordered list with custom start (CommonMark allows any start number):
5. Start at five
6. Next

GFM task list (checkboxes):
- [x] Completed task
- [ ] Open task
- [ ] Another task

---

## Links and references

Inline link: [Zig website](https://ziglang.org)

Reference-style link:
This uses a [reference link][example].

[example]: https://example.com "Example site"

Autolinks (GFM/CommonMark autolink):
<http://example.com>
<user@example.com>

Image (inline):
![Alt text: small kitten](https://placekitten.com/120/80 "Kitten")

Reference image:
![logo][logo-ref]

[logo-ref]: https://upload.wikimedia.org/wikipedia/commons/4/4f/Iconic_image_example.svg "Logo (reference)"

---

## Tables (GFM)

Simple table:

| Name     | Age | Notes               |
|:---------|:---:|--------------------:|
| Alice    |  30 | Left-aligned name   |
| Bob      |  25 | Center age, right notes |
| Charlie  |  23 | —                   |

Alignment examples:

| Left (default) | Center | Right  |
|:---------------|:-----:|-------:|
| left text      | center | right  |
| foo            | bar   | baz    |

Note: Tables are a GFM extension (not core CommonMark).

---

## HTML passthrough (allowed; rendered as HTML)

You can include raw HTML. Example: keyboard key element and details/summary
(GFM supports this on GitHub):

<kbd>Ctrl</kbd> + <kbd>C</kbd>

<details>
<summary>Click to expand</summary>

### Collapsible content

This content is hidden until the summary is clicked. You can put lists, code, images, etc.

- Item 1
- Item 2

</details>

---

## Mentions, issue/PR refs, and emoji (GFM)

- Mention a user: @octocat  (only works on GitHub to link a username)
- Reference an issue: #123  (links on GitHub)
- Emoji shortcodes: :smile: :rocket: :bug:

---

## Autolinks and bare URLs

URLs in angle brackets are autolinked: <https://example.com>

Bare URLs in GFM are automatically turned into links in many renderers:
https://ziglang.org

---

## Reference-style resources and footnote-like links

Reference links allow you to define URLs separately:

See the [Zig site][zig].

[zig]: https://ziglang.org

Note: GFM does not provide native "footnotes" in the CommonMark spec; some
renderers support footnote extensions, but they are not standard on GitHub.

---

## Inline HTML comments and entity examples

This is visible text. <!-- This comment is hidden in rendered HTML -->

Use entities when needed: &amp; &lt; &gt;

---

## Accessibility & images

Use alt text for accessibility:
![A kitten looking up](https://placekitten.com/200/140 "Kitten looking up")

---

## Notes — What is CommonMark vs. GFM

- CommonMark defines the baseline, unambiguous Markdown syntax (headings, lists,
  code fences, blockquotes, emphasis, links, reference links, etc.).
- GFM (GitHub Flavored Markdown) adds commonly-used extensions:
  - Tables
  - Task lists (checkboxes)
  - Strikethrough (`~~`)
  - Autolinking bare URLs and email addresses
  - @mentions, #issue references, and emoji shortcodes
  - Collapsible `<details>`/`<summary>` blocks (HTML)
  - Syntax highlighting for fenced code blocks (via language hints)

Features not universally supported:
- Footnotes are not part of CommonMark; some implementations/extensions add them.
- Certain HTML tags may be sanitized on some platforms for security.

## LaTeX

### Inline

This sentence uses `$` delimiters to show math inline: $\sqrt{3x-1}+(1+x)^2$.

This sentence uses $\` and \`$ delimiters to show math inline: $`\sqrt{3x-1}+(1+x)^2`$.

### Block

**The Cauchy-Schwarz Inequality**\
$$\left( \sum_{k=1}^n a_k b_k \right)^2 \leq \left( \sum_{k=1}^n a_k^2 \right) \left( \sum_{k=1}^n b_k^2 \right)$$

**The Cauchy-Schwarz Inequality**

```math
\left( \sum_{k=1}^n a_k b_k \right)^2 \leq \left( \sum_{k=1}^n a_k^2 \right) \left( \sum_{k=1}^n b_k^2 \right)
```

### Using a Dollar Sign

#### Within a Math Expression

Within a math expression, add a \ symbol before the explicit $.

This expression uses `\$` to display a dollar sign: $`\sqrt{\$4}`$
Screenshot of rendered Markdown showing how a backslash before a dollar sign
displays the sign as part of a mathematical expression.

#### Outside a Math Expression

Outside a math expression, but on the same line, use span tags around the explicit $.

To split <span>$</span>100 in half, we calculate $100/2$

## References

[GitHub Flavored Markdown][GFM]
[GitHub Alerts][GA]
[Writing Mathematical Expressions][WME]

[GFM]: https://github.github.com/gfm "GitHub Flavored Markdown"
[GA]: https://github.com/orgs/community/discussions/16925 "GitHub Alerts"
[WME]: https://docs.github.com/en/get-started/writing-on-github/working-with-advanced-formatting/writing-mathematical-expressions "Writing Mathematical Expressions"
