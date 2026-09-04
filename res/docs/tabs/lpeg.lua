return {

  intro = table.concat({
    "santoku-lpeg is the parsing and text transformation layer of the framework, built in ",
    "three layers. At the bottom sits a vendored LPeg 1.1.0 engine, shipped inside the rock ",
    "as the C module santoku.re.core (renamed so it can coexist with an external lpeg rock). ",
    "On top of it, santoku.re is the re grammar frontend: PEG pattern strings with match, ",
    "find, gsub, plus a second, state-free parallel tier (check, tags, pmatch) that accepts ",
    "only structure-reading patterns. The top layer is santoku.lpeg: scanning helpers that ",
    "stream named fields out of JSON lines, parse CSV, and scan, extract, rewrite, and ",
    "minify HTML, plus santoku.lpeg.strip, a subsequence-safe comment stripper for a dozen ",
    "languages. toku web builds minify shipped HTML with ",
    "minify_html and transform_inline, the component framework splits fragments with ",
    "component_parts, html_text and json_fields reduce documents to indexable text, ",
    "and strip backs comment policy enforcement in commit hooks. The tour ",
    "below runs basics to advanced: single patterns, then grammars, then the scanners, ",
    "then the stripper and its safety guarantees.",
  }),

  examples = {

    {
      title = "re.match: literals and classes",
      desc = table.concat({
        "The re frontend compiles PEG pattern strings. re.match takes the subject first, ",
        "then the pattern. Without captures it returns the position one past the match; ",
        "{...} adds a value capture; on failure it returns nil. Character classes are the ",
        "familiar %a %d %s %w set, and 'quoted' text matches literally.",
      }),
      code = [[
local re = require("santoku.re")
print("literal:", re.match("hello", "'hello'"))
print("capture:", re.match("hello world", "{%a+}"))
print("after digits:", re.match("123abc", "%d+ {%a+}"))
print("no match:", re.match("hello", "%d+"))
return re.match("hello world", "{%a+}")
]],
    },

    {
      title = "re predicates and bounded repetition",
      desc = table.concat({
        "PEG predicates consume nothing: &p succeeds only if p matches here, !p succeeds ",
        "only if it does not, and the idiom (!stop .)* consumes up to a delimiter without ",
        "eating it. Bracket classes [0-9a-f] and complements [^aeiou] compile to set ",
        "patterns. Repetition is bounded three ways, and the counts differ from LPeg ",
        "combinators: ^n compiles to exactly n concatenated copies, ^+n means at least n, ",
        "^-n means at most n.",
      }),
      code = [[
local re = require("santoku.re")
print("hex:", re.match("c0ffee", "{[0-9a-f]+}"))
print("complement:", re.match("xyz", "{[^aeiou]+}"))
print("exactly 3:", re.match("aaaa", "%a^3 {}"))
print("at least 2:", re.match("aaaa", "%a^+2 {}"))
print("at most 2:", re.match("aaaa", "%a^-2 {}"))
print("lookahead:", re.match("foobar", "&'foo' {%a+}"))
print("negation:", re.match("bar", "!'foo' {%a+}"))
print("guarded:", re.match("foo", "!'foo' %a+"))
print("until comma:", re.match("a b,c", "{ (!',' .)* }"))
return re.match("a b,c", "{ (!',' .)* }")
]],
    },

    {
      title = "re captures: position, table, named, substitution",
      desc = table.concat({
        "The capture zoo: {} captures the current position, {| ... |} collects into a table, ",
        "{:name: ... :} names an entry inside that table, and {~ ... ~} is a substitution ",
        "capture that rewrites matched text in place. This fork keeps only literal string ",
        "and number transforms (patt -> 'x'); function transforms and user definition ",
        "tables were dropped, so %custom raises and -> f is a syntax error.",
      }),
      code = [[
local re = require("santoku.re")
print("pos:", re.match("abc", ". . {}"))
local d = re.match("2026-08-25",
  "{| {:y: %d+ :} '-' {:m: %d+ :} '-' {:d: %d+ :} |}")
print("date:", d.y, d.m, d.d)
print("subst:", re.match("a b c", "{~ (%s -> '_' / .)* ~}"))
print("transform:", re.match("x", "'x' -> 'Y'"))
return d.y
]],
    },

    {
      title = "re.find and re.gsub",
      desc = table.concat({
        "re.find searches for the pattern anywhere in the subject and returns the start ",
        "and inclusive end positions. re.gsub replaces every match; a string replacement ",
        "can reference captures with %1. All three entry points memoize their compiled ",
        "patterns, so repeated calls with the same pattern string are cheap.",
      }),
      code = [[
local re = require("santoku.re")
print("find:", re.find("hello 123 world", "%d+"))
print("gsub:", re.gsub("hello world", "%s+", "_"))
print("gsub caps:", re.gsub("ab cd", "{%a+}", "<%1>"))
return re.gsub("hello world", "%s+", "_")
]],
    },

    {
      title = "re back-references",
      desc = table.concat({
        "=name re-matches the text captured by a prior named group, implemented as a ",
        "match-time capture over a back-reference. Useful for doubled words, matching ",
        "delimiters, and heredoc-style constructs. Because it is a match-time capture it ",
        "runs only on the serial tier; re.check rejects it for the parallel tier.",
      }),
      code = [[
local re = require("santoku.re")
print("doubled:", re.match("boo boo", "{:w: %a+ :} ' ' =w"))
print("differs:", re.match("boo baa", "{:w: %a+ :} ' ' =w"))
return re.match("boo boo", "{:w: %a+ :} ' ' =w")
]],
    },

    {
      title = "re grammars: recursion",
      desc = table.concat({
        "A pattern of the form name <- expression defines a grammar rule, and rules can ",
        "refer to themselves. This is the step regexes cannot take: balanced, nested ",
        "structure. One line matches arbitrarily nested parentheses.",
      }),
      code = [[
local re = require("santoku.re")
local balanced = "b <- '(' b* ')'"
print("nested:", re.match("(()())", balanced))
print("deep:", re.match("(((())))", balanced))
print("unbalanced:", re.match("((", balanced))
return re.match("(()())", balanced)
]],
    },

    {
      title = "re grammars: composing a parser",
      desc = table.concat({
        "Multiple rules compose into a real parser. Here a two-rule grammar parses a ",
        "key=value list straight into nested Lua tables: the outer rule collects pairs ",
        "into an array, the inner rule names each key and value. This is the same shape ",
        "santoku.lpeg uses internally to skip whole JSON values.",
      }),
      code = [[
local re = require("santoku.re")
local p = [=[
  pairs <- {| pair (',' pair)* |}
  pair <- {| {:key: %a+ :} '=' {:val: %d+ :} |}
]=]
local t = re.match("a=1,b=22,c=3", p)
print("count:", #t)
print("first:", t[1].key, t[1].val)
print("second:", t[2].key, t[2].val)
return t[3].key .. "=" .. t[3].val
]],
    },

    {
      title = "re grammars: precedence by layering",
      desc = table.concat({
        "The classic PEG precedence technique: one rule per precedence level, each level ",
        "defined as a list of the next tighter one. sum is prods joined by +, prod is ",
        "nums joined by *, so multiplication groups before addition with no precedence ",
        "table and no separate AST pass. The capture tables mirror the grouping directly: ",
        "1+2*3+4 parses to three terms, and only the middle term holds two factors.",
      }),
      code = [[
local re = require("santoku.re")
local p = [=[
  sum <- {| prod ('+' prod)* |}
  prod <- {| num ('*' num)* |}
  num <- {%d+}
]=]
local t = re.match("1+2*3+4", p)
print("terms:", #t)
print("middle term factors:", t[2][1], t[2][2])
print("outer terms:", t[1][1], t[3][1])
return #t
]],
    },

    {
      title = "re.check, re.tags, re.pmatch: the parallel tier",
      desc = table.concat({
        "Beyond the serial matcher, santoku.re compiles patterns to state-free programs ",
        "that can run without a Lua state, for parallel scanning from C. That tier reads ",
        "structure only: position and named-group captures pass, value and match-time ",
        "captures are rejected. re.check reports acceptance, re.tags returns dense ids ",
        "for named groups in order of first appearance, and re.pmatch runs the state-free ",
        "matcher, returning the match's inclusive end offset and a capture count. Note the ",
        "argument order: pmatch takes (pattern, subject, init), match takes (subject, ",
        "pattern, init).",
      }),
      code = [[
local re = require("santoku.re")
print("plain:", re.check("%a+"))
print("named group:", re.check("{:w: %a+ :}"))
print("value cap:", re.check("{%a+}"))
print("backref:", re.check("{:g: %a :} =g"))
local t = re.tags("{:caps: %u+ :} / {:num: %d+ :}")
print("tags:", t.caps, t.num)
print("pmatch:", re.pmatch("%a+", "hello123"))
print("pmatch init:", re.pmatch("%d+", "ab12", 3))
return re.pmatch("%a+", "hello123")
]],
    },

    {
      title = "santoku.re.core: raw combinators",
      desc = table.concat({
        "The vendored engine exports the full LPeg combinator API: P, S, R, B, V, the ",
        "capture family C, Cc, Cp, Cs, Ct, Cg, Cb, Cmt, Carg, Cf, plus match, locale, ",
        "type, utfR, and setmaxstack. Everything santoku.lpeg does (JSON scanning, HTML ",
        "tokenizing, CSV) is built from these. Here the combinators build a recursive ",
        "grammar for nested word lists, the programmatic twin of the re string syntax.",
      }),
      code = [[
local lpeg = require("santoku.re.core")
local P, S, R, C, Ct, V =
  lpeg.P, lpeg.S, lpeg.R, lpeg.C, lpeg.Ct, lpeg.V
local ws = S(" \t") ^ 0
local word = C(R("az") ^ 1)
local list = P({ "list",
  list = P("(") * ws *
    Ct(((word + V("list")) * ws) ^ 0) * P(")"),
})
local t = lpeg.match(list, "(ab (cd ef) gh)")
print(t[1], t[2][1], t[2][2], t[3])
return t[1]
]],
    },

    {
      title = "lp.json_fields",
      desc = table.concat({
        "Stream named top-level fields out of a JSON line as byte ranges, without building ",
        "a document tree. String values yield their inner range (quotes excluded), arrays ",
        "yield each string element, nested objects are skipped entirely, and empty strings ",
        "are not yielded. This is how search pipelines pull indexable text out of JSONL ",
        "without paying for a full JSON parse per line.",
      }),
      code = [[
local lp = require("santoku.lpeg")
local line =
  '{"title":"Dune","tags":["scifi","classic"],"meta":{"title":"nope"},"year":1965}'
local out = {}
for s, e in lp.json_fields(line, { "title", "tags" }) do
  out[#out + 1] = line:sub(s, e)
  print(line:sub(s, e))
end
return table.concat(out, ", ")
]],
    },

    {
      title = "lp.csv",
      desc = table.concat({
        "A small CSV parser: quoted fields may contain commas and newlines, doubled ",
        "quotes unescape to one, CRLF and lone LF both delimit records, a UTF-8 BOM is ",
        "stripped, and fully blank records are dropped. Returns an array of row arrays. ",
        "Used for admin data imports where a spreadsheet export is the source of truth.",
      }),
      code = [[
local lp = require("santoku.lpeg")
local text = table.concat({
  'name,qty\r\n',
  '"Smith, J.",2\r\n',
  '"say ""hi""",3\r\n',
})
local rows = lp.csv(text)
print("rows:", #rows)
print("quoted comma:", rows[2][1], rows[2][2])
print("escaped quote:", rows[3][1])
return rows[2][1]
]],
    },

    {
      title = "lp.html_text",
      desc = table.concat({
        "Iterate the visible text runs of an HTML fragment, dropping tags, comments, and ",
        "the entire contents of script and style. Block-level elements flush the current ",
        "run, so structure boundaries become run boundaries. This is the first stage of ",
        "reducing stored HTML descriptions to tokenizable text for search indexing.",
      }),
      code = [[
local lp = require("santoku.lpeg")
local html =
  '<ul><li>alpha</li><li>beta</li></ul><script>track()</script><p>done</p>'
local n = 0
for text in lp.html_text(html) do
  n = n + 1
  print(n, text)
end
return n
]],
    },

    {
      title = "lp.html_extract and lp.html_inject",
      desc = table.concat({
        "The central round trip. html_extract strips tags to plain text and returns tag ",
        "records carrying the element name, attribute table, and the 1-based inclusive ",
        "s, e range each element covers in the stripped text. Edit the records (here a ",
        "text override canonicalizes the author name), then html_inject rebuilds markup ",
        "around the text. Positions index the stripped text, not the original HTML.",
      }),
      code = [[
local lp = require("santoku.lpeg")
local html = 'hello <span class="author">J. Smith</span> world'
local text, tags = lp.html_extract(html)
print("text:", text)
print("tag:", tags[1].name, tags[1].attrs.class)
print("covers:", text:sub(tags[1].s, tags[1].e))
tags[1].text = "John Smith"
return lp.html_inject(text, tags)
]],
    },

    {
      title = "lp.html_inject from scratch",
      desc = table.concat({
        "Tag records do not have to come from html_extract: build them directly to wrap ",
        "ranges of plain text in markup. The third argument fixes attribute emission ",
        "order, making output deterministic (attribute tables otherwise iterate in hash ",
        "order); unlisted attributes follow the ordered ones.",
      }),
      code = [[
local lp = require("santoku.lpeg")
local text = "hello Germany world"
local tags = { {
  name = "span", s = 7, e = 13,
  attrs = { class = "country", id = "276" },
} }
return lp.html_inject(text, tags, { "class", "id" })
]],
    },

    {
      title = "lp.html_tags",
      desc = table.concat({
        "Iterate elements with their attributes and byte positions in the original HTML: ",
        "each step yields name, attrs, open_s, open_e, close_s, close_e, where the open ",
        "range covers the opening tag and the close range covers the closing tag. Unlike ",
        "html_extract's s and e, these positions index the raw input.",
      }),
      code = [[
local lp = require("santoku.lpeg")
local html = '<b>bold</b> and <i x="1">italic</i>'
for name, attrs, os_, oe, cs, ce in lp.html_tags(html) do
  print(name, attrs.x, html:sub(os_, oe), html:sub(cs, ce))
end
return html
]],
    },

    {
      title = "lp.html_match_tags and lp.html_spans",
      desc = table.concat({
        "The bridge from match vectors to markup. Given parallel id, start, and end ",
        "vectors (0-based offsets, anything with :size() and :get(i), which santoku.ivec ",
        "satisfies), html_match_tags builds span tag records with class names mapped ",
        "through a names table and an optional prefix, ready for html_inject. This is how ",
        "search hit highlighting and entity annotation render: the matcher emits offsets, ",
        "this turns them into spans. html_spans goes the other way, converting tag records ",
        "to a santoku.pvec of (s-1, e) pairs for span algebra.",
      }),
      code = [[
local lp = require("santoku.lpeg")
local ivec = require("santoku.ivec")
local text = "Ada met Rome"
local ids = ivec.create({ 1, 2 })
local starts = ivec.create({ 0, 8 })
local ends = ivec.create({ 3, 12 })
local tags = lp.html_match_tags(ids, starts, ends,
  { [1] = "per", [2] = "loc" }, "hl-")
print("tags:", #tags, tags[1].attrs.class, tags[2].attrs.class)
print("spans:", lp.html_spans(tags):size())
return lp.html_inject(text, tags)
]],
    },

    {
      title = "lp.minify_html",
      desc = table.concat({
        "Collapse whitespace runs and drop comments while preserving pre, textarea, ",
        "script, and style bodies byte for byte. This runs over every HTML asset in toku ",
        "web release builds, so the shipped markup is exactly what this function returns.",
      }),
      code = [[
local lp = require("santoku.lpeg")
local html = table.concat({
  "<!-- build note -->\n",
  "<div>\n  hello   world\n</div>\n",
  "<pre>  keep   this  </pre>",
})
return lp.minify_html(html)
]],
    },

    {
      title = "lp.transform_inline",
      desc = table.concat({
        "Rewrite inline script and style bodies through js and css transform functions, ",
        "leaving scripts with a src attribute untouched. In release builds the transforms ",
        "are the JS and CSS minifiers; here string.upper makes the rewriting visible.",
      }),
      code = [[
local lp = require("santoku.lpeg")
local html = table.concat({
  '<style>.a { color: red }</style>',
  '<script src="x.js">keep</script>',
  '<script>var x = 1;</script>',
})
return lp.transform_inline(html, {
  js = string.upper,
  css = string.upper,
})
]],
    },

    {
      title = "lp.component_parts",
      desc = table.concat({
        "Split an HTML component fragment into its pieces: external deps (script src ",
        "attributes), the style body, the inline init script, an optional destroy script ",
        "(script type=\"destroy\"), and the remaining body markup. This is the loader ",
        "behind the web component framework: one file per component, one call to take ",
        "it apart.",
      }),
      code = [[
local lp = require("santoku.lpeg")
local parts = lp.component_parts(table.concat({
  '<style>.card { color: red }</style>\n',
  '<div class="card">hi</div>\n',
  '<script src="lib.js"></script>\n',
  '<script>setup()</script>',
}))
print("dep:", parts.deps[1])
print("style:", parts.style)
print("init:", parts.init)
return parts.body
]],
    },

    {
      title = "santoku.lpeg.strip: Lua",
      desc = table.concat({
        "The comment stripper's core guarantee: output is always a byte-subsequence of ",
        "the input, so it can only ever delete comment bytes, never mutate code; on any ",
        "ambiguity it returns the input unchanged with bailed true. Comment markers ",
        "inside short and leveled long strings survive, long comments are removed while ",
        "keeping token separation, whole-line comments vanish without leaving blanks, and ",
        "functional directives like luacheck: and luacov: are kept.",
      }),
      code = [=[
local strip = require("santoku.lpeg.strip")
local src = table.concat({
  'local x = 1 -- setup\n',
  '-- whole line\n',
  'local s = "-- not a comment"\n',
  'local l = [==[ ]] -- inside ]==]\n',
  'a --[[ short block ]] b\n',
  'return x -- luacheck: ignore\n',
})
local out, bailed = strip.strip_lua(src)
print("bailed:", bailed)
return out
]=],
    },

    {
      title = "santoku.lpeg.strip: one stripper per language",
      desc = table.concat({
        "Each language gets a grammar that knows its own hazards. C handles both comment ",
        "styles and keeps NOLINT-style directives. JS distinguishes regex literals from ",
        "division and leaves backtick templates and @ts- directives alone. CSS strips ",
        "only block comments outside strings, and nginx conf strips hash comments but ",
        "not hashes inside quoted values. Also exported: strip_sh, strip_hcl, ",
        "strip_python, strip_yaml, strip_dockerfile, strip_unit, and strip_html.",
      }),
      code = [[
local strip = require("santoku.lpeg.strip")
print((strip.strip_c('int x; // note\nint y; /* z */\n')))
print((strip.strip_js("var r = /ab\\/c/g;\n")))
print((strip.strip_js("var x = a / b // gone\n")))
print((strip.strip_js("x; // @ts-ignore\n")))
print((strip.strip_css(".a { color: red } /* c */\n")))
print((strip.strip_conf('add_header X "# not a comment";\n')))
return (strip.strip_html("<div>a<!-- c -->b</div>"))
]],
    },

    {
      title = "strip guarantees: opaque bodies, bails, license heads",
      desc = table.concat({
        "Three safety rules make strip fit for a commit hook. First, opaque regions ",
        "(shell and HCL heredocs, Python docstrings, YAML block scalars, JS template ",
        "literals) are never scanned for comment markers, so a hash inside a heredoc ",
        "body survives while the comment after the terminator goes. Second, anything ",
        "unprovable bails: an unterminated heredoc, a block comment spanning a <% %> ",
        "template block, output that stops being a byte-subsequence, all return the ",
        "input unchanged with bailed true. Third, a leading license head (a comment run ",
        "containing Copyright, SPDX-License-Identifier, or a permission notice) passes ",
        "through untouched before stripping starts, and losing a notice anywhere else ",
        "bails rather than deleting it.",
      }),
      code = [[
local strip = require("santoku.lpeg.strip")
local sh = table.concat({
  "#!/bin/sh\n",
  "cat <<'CONF'\n",
  "# keep: heredoc body\n",
  "CONF\n",
  "echo done # gone\n",
})
print((strip.strip_sh(sh)))
local _, bailed = strip.strip_sh("cat <<EOF\n# keep\n")
print("unterminated heredoc bails:", bailed)
local tsrc = "a /* c <% x() %> d */ b\n"
local tout, tbailed = strip.strip_template(tsrc, "c")
print("comment spanning a block bails:", tbailed, tout == tsrc)
local lic = "-- Copyright 2026 Example Co\n\nlocal x = 1 -- gone\n"
return (strip.strip(lic, "mod.lua"))
]],
    },

    {
      title = "strip dispatch, templates, and coverage",
      desc = table.concat({
        "strip.strip(src, filename) picks the language from the extension, name, or ",
        "shebang, passes binary and data formats through untouched, and returns out plus ",
        "bailed. After stripping, runs of blank lines outside protected regions (long ",
        "strings, heredocs, block scalars, template blocks) collapse to one. A .tk.<ext> ",
        "template file is handled twice over: literal text is stripped with the output ",
        "language's grammar and each <% ... %> block's Lua is stripped, with the ",
        "delimiters preserved. strip.coverage classifies a file as checked, ignored, or ",
        "unknown, which is what a commit hook needs to decide whether a file even ",
        "participates in comment policy.",
      }),
      code = [[
local strip = require("santoku.lpeg.strip")
print(strip.strip("local x = 1 -- note\nreturn x\n", "mod.lua"))
print(strip.strip("<% foo() -- done %>", "mod.tk.lua"))
print(strip.strip("a = 1\n\n\n\nb = 2\n", "x.lua"))
print(strip.strip_template("a -- gone\n<% z() %>\n", "lua"))
print("lua:", strip.coverage("x = 1\n", "a.lua"))
print("png:", strip.coverage("", "logo.png"))
print("xyz:", strip.coverage("", "notes.xyz"))
return (strip.strip("local x = 1 -- note\nreturn x\n", "mod.lua"))
]],
    },

  },

}
