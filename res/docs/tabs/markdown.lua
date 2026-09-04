return {

  intro = table.concat({
    "santoku-markdown is the framework's Markdown renderer: a C binding to Sundown ",
    "that exposes a single function, to_html, taking a Markdown string and returning ",
    "the rendered HTML string. The binding constructs Sundown's standard HTML renderer ",
    "with every extension flag and every render flag set to zero and a block nesting ",
    "depth of 16, so what you get is base Markdown exactly: ATX and setext headings, ",
    "paragraphs, lists, blockquotes, indented code, emphasis, links, images, ",
    "angle-bracket autolinks, backslash escapes, and raw HTML passthrough, with the ",
    "Sundown extras (tables, fenced code, bare-URL autolinking, strikethrough, ",
    "superscript) deliberately off. Output is plain HTML, not XHTML: hr and br render ",
    "without the self-closing slash. It compiles both natively and to WebAssembly, so ",
    "the same call renders on the server and in the browser; this docs site renders ",
    "its own prose through it at build time.",
  }),

  examples = {

    {
      title = "to_html: render a document",
      desc = "The whole API is one function: Markdown string in, HTML string out. Block elements are separated by blank lines in the output and each ends with a newline.",
      code = [[
local md = require("santoku.markdown")
local html = md.to_html([=[
# Title
Some text

## Subtitle
1. Hello
2. World
]=])
print(html)
return #html
]],
    },

    {
      title = "Headings, three ways",
      desc = "ATX hashes give h1 through h6, and the space after the hashes is optional because Sundown's space_headers extension is off. Trailing hashes and spaces are stripped. Setext underlines with equals or dashes give h1 and h2.",
      code = [[
local md = require("santoku.markdown")
print(md.to_html("# one\n## two\n### three\n###### six"))
print(md.to_html("#no space needed"))
print(md.to_html("## closed style ##"))
return md.to_html("Top\n===\n\nSection\n-------")
]],
    },

    {
      title = "Inline markup",
      desc = "Emphasis, strong, code spans, and links inside a paragraph.",
      code = [[
local md = require("santoku.markdown")
print(md.to_html("*emphasis*, **strong**, and `code spans`"))
print(md.to_html("See [santoku](https://github.com/birchpointswe/lua-santoku)."))
return md.to_html("plain text")
]],
    },

    {
      title = "Emphasis in detail",
      desc = "Asterisks and underscores are interchangeable, tripling nests strong and em, and because the no_intra_emphasis extension is off, underscores inside words emphasize too: snake_case identifiers need escaping or code spans.",
      code = [[
local md = require("santoku.markdown")
print(md.to_html("*star* _underscore_ **bold** __also bold__"))
print(md.to_html("***both at once***"))
print(md.to_html("a snake_case_name gets chewed up"))
return md.to_html("`snake_case_name` survives in a code span")
]],
    },

    {
      title = "Code spans",
      desc = "Single backticks open a span, double backticks let a literal backtick appear inside, and surrounding spaces next to the delimiters are trimmed.",
      code = [[
local md = require("santoku.markdown")
print(md.to_html("call `md.to_html(s)` to render"))
print(md.to_html("use `` ` `` for a literal backtick"))
return md.to_html("`a < b` escapes inside spans too")
]],
    },

    {
      title = "Block elements",
      desc = "Blockquotes, four-space indented code blocks, and horizontal rules. The rule renders as a bare hr tag because the XHTML flag is off.",
      code = [[
local md = require("santoku.markdown")
print(md.to_html("> Markdown in, HTML out."))
print(md.to_html("    local x = 1\n    print(x)"))
return md.to_html("---")
]],
    },

    {
      title = "Lists and nesting",
      desc = "Dashes, pluses, and asterisks all open unordered lists, four extra spaces of indent nest a sublist, and ordered list source numbers are discarded: the renderer emits a plain ol and the browser numbers it.",
      code = [[
local md = require("santoku.markdown")
print(md.to_html("- dash\n+ plus\n* star"))
print(md.to_html("- fruits\n    - apple\n    - pear\n- roots\n    - beet"))
return md.to_html("3. renders first\n7. renders second\n1. renders third")
]],
    },

    {
      title = "Tight versus loose lists",
      desc = "Items packed together render bare text inside each li; blank lines between items switch the list to block mode and wrap every item's text in paragraph tags.",
      code = [[
local md = require("santoku.markdown")
print(md.to_html("- alpha\n- beta"))
return md.to_html("- alpha\n\n- beta")
]],
    },

    {
      title = "Blank lines matter",
      desc = "Without the lax_spacing extension, a list glued to a paragraph stays paragraph text: the blank line is what opens the list.",
      code = [[
local md = require("santoku.markdown")
local glued = md.to_html("Shopping:\n- milk\n- eggs")
print(glued)
return md.to_html("Shopping:\n\n- milk\n- eggs")
]],
    },

    {
      title = "Hard line breaks",
      desc = "A single newline inside a paragraph is a soft wrap and renders as whitespace; two trailing spaces before the newline force a br tag (no self-closing slash, XHTML is off).",
      code = [[
local md = require("santoku.markdown")
print(md.to_html("soft wrap\nsame paragraph"))
return md.to_html("hard break  \nnew line, same paragraph")
]],
    },

    {
      title = "Links: inline, reference, implicit",
      desc = "Inline links take an optional quoted title. Reference definitions live on their own line anywhere in the document, and an empty second bracket reuses the link text as the reference name.",
      code = [[
local md = require("santoku.markdown")
print(md.to_html('[repo](https://github.com/birchpointswe/lua-santoku-markdown "the rock")'))
print(md.to_html("read [the docs][site] first\n\n[site]: https://example.com"))
return md.to_html("[example][]\n\n[example]: https://example.com")
]],
    },

    {
      title = "Images",
      desc = "Image syntax is link syntax with a leading bang: alt text, href, optional title. The src and title are attribute-escaped and the tag closes without a slash.",
      code = [[
local md = require("santoku.markdown")
print(md.to_html('![logo](logo.png "Santoku")'))
return md.to_html("![plain alt](icons/knife.svg)")
]],
    },

    {
      title = "Autolinks need angle brackets",
      desc = "Wrapping a URL or email in angle brackets links it, and emails gain a mailto: prefix. Bare URLs stay plain text because the autolink extension is off.",
      code = [[
local md = require("santoku.markdown")
print(md.to_html("go to <https://example.com> now"))
print(md.to_html("mail <user@example.com> about it"))
return md.to_html("bare https://example.com stays text")
]],
    },

    {
      title = "Backslash escapes",
      desc = "A backslash before any of \\ ` * _ { } [ ] ( ) # + - . ! : | & < > ^ ~ renders the character literally; before anything else the backslash itself stays in the output.",
      code = [[
local md = require("santoku.markdown")
print(md.to_html("\\*not emphasized\\* but *emphasized*"))
print(md.to_html("\\# not a heading"))
return md.to_html("\\q is not in the escape set")
]],
    },

    {
      title = "Entities and ampersands",
      desc = "Anything matching an entity shape (ampersand, optional hash, alphanumerics, semicolon) passes through untouched; a lone ampersand is escaped to amp.",
      code = [[
local md = require("santoku.markdown")
print(md.to_html("&amp; and &#169; pass through"))
print(md.to_html("AT&T gets its ampersand escaped"))
return md.to_html("&notanentity because no semicolon")
]],
    },

    {
      title = "HTML escaping",
      desc = "Special characters in plain text and code spans are entity-escaped: angle brackets, ampersands, double quotes, and single quotes.",
      code = [[
local md = require("santoku.markdown")
print(md.to_html("a < b & c"))
print(md.to_html("`5 > 4` is true"))
print(md.to_html("it's got 'singles'"))
return md.to_html('say "hello"')
]],
    },

    {
      title = "Raw HTML passes through",
      desc = "With all render flags at zero, inline tags and block-level HTML are emitted verbatim, not escaped. That is a feature for trusted prose and a reason to sanitize or pre-escape untrusted input before rendering.",
      code = [[
local md = require("santoku.markdown")
print(md.to_html("inline <span class=\"hl\">spans</span> survive"))
return md.to_html("<div class=\"note\">\nA whole block, kept <em>as is</em>.\n</div>")
]],
    },

    {
      title = "What the extensions being off looks like",
      desc = "Fenced code, pipe tables, and strikethrough are Sundown extensions this binding does not enable, so their syntax renders as ordinary text. Indented code blocks are the supported form.",
      code = [[
local md = require("santoku.markdown")
print(md.to_html("```\nnot a code block\n```"))
print(md.to_html("| a | b |\n|---|---|\n| 1 | 2 |"))
return md.to_html("~~not struck~~")
]],
    },

    {
      title = "Argument handling and edge cases",
      desc = "The binding takes exactly one argument through luaL_checklstring: extra arguments are dropped, numbers coerce through Lua's standard string conversion, non-strings like nil raise, and empty input renders to the empty string.",
      code = [[
local md = require("santoku.markdown")
print(md.to_html("first", "ignored", "also ignored"))
print(md.to_html(42))
print("empty in, empty out:", "[" .. md.to_html("") .. "]")
local ok, err = pcall(md.to_html, nil)
print(ok, err)
return ok
]],
    },

    {
      title = "Composing with santoku.string",
      desc = "Interpolate a Markdown template with the base library, then render it.",
      code = [[
local md = require("santoku.markdown")
local str = require("santoku.string")
local doc = str.interp("# %name\n\nThe %name rock wraps %impl and returns HTML.", {
  name = "santoku-markdown",
  impl = "Sundown",
})
print(doc)
return md.to_html(doc)
]],
    },

    {
      title = "Data to page with santoku.mustache",
      desc = "The two renderers chain naturally: mustache turns a table into Markdown source, to_html turns that into markup. This is the shape of a changelog or notes pipeline.",
      code = [[
local md = require("santoku.markdown")
local mch = require("santoku.mustache")
local tpl = mch("# {{title}}\n\n{{#items}}- {{.}}\n{{/items}}")
local doc = tpl({
  title = "Release notes",
  items = { "faster parse", "smaller wasm", "same one-function API" },
})
print(doc)
return md.to_html(doc)
]],
    },

  },

}
