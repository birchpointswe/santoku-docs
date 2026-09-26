return {

  intro = table.concat({
    "santoku-learn is the machine learning toolkit of the framework: C modules built ",
    "on santoku-matrix types (csr sparse features, mtx dense codes, spans) covering ",
    "n-gram tokenization, Aho-Corasick gazetteer matching, booleanization, spectral ",
    "Nystrom embeddings, ridge regression, and calibrated decisions, with ",
    "optimize.krr tying the whole modelling path together. Binary-code retrieval ",
    "uses santoku-matrix directly: bm25 weighting, spectral codes, mtx:itq, and ",
    "Hamming top-k. The front half of ",
    "that pipeline runs live on this page: tokenizer, aho, booleanizer, and decide ",
    "ship in the browser bundle as WASM builds, so every ",
    "example up to the in-browser classifier is runnable right here. The back half ",
    "(spectral, ridge, optimize, and the file-fed dataset, util, and bundle ",
    "helpers) is shown for reading: it depends on BLAS/LAPACK or on training corpora ",
    "read from disk. The full pipelines those examples distill live ",
    "in the repo's regression suites (eurlex, newsgroups, imdb, mnist, housing, and ",
    "the CoNLL pair): ",
    "https://github.com/birchpointswe/lua-santoku-learn/tree/master/test/spec/santoku/learn/regress",
  }),

  examples = {

    {
      title = "santoku.learn.tokenizer (raw)",
      desc = table.concat({
        "One-shot n-gram hashing: text straight to sparse count features, no vocabulary ",
        "to fit, stable column ids for the same n-gram across documents.",
      }),
      code = [[
local tokenizer = require("santoku.learn.tokenizer")
local off, tok, val = tokenizer.tokenize_raw({
  texts = { "hello", "hello world" },
  n_samples = 2,
  ngram_min = 3,
  ngram_max = 3,
  normalize = true,
})
print("docs:", off:size() - 1)
print("ngrams in doc 1:", off:get(1) - off:get(0))
print("ngrams in doc 2:", off:get(2) - off:get(1))
print("total ngram count:", val:sum())
local _, tok2 = tokenizer.tokenize_raw({
  texts = { "abc", "abc" }, n_samples = 2, ngram_min = 3, ngram_max = 3,
})
print("shared column id:", tok2:get(0) == tok2:get(1))
local _, tok3, val3 = tokenizer.tokenize_raw({
  texts = { "ababab" }, n_samples = 1, ngram_min = 2, ngram_max = 2,
})
print("distinct bigrams:", tok3:size())
print("most frequent count:", val3:max())
return tok:size()
]],
    },

    {
      title = "santoku.learn.tokenizer (fitted)",
      desc = table.concat({
        "Fit a vocabulary on training text, then tokenize new text against the frozen ",
        "vocabulary: unseen n-grams do not grow it, so train and serve agree on columns.",
      }),
      code = [[
local tokenizer = require("santoku.learn.tokenizer")
local tok = tokenizer.create({ ngram_min = 3, ngram_max = 3, normalize = true })
local X = tok:fit({ texts = { "hello", "world" } })
print("training rows:", (X:shape()))
print("nnz:", X:nnz())
print("vocab size:", tok:n_tokens())
local X2 = tok:tokenize({ texts = { "brand new text" } })
print("new rows:", (X2:shape()))
print("vocab still:", tok:n_tokens())
return tok:n_tokens()
]],
    },

    {
      title = "tokenizer.extract: regex to spans",
      desc = table.concat({
        "Run a compiled regex program over a batch of texts and get token spans back as ",
        "three ivecs (per-doc offsets, starts, ends), ready to wrap in a spans set. A pattern ",
        "that fails to match cleanly raises \"extract: pattern match failed (re status N)\" ",
        "instead of dropping tokens.",
      }),
      code = [[
local tokenizer = require("santoku.learn.tokenizer")
local re = require("santoku.re")
local spans = require("santoku.spans")
local arr = require("santoku.array")
local texts = { "The quick brown fox", "jumps over 42 dogs" }
local prog = re.prog("[A-Za-z0-9]+")
local off, s, e = tokenizer.extract({ n = 2, texts = texts, pattern = prog })
for d = 1, 2 do
  local words = {}
  for j = off:get(d - 1), off:get(d) - 1 do
    words[#words + 1] = texts[d]:sub(s:get(j) + 1, e:get(j))
  end
  print("doc " .. d .. ":", arr.concat(words, "|"))
end
local T = spans.create({ offsets = off, s = s, e = e })
return T:col("s"):size()
]],
    },

    {
      title = "word n-grams over extracted tokens",
      desc = table.concat({
        "Feed extracted word spans into a flat-mode tokenizer: n-grams range over the ",
        "word sequence instead of raw bytes, and a frozen tokenize reproduces the fit ",
        "exactly.",
      }),
      code = [[
local tokenizer = require("santoku.learn.tokenizer")
local re = require("santoku.re")
local spans = require("santoku.spans")
local texts = { "the quick brown fox", "the lazy dog sleeps" }
local prog = re.prog("[A-Za-z0-9]+")
local woff, ws, we = tokenizer.extract({ n = 2, texts = texts, pattern = prog })
local T = spans.create({ offsets = woff, s = ws, e = we })
local w = tokenizer.create({ ngram_min = 1, ngram_max = 2, mode = "flat", terminals = true })
local X = w:fit({ texts = texts, tokens = T })
print("rows:", (X:shape()))
print("word ngram vocab:", w:n_tokens())
local Y = w:tokenize({ texts = texts, tokens = T })
print("frozen equals fit:", X:eq(Y))
return w:n_tokens()
]],
    },

    {
      title = "tokenizer.normalize: fold text before word spans",
      desc = table.concat({
        "tokenizer.normalize(texts) returns new strings, lowercased, with accents folded and ",
        "whitespace collapsed. Word spans index into the text they were extracted from, so ",
        "normalize first, extract from the normalized strings, and fit on those same strings. ",
        "Accented and plain spellings then share columns.",
      }),
      code = [[
local tokenizer = require("santoku.learn.tokenizer")
local re = require("santoku.re")
local spans = require("santoku.spans")
local norm = tokenizer.normalize({ "Café  NOIR", "cafe noir" })
print("normalized:", norm[1], norm[2])
local prog = re.prog("[A-Za-z0-9]+")
local off, s, e = tokenizer.extract({ n = 2, texts = norm, pattern = prog })
local T = spans.create({ offsets = off, s = s, e = e })
local w = tokenizer.create({ ngram_min = 1, ngram_max = 2, mode = "flat", terminals = true })
w:fit({ texts = norm, tokens = T })
print("word ngram vocab:", w:n_tokens())
return w:n_tokens()
]],
    },

    {
      title = "santoku.learn.aho: matching",
      desc = table.concat({
        "Aho-Corasick multi-pattern matching: one pass over the text finds every ",
        "pattern, returned as a spans set with id, start, and end columns.",
      }),
      code = [[
local aho = require("santoku.learn.aho")
local ac = aho.create({ patterns = { "foo", "bar", "baz" } })
local text = "foo bar baz"
local S = ac:predict({ texts = { text } })
local ids, starts, ends = S:col("id"), S:col("s"), S:col("e")
print("matches:", ids:size())
for i = 0, ids:size() - 1 do
  local s, e = starts:get(i), ends:get(i)
  print(text:sub(s + 1, e), "pattern " .. ids:get(i), s, e)
end
return ids:size()
]],
    },

    {
      title = "aho:tag: formatted output",
      desc = table.concat({
        "tag rewrites matches through a format string: %match and %id for the raw hit, ",
        "%name for the display name, and %hmatch and %hname for HTML-escaped variants, ",
        "safe to inject into markup.",
      }),
      code = [[
local aho = require("santoku.learn.aho")
local ac = aho.create({ patterns = { "foo", "bar" } })
print(ac:tag({ texts = { "foo and bar" }, fmt = "[%match:%id]" })[1])
local cities = aho.create({
  patterns = { "nyc", "la" },
  names = { "New York City", "Los Angeles" },
})
print(cities:tag({
  texts = { "visit nyc or la" },
  fmt = '<span title="%hname">%hmatch</span>',
})[1])
local amp = aho.create({ patterns = { "a&b" } })
print(amp:tag({ texts = { "see a&b here" }, fmt = "<b>%hmatch</b>" })[1])
return true
]],
    },

    {
      title = "aho unicode normalization",
      desc = table.concat({
        "With normalize = true, matching folds case and strips diacritics on both sides ",
        "while spans and tag output preserve the original bytes: cafe finds café, hello ",
        "finds HELLO.",
      }),
      code = [[
local aho = require("santoku.learn.aho")
local ac = aho.create({ patterns = { "cafe" }, normalize = true })
print(ac:tag({ texts = { "at café now" }, fmt = "[%match]" })[1])
local up = aho.create({ patterns = { "hello" }, normalize = true })
print(up:tag({ texts = { "say HELLO there" }, fmt = "[%match]" })[1])
local S = ac:predict({ texts = { "café" } })
print("byte span:", S:col("s"):get(0), S:col("e"):get(0))
return S:col("id"):size()
]],
    },

    {
      title = "aho boundaries: longest match, token alignment",
      desc = table.concat({
        "longest = true keeps only the longest overlapping hit, and a tokens spans set ",
        "restricts matches to token boundaries, so cat stops matching inside ",
        "concatenate.",
      }),
      code = [[
local aho = require("santoku.learn.aho")
local spans = require("santoku.spans")
local ivec = require("santoku.ivec")
local ny = aho.create({ patterns = { "new", "new york" }, names = { "New", "New York" } })
local S = ny:predict({ texts = { "new york city" } })
print("all matches:", S:col("id"):size())
S = ny:predict({ texts = { "new york city" }, longest = true })
print("longest only:", S:col("id"):size())
print(ny:tag({ texts = { "new york city" }, fmt = "[%name]", longest = true })[1])
local cat = aho.create({ patterns = { "cat" } })
local T = spans.create({ offsets = ivec.create({ 0, 3 }),
  s = ivec.create({ 0, 4, 16 }), e = ivec.create({ 3, 15, 19 }) })
local S2 = cat:predict({ texts = { "cat concatenate cat" } })
print("raw matches:", S2:col("id"):size())
S2 = cat:predict({ texts = { "cat concatenate cat" }, tokens = T })
print("token aligned:", S2:col("id"):size())
return S2:col("id"):size()
]],
    },

    {
      title = "aho exclude regions",
      desc = table.concat({
        "Pass byte ranges as a pvec to mask regions out of matching; a second return ",
        "reports per-region whether the automaton recognized the excluded text, which ",
        "is how a suggester skips already-linked entities.",
      }),
      code = [[
local aho = require("santoku.learn.aho")
local pvec = require("santoku.pvec")
local ac = aho.create({ patterns = { "foo", "bar", "baz" } })
local exc = pvec.create()
exc:push(0, 3)
local S = ac:predict({ texts = { "foo bar baz" }, exclude = exc })
print("surviving ids:", S:col("id"):get(0), S:col("id"):get(1))
print(ac:tag({ texts = { "foo bar baz" }, fmt = "[%match]", exclude = exc })[1])
local ac2 = aho.create({ patterns = { "foo" } })
local exc2 = pvec.create()
exc2:push(0, 3)
exc2:push(4, 11)
local S2, hits = ac2:predict({ texts = { "foo hello world" }, exclude = exc2 })
print("matches:", S2:col("id"):size())
print("region recognized:", hits:get(0), hits:get(1))
return hits:size()
]],
    },

    {
      title = "santoku.learn.booleanizer",
      desc = table.concat({
        "Observe mixed categorical and continuous values, finalize, then encode rows ",
        "to bit features (a csr) plus dense features (a matrix); restrict prunes the ",
        "bit vocabulary to a kept id set.",
      }),
      code = [[
local booleanizer = require("santoku.learn.booleanizer")
local ivec = require("santoku.ivec")
local bzr = booleanizer.create()
bzr:observe("title", "The Great Gatsby")
bzr:observe("title", "1984")
bzr:observe("author", "F. Scott Fitzgerald")
bzr:observe("author", "George Orwell")
bzr:observe("year", 1925)
bzr:observe("year", 1949)
bzr:observe("rating", 4.5)
bzr:observe("rating", 4.8)
bzr:finalize()
local n_bits, n_dense = bzr:features()
print("bit features:", n_bits)
print("dense features:", n_dense)
local cols = { "title", "author", "year", "rating" }
local rows = {
  { title = "The Great Gatsby", author = "F. Scott Fitzgerald", year = 1925, rating = 4.5 },
  { title = "1984", author = "George Orwell", year = 1949, rating = 4.8 },
}
local bits, dense = bzr:encode({ samples = rows, cols = cols })
print("bit nnz:", bits:neighbors():size())
print("dense shape:", dense:shape())
local keep = ivec.create(2)
keep:fill_indices()
bzr:restrict(keep)
print("bits after restrict:", (bzr:features()))
return n_bits + n_dense
]],
    },

    {
      title = "santoku.learn.decide (single-label)",
      desc = "The decision layer: a single-label decider picks the argmax class from a flat row-major score vector.",
      code = [[
local decide = require("santoku.learn.decide")
local fvec = require("santoku.fvec")
local scores = fvec.create({
  5, 0, 0,
  0.5, 0, 0.49,
  0, 1, 2,
})
local g = decide.create({ n_labels = 3, single = true })
local pred = g:predict({ scores = scores, n_samples = 3 })
for i = 0, pred:size() - 1 do
  print("sample " .. i .. " label:", pred:get(i))
end
return pred:size()
]],
    },

    {
      title = "decide:score: macro F1 and accuracy",
      desc = table.concat({
        "Score predictions against expected labels held in a csr (csr.from_classes ",
        "builds one from a class ivec); separable scores come back with macro F1 and ",
        "accuracy of 1.",
      }),
      code = [[
local decide = require("santoku.learn.decide")
local fvec = require("santoku.fvec")
local csr = require("santoku.csr")
local ivec = require("santoku.ivec")
local scores = fvec.create({
  6, 0, 0,
  0, 6, 0,
  0, 0, 6,
  6, 0, 0,
})
local E = csr.from_classes(ivec.create({ 0, 1, 2, 0 }), 3)
local g = decide.create({ n_labels = 3, single = true })
local macro, m = g:score({ scores = scores, n_samples = 4, expected = E })
print("macro f1:", macro)
print("accuracy:", m.accuracy)
return m.macro_f1
]],
    },

    {
      title = "decide (multilabel): calibrate a threshold",
      desc = table.concat({
        "Multilabel mode sweeps a score threshold that maximizes micro F1 on ",
        "validation predictions (a csr of label scores per sample), then predict ",
        "counts the accepted labels per row at that threshold.",
      }),
      code = [[
local decide = require("santoku.learn.decide")
local csr = require("santoku.csr")
local ivec = require("santoku.ivec")
local fvec = require("santoku.fvec")
local P = csr.create({
  offsets = ivec.create({ 0, 2, 4 }),
  neighbors = ivec.create({ 0, 2, 1, 0 }),
  values = fvec.create({ 0.9, 0.2, 0.8, 0.1 }),
  n_cols = 3,
})
local E = csr.create({
  offsets = ivec.create({ 0, 1, 2 }),
  neighbors = ivec.create({ 0, 1 }),
  n_cols = 3,
})
local g = decide.create({ n_labels = 3 })
local f1, prec, rec = g:calibrate({ pred = P, expected = E, n_samples = 2 })
print("f1:", f1, "precision:", prec, "recall:", rec)
print("threshold:", g:offset())
local ks = g:predict({ pred = P, n_samples = 2 })
print("accepted per sample:", ks:get(0), ks:get(1))
return f1
]],
    },

    {
      title = "decide (span mode): non-maximum suppression",
      desc = table.concat({
        "Span mode turns scored candidate spans into a non-overlapping labelling: per ",
        "candidate it takes the argmax class and its margin, drops reject-class ",
        "candidates, then a weighted interval DP keeps the best non-overlapping set, ",
        "so New York City beats the overlapping New York and the weak candidate over ",
        "the word in is rejected outright.",
      }),
      code = [[
local decide = require("santoku.learn.decide")
local spans = require("santoku.spans")
local ivec = require("santoku.ivec")
local fvec = require("santoku.fvec")
local text = "Alice met Bob in New York City"
local C = spans.create({
  offsets = ivec.create({ 0, 5 }),
  s = ivec.create({ 0, 10, 14, 17, 17 }),
  e = ivec.create({ 5, 13, 16, 25, 30 }),
})
local scores = fvec.create({
  2.0, 0.1, 0.1,
  1.5, 0.2, 0.2,
  0.1, 0.1, 0.9,
  0.2, 1.2, 0.1,
  0.1, 2.0, 0.1,
})
local g = decide.create({ n_labels = 3, span = true })
local poff, ps, pe, pty = g:predict({ scores = scores, cand = C, n_samples = 1 })
local names = { "person", "location" }
print("kept spans:", ps:size())
for j = 0, ps:size() - 1 do
  print(text:sub(ps:get(j) + 1, pe:get(j)), names[pty:get(j) + 1])
end
return ps:size()
]],
    },

    {
      title = "end to end: a text classifier in the browser",
      desc = table.concat({
        "The full loop on inline data, running live in this page: hash character ",
        "n-grams for training texts and queries in one call (shared column ids), ",
        "L2-normalize each document in plain Lua, score each query by mean cosine ",
        "similarity to every class, and hand the score matrix to a single-label ",
        "decider.",
      }),
      code = [[
local tokenizer = require("santoku.learn.tokenizer")
local decide = require("santoku.learn.decide")
local fvec = require("santoku.fvec")
local num = require("santoku.num")
local train = {
  { text = "the striker scored a late goal", label = 0 },
  { text = "the keeper saved the penalty kick", label = 0 },
  { text = "simmer the garlic in olive oil", label = 1 },
  { text = "whisk the eggs into the batter", label = 1 },
}
local queries = {
  "the striker scored the winning goal",
  "simmer the eggs in the pan",
}
local names = { "sports", "cooking" }
local texts = {}
for i = 1, #train do texts[i] = train[i].text end
for i = 1, #queries do texts[#train + i] = queries[i] end
local off, tok, val = tokenizer.tokenize_raw({
  texts = texts,
  n_samples = #texts,
  ngram_min = 3,
  ngram_max = 4,
  normalize = true,
})
local docs = {}
for d = 1, #texts do
  local v, ss = {}, 0
  for j = off:get(d - 1), off:get(d) - 1 do
    local c = val:get(j)
    v[tok:get(j)] = c
    ss = ss + c * c
  end
  local inv = ss > 0 and 1 / num.sqrt(ss) or 0
  for k, c in pairs(v) do v[k] = c * inv end
  docs[d] = v
end
local n_labels = 2
local scores = fvec.create(#queries * n_labels)
for q = 1, #queries do
  local sums, counts = { 0, 0 }, { 0, 0 }
  local qv = docs[#train + q]
  for t = 1, #train do
    local dot = 0
    for k, c in pairs(qv) do
      local tc = docs[t][k]
      if tc then dot = dot + c * tc end
    end
    local l = train[t].label + 1
    sums[l] = sums[l] + dot
    counts[l] = counts[l] + 1
  end
  for l = 1, n_labels do
    scores:set((q - 1) * n_labels + (l - 1), sums[l] / counts[l])
  end
end
local g = decide.create({ n_labels = n_labels, single = true })
local pred = g:predict({ scores = scores, n_samples = #queries })
for q = 1, #queries do
  print(queries[q] .. " -> " .. names[pred:get(q - 1) + 1])
end
return pred:size()
]],
    },

    {
      title = "aho at scale: prepare, mmap, persist",
      desc = table.concat({
        "The two-phase build for large ",
        "gazetteers: prepare counts states, the goto table is mmapped at ",
        "n_states * 256 entries, and the built automaton persists to disk for ",
        "serve-time load.",
      }),
      runnable = false,
      code = [[
local aho = require("santoku.learn.aho")
local svec = require("santoku.svec")
local ivec = require("santoku.ivec")
local patterns = { "jane doe", "acme press", "acme" }
local names = { "Jane Doe", "Acme Press", "Acme Press" }
local priorities = ivec.create({ 2, 2, 1 })
local builder = aho.prepare({
  patterns = patterns,
  names = names,
  priorities = priorities,
  normalize = true,
})
local n_states = builder:n_states()
local goto_buf = svec.mmap_create("suggest.aho.goto", n_states * 256)
local ac = builder:build(goto_buf)
ac:persist("suggest.aho")
local served = aho.load("suggest.aho")
local S = served:predict({ texts = { "signed with acme press" }, longest = true })
return S:col("id"):size()
]],
    },

    {
      title = "santoku.learn.spectral: embed and retrieve with binary codes",
      desc = table.concat({
        "Weight n-gram features with bm25, embed them with a Nystrom spectral encoder, then ",
        "fit an ITQ rotation (santoku-matrix mtx:itq) and search the sign bits by exhaustive ",
        "Hamming top-k. Exact float topk over the codes is the reference. Queries reuse the ",
        "fitted bm25 statistics, the encoder, the centering means, and the rotation. The full ",
        "retrieval suite this distills: ",
        "https://github.com/birchpointswe/lua-santoku-learn/blob/master/test/spec/santoku/learn/retrieval.lua",
      }),
      runnable = false,
      code = [[
local tokenizer = require("santoku.learn.tokenizer")
local spectral = require("santoku.learn.spectral")
local ds = require("santoku.learn.dataset")
local mtx = require("santoku.mtx")
local function bits (M)
  local r, c = M:shape()
  return mtx.create({ data = M:sign(), n_rows = r, n_cols = c, bits = true })
end
local texts = ds.read_imdb("test/res/imdb.50k", 500).problems
local tok = tokenizer.create({ ngram_min = 4, ngram_max = 4, normalize = true })
local X = tok:fit({ texts = texts })
local w, avgdl = X:bm25()
X:normalize()
local _, enc = spectral.encode({ x = X, n_landmarks = 256, kernel = "cosine" })
local C = enc:encode(X)
C:normalize("row")
local mu = C:center()
C:normalize("row")
local W = C:itq({ iterations = 30 })
local B = bits(C:multiply(W))
print("docs, dims:", C:shape())
print("exact nnz:", C:topk(C, 10):nnz())
print("hamming nnz:", B:topk(B, 10):nnz())
local Y = tok:tokenize({ texts = { texts[1] } })
Y:bm25(w, avgdl)
Y:normalize()
local Q = enc:encode(Y)
Q:normalize("row")
Q:center(mu)
Q:normalize("row")
local hit = B:topk(bits(Q:multiply(W)), 1)
print("query finds doc:", hit:neighbors():get(0))
return hit:nnz()
]],
    },

    {
      title = "santoku.learn.optimize.krr: the supervised entry point",
      desc = table.concat({
        "The supervised path on the IMDB sentiment corpus: tokenize byte and word ",
        "blocks, encode, solve ridge, score through a calibrated decider, then persist ",
        "the whole deployment as one bundle and reload it. The full pipeline this ",
        "distills: ",
        "https://github.com/birchpointswe/lua-santoku-learn/blob/master/test/spec/santoku/learn/regress/imdb.lua",
      }),
      runnable = false,
      code = [[
local optimize = require("santoku.learn.optimize")
local ds = require("santoku.learn.dataset")
local util = require("santoku.learn.util")
local bundle = require("santoku.learn.bundle")
local dataset = ds.read_imdb("test/res/imdb.50k")
local train, test_set = ds.split_imdb(dataset, 0.5)
local W = util.word_spans(train.problems, train.n)
local Wt = util.word_spans(test_set.problems, test_set.n)
local blocks = {
  { ngram_min = 1, ngram_max = 5, mode = "flat" },
  { ngram_min = 1, ngram_max = 3, mode = "words" },
}
local toks, pool_blocks = util.tokenize_blocks(blocks, train.problems, { tokens = W })
local _, test_blocks = util.tokenize_blocks(blocks, test_set.problems, { toks = toks, tokens = Wt })
local enc, ridge, deploy, best, decider = optimize.krr({
  pool_blocks = pool_blocks,
  pool_labels = train.labels,
  n_labels = 1,
  relevance = { "bns", "bns" },
  n_landmarks = 1024 * 8,
  kernel = { "cosine" },
  lambda = { def = 0.025 },
  k = 1,
  decode_offset = { def = 0.49393576 },
  search_trials = 0,
  folds = 5,
})
local P = util.predict_tiled({
  deploy = deploy, ridge = ridge,
  blocks = test_blocks, n = test_set.n, k = 1,
})
local _, m = decider:score({
  pred = P, expected = test_set.labels, n_samples = test_set.n,
})
print(util.fmt_metrics(m))
bundle.persist({
  dir = "imdb.bundle",
  tokenizers = toks, encoder = enc, ridge = ridge, decider = decider,
})
local b = bundle.load("imdb.bundle")
local _, Xb = util.tokenize_blocks(blocks, test_set.problems, { toks = b.tokenizers, tokens = Wt })
local Pb = util.predict_tiled({ deploy = b.encode, ridge = b.ridge, blocks = Xb, n = test_set.n, k = 1 })
local _, mb = b.decider:score({ pred = Pb, expected = test_set.labels, n_samples = test_set.n })
print(util.fmt_metrics(mb))
return best.lambda
]],
    },

    {
      title = "santoku.learn.ner: span NER with gazetteer candidates",
      desc = table.concat({
        "Condensed from the CoNLL-2003 regression spec: a surface gazetteer proposes ",
        "typed candidate spans, a character gazetteer contributes a feature block, ",
        "optimize.krr trains the span head, and the decider scores span F1 through ",
        "the same NMS it deploys with. The full pipeline: ",
        "https://github.com/birchpointswe/lua-santoku-learn/blob/master/test/spec/santoku/learn/regress/conll-full.lua",
      }),
      runnable = false,
      code = [[
local ds = require("santoku.learn.dataset")
local ner = require("santoku.learn.ner")
local util = require("santoku.learn.util")
local optimize = require("santoku.learn.optimize")
local csr = require("santoku.csr")
local spans = require("santoku.spans")
local ivec = require("santoku.ivec")
local train, dev, test_set = ds.read_conll2003("test/res/conll2003")
local ac, pat_type = util.surface_gaz({ train, dev, test_set }, 4, false)
local pool = ds.merge_conll2003(train, dev)
local T = util.shape_spans(pool.texts, pool.n)
local S = ac:predict({ texts = pool.texts, longest = true, tokens = T })
local ty = ivec.create(S:col("id"):size()):copy(pat_type, S:col("id"))
local C = spans.create({ offsets = S:offsets(), s = S:col("s"), e = S:col("e"), ty = ty })
local Y = csr.from_mask(C:match_labels(pool.gold))
local blocks = {
  { ngram_min = 1, ngram_max = 5, normalize = false, regions = true },
}
local toks, X = util.tokenize_blocks(blocks, pool.texts, { focus = C, tokens = T })
local gaz = ner.build_char_gaz({
  texts = pool.texts, gold = pool.gold, n_types = 4,
  ngram_min = 1, ngram_max = 5,
})
X[#X + 1] = gaz:block(pool.texts, C, C:type_labels(pool.gold, 4))
local enc, ridge, deploy, best, decider = optimize.krr({
  pool_blocks = X,
  pool_labels = Y,
  pool_n = C:col("s"):size(),
  n_labels = 1,
  reject = 4,
  cand = C,
  gold = pool.gold,
  n_landmarks = 1024 * 8,
  kernel = { "matern" },
  decode_offset = { def = -0.56368208 },
  search_trials = 0,
  folds = 5,
})
local _, scores = util.predict_tiled({
  deploy = deploy, ridge = ridge,
  blocks = X, n = C:col("s"):size(), scores = true, n_labels = 1,
})
local f1, m = decider:score({
  scores = scores, cand = C, gold = pool.gold, n_samples = pool.n,
})
print(util.fmt_metrics(m))
return f1
]],
    },

    {
      title = "regression: santoku.learn.evaluator",
      desc = table.concat({
        "The same path does regression: pass targets instead of labels, mix ",
        "standardized continuous columns with booleanized bits as blocks, and score ",
        "with regress_accuracy (normalized MAE and friends). The full pipeline: ",
        "https://github.com/birchpointswe/lua-santoku-learn/blob/master/test/spec/santoku/learn/regress/housing.lua",
      }),
      runnable = false,
      code = [[
local ds = require("santoku.learn.dataset")
local eval = require("santoku.learn.evaluator")
local optimize = require("santoku.learn.optimize")
local util = require("santoku.learn.util")
local dataset = ds.read_california_housing("test/res/california-housing.csv", {})
local train, test_set = ds.split_california_housing(dataset, 0.8)
local mean = train.continuous:center()
test_set.continuous:center(mean)
local Xc = train.continuous:to_sparse():i32()
local sp = Xc:standardize()
local Xt = test_set.continuous:to_sparse():i32()
Xt:standardize(sp)
local bits = train.bits:i32()
local bits_std = bits:standardize()
local bits_t = test_set.bits:i32()
bits_t:standardize(bits_std)
local enc, ridge, deploy = optimize.krr({
  pool_blocks = { Xc, bits },
  pool_targets = train.targets,
  n_targets = 1,
  pool_n = train.n,
  n_landmarks = 1024 * 8,
  kernel = { "matern" },
  nu = { def = 0 },
  gamma = { def = 0.94 },
  lambda = { def = 0.0002 },
  search_trials = 0,
  folds = 5,
})
local _, scores = util.predict_tiled({
  deploy = deploy, ridge = ridge,
  blocks = { Xt, bits_t }, n = test_set.n, scores = true, n_labels = 1,
})
local m = eval.regress_accuracy(scores, test_set.targets)
print("test accuracy:", 1 - m.nmae)
return m.nmae
]],
    },

  },

}
