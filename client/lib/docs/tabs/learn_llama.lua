return {

  intro = table.concat({
    "santoku-learn-llama is a deliberately small C binding to llama.cpp with two jobs: ",
    "turn batches of text into dense embedding vectors (a santoku-matrix fvec of shape ",
    "n_samples x n_embd, the dense-codes alternative to santoku-learn's sparse BPE ",
    "vectorizer path), and provide a minimal text-generation entry point. The entire ",
    "surface is three constructors (create, embedder, generator) and five methods ",
    "across two object types; the modelling that consumes the embeddings lives in ",
    "santoku-learn. The binding links a statically built llama.cpp (vendored at a ",
    "pinned commit) with OpenMP and BLAS/LAPACK, and needs a gguf model file at ",
    "runtime, so nothing on this page can run in the browser: every example is ",
    "display-only, mirrored from the repo's regress ",
    "suites. The full pipelines live in those suites: ",
    "https://github.com/birchpointswe/lua-santoku-learn-llama/tree/master/test/spec/santoku/learn/regress ",
    "and the examples here are distillations.",
  }),

  examples = {

    {
      title = "loading an embedder",
      desc = table.concat({
        "create(path) loads a gguf model in embed mode. A number as the second ",
        "argument sets n_seq, the batch width in sequences per forward pass (default ",
        "32); an options table takes n_seq and n_threads (default: all OpenMP ",
        "threads). embedder(path, ...) is the explicit form of the same constructor. ",
        "dims() returns the model's embedding size, n_embd.",
      }),
      runnable = false,
      code = [[
local llama = require("santoku.learn.llama")
local enc = llama.create("model.gguf")
print("n_embd:", enc:dims())
local wide = llama.create("model.gguf", 64)
local tuned = llama.embedder("model.gguf", { n_seq = 16, n_threads = 8 })
print("same model, same dims:", wide:dims() == tuned:dims())
]],
    },

    {
      title = "encode: texts to dense codes",
      desc = table.concat({
        "encode takes an array of strings and returns a row-major fvec of shape ",
        "n_samples x n_embd plus the dimension as a second return. Each row is ",
        "L2-normalized by default. Pooling is model-driven: models with a pooling ",
        "type pool, others use the last-token embedding; there is no pooling option. ",
        "Each text is truncated to the model's training context, and the batch is ",
        "chunked n_seq sequences at a time.",
      }),
      runnable = false,
      code = [[
local llama = require("santoku.learn.llama")
local enc = llama.create("model.gguf")
local codes, dim = enc:encode({
  "the first document",
  "the second document",
  "the third document",
})
print("rows:", codes:size() / dim)
print("cols:", dim)
]],
    },

    {
      title = "encode options: normalization and in-place output",
      desc = table.concat({
        "Pass false as the second argument to skip L2 normalization. Pass an fvec as ",
        "the third argument and encode writes into it in place and returns nothing, ",
        "which pairs with mmap-backed vectors to keep large corpora off the heap.",
      }),
      runnable = false,
      code = [[
local llama = require("santoku.learn.llama")
local fvec = require("santoku.fvec")
local enc = llama.create("model.gguf")
local texts = { "alpha document", "beta document" }
local raw = enc:encode(texts, false)
print("unnormalized rows:", raw:size() / enc:dims())
local out = fvec.mmap_create("codes.bin", #texts * enc:dims())
enc:encode(texts, true, out)
out:mmap_sync()
print("written in place:", out:size())
]],
    },

    {
      title = "the point of it all: dense codes for the learn pipeline",
      desc = table.concat({
        "The embeddings stand in for santoku-learn's sparse n-gram codes: encode each ",
        "split, wrap the fvec in an mtx, and hand it to optimize.krr. Free each code ",
        "matrix once consumed; the encoded splits are the memory ceiling. Distilled ",
        "from the 20-newsgroups regress suite: ",
        "https://github.com/birchpointswe/lua-santoku-learn-llama/blob/master/test/spec/santoku/learn/regress/newsgroups-llama.lua",
      }),
      runnable = false,
      code = [[
local llama = require("santoku.learn.llama")
local mtx = require("santoku.mtx")
local optimize = require("santoku.learn.optimize")
local enc = llama.create(model_path)
local n_dims = enc:dims()
local train_codes = enc:encode(train.problems)
train_codes = mtx.create({ n_rows = train.n, n_cols = n_dims, data = train_codes })
train.problems = nil
local enc2, ridge_obj, _, best_params, decider = optimize.krr({
  pool_codes = train_codes,
  pool_labels = train.labels,
  pool_class = train.labels:neighbors(),
  n_labels = 20,
  folds = 3,
  n_landmarks = 1024 * 8,
  relevance = { "auc" },
  lambda = { def = 2.35441e-05 },
  k = 1,
  search_trials = 0,
})
train_codes = nil
collectgarbage("collect")
local test_codes = enc:encode(test_set.problems)
test_codes = mtx.create({ n_rows = test_set.n, n_cols = n_dims, data = test_codes })
local scores = ridge_obj:regress(enc2:encode(test_codes))
local _, metrics = decider:score({
  scores = scores, n_samples = test_set.n, expected = test_set.labels,
})
]],
    },

    {
      title = "sentence pairs: one string per sample",
      desc = table.concat({
        "The model sees exactly one string per sample, so pair tasks (NLI, duplicate ",
        "detection) concatenate the two sides into a single text before encoding; the ",
        "resulting fvec flows into the ridge pipeline unchanged. Pattern from the SNLI ",
        "walkthrough in ",
        "https://github.com/birchpointswe/lua-santoku-learn-llama/blob/master/doc/usage.md",
      }),
      runnable = false,
      code = [[
local llama = require("santoku.learn.llama")
local enc = llama.create(model_path)
local function pair_texts (split)
  local texts = {}
  for i = 1, split.n do
    local a = split.unique_texts[split.idx1:get(i - 1) + 1]
    local b = split.unique_texts[split.idx2:get(i - 1) + 1]
    texts[i] = a .. "\n" .. b
  end
  return texts
end
local train_codes = enc:encode(pair_texts(train))
]],
    },

    {
      title = "extreme multi-label: same embedder, bigger k",
      desc = table.concat({
        "For thousands of labels the embedder's role is unchanged: produce the dense ",
        "codes. The eurlex57k regress suite drives optimize.krr with a Matern kernel ",
        "and k = 256, then labels the test split through the deploy encoder. The full ",
        "pipeline: ",
        "https://github.com/birchpointswe/lua-santoku-learn-llama/blob/master/test/spec/santoku/learn/regress/eurlex-llama.lua",
      }),
      runnable = false,
      code = [[
local llama = require("santoku.learn.llama")
local mtx = require("santoku.mtx")
local optimize = require("santoku.learn.optimize")
local enc = llama.create(model_path)
local n_dims = enc:dims()
local pool_codes = enc:encode(collect_texts(train.text_iter, train.n))
pool_codes = mtx.create({ n_rows = train.n, n_cols = n_dims, data = pool_codes })
local _, ridge_obj, deploy, best, decider = optimize.krr({
  pool_codes = pool_codes,
  pool_labels = train.labels,
  n_labels = train.n_labels,
  folds = 3,
  kernel = { "matern" },
  nu = { def = 3 },
  gamma = { def = 1.10565 },
  lambda = { def = 5.23323e-06 },
  n_landmarks = 1024 * 8,
  k = 256,
  search_trials = 0,
})
local test_codes = enc:encode(collect_texts(test_set.text_iter, test_set.n))
test_codes = mtx.create({ n_rows = test_set.n, n_cols = n_dims, data = test_codes })
local P = ridge_obj:label(deploy(test_codes), 256)
]],
    },

    {
      title = "semantic search",
      desc = table.concat({
        "Documents are embedded once with a document prefix into an mmap-backed fvec index, and ",
        "each query is encoded on the fly with an asymmetric query prefix (both ",
        "prefixes come from the model card, via env vars). Retrieval is cosine top-k ",
        "over the normalized rows via mtx.",
      }),
      runnable = false,
      code = [[
local llama = require("santoku.learn.llama")
local mtx = require("santoku.mtx")
local fvec = require("santoku.fvec")
local ivec = require("santoku.ivec")
local env = require("santoku.env")
local enc = llama.create(env.var("LLAMA_MODEL"))
local query_prefix = env.var("LLAMA_MODEL_QUERY_PREFIX", "")
local d = enc:dims()
local ids = ivec.load("deals.ids")
local codes = fvec.mmap_open("deals.mcodes")
local query_emb = enc:encode({ query_prefix .. "cozy fantasy debut" }, true)
local Mc = mtx.create({ data = codes, n_rows = ids:size(), n_cols = d })
local Mq = mtx.create({ data = query_emb, n_rows = 1, n_cols = d })
local hits = Mc:topk(Mq, 10)
]],
    },

    {
      title = "generator: raw prompts",
      desc = table.concat({
        "generator(path, opts) loads a model in decode mode: n_ctx defaults to 4096 ",
        "and is capped at the model's training context. generate(prompt, opts) ",
        "returns just the completion; stop strings truncate output (the matched stop ",
        "is removed), and end-of-generation tokens end it naturally. On a generator, ",
        "dims() is the vocabulary size. Distilled from ",
        "https://github.com/birchpointswe/lua-santoku-learn-llama/blob/master/test/spec/santoku/learn/regress/generate-llama.lua",
      }),
      runnable = false,
      code = [[
local llama = require("santoku.learn.llama")
local g = llama.generator(model_path, { n_ctx = 2048 })
local prompt = "<|begin_of_text|><|start_header_id|>user<|end_header_id|>\n\n"
  .. "Say hi in one word.<|eot_id|>"
  .. "<|start_header_id|>assistant<|end_header_id|>\n\n"
local out = g:generate(prompt, {
  max_tokens = 16, temperature = 0.0, stop = { "\n", "<|" },
})
print("vocab:", g:dims())
print("completion:", out)
]],
    },

    {
      title = "generator: chat templates",
      desc = table.concat({
        "Construct with template = \"llama3\" or \"chatml\" and chat() builds the ",
        "prompt from system (optional), user (required), and assistant_prefix ",
        "(optional) fields. Without a template chat() raises; use generate() for raw ",
        "prompts. create(path, { mode = \"generate\", ... }) is the dispatching form ",
        "of the same constructor.",
      }),
      runnable = false,
      code = [[
local llama = require("santoku.learn.llama")
local g = llama.generator(model_path, { n_ctx = 2048, template = "llama3" })
local out = g:chat(
  { system = "You write terse one-line answers.", user = "Say hi in one word." },
  { max_tokens = 16, temperature = 0.0, stop = { "\n" } })
print("completion:", out)
local raw = llama.create(model_path, { mode = "generate" })
local ok, err = pcall(function ()
  return raw:chat({ user = "hi" })
end)
print("no template configured:", ok, err)
]],
    },

    {
      title = "sampling options",
      desc = table.concat({
        "Defaults: max_tokens 64, temperature 0 (greedy). With temperature above 0 ",
        "the sampler chain is repeat penalty (only when repeat_penalty exceeds 1, ",
        "over the last 64 tokens), top_k 40, top_p 0.95, min_p 0.05, temperature, ",
        "then a seeded distribution; seed defaults to the constructor's seed ",
        "(default 0). generate errors on an empty prompt or one that fills n_ctx.",
      }),
      runnable = false,
      code = [[
local llama = require("santoku.learn.llama")
local g = llama.generator(model_path, { n_ctx = 4096, seed = 42 })
local greedy = g:generate("Once upon a time", { max_tokens = 64 })
local sampled = g:generate("Once upon a time", {
  max_tokens = 128,
  temperature = 0.8,
  top_k = 40,
  top_p = 0.95,
  min_p = 0.05,
  repeat_penalty = 1.1,
  seed = 7,
  stop = { "\n\n" },
})
print("greedy is deterministic:", greedy == g:generate("Once upon a time"))
]],
    },

    {
      title = "what it takes to run",
      desc = table.concat({
        "The rock builds against a vendored llama.cpp pinned by commit and links its ",
        "static archives with OpenMP, BLAS/LAPACK, and libstdc++; at runtime you ",
        "supply a gguf model file. The regress suites are benchmarks, not unit tests: ",
        "they read LLAMA_MODEL (embedders) or LLAMA_GEN_MODEL (generator) and skip ",
        "when unset. llama.cpp logging is silenced, and the backend is refcounted: ",
        "it is freed when the last embedder or generator is collected.",
      }),
      runnable = false,
      code = [[
local env = require("santoku.env")
local model_path = env.var("LLAMA_MODEL", nil)
if not model_path then
  print("LLAMA_MODEL not set. Skipping.")
  return
end
local llama = require("santoku.learn.llama")
local enc = llama.create(model_path)
print("n_embd:", enc:dims())
]],
    },

  },

}
