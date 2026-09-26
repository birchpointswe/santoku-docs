return {

  intro = table.concat({
    "santoku-matrix is the numeric data layer of the framework: typed C-backed ",
    "vectors (ivec for i64, dvec for f64, fvec for f32, svec for i32, plus pair ",
    "and byte vectors), dense matrices (mtx), sparse matrices (csr), labelled span ",
    "sets (spans), disk-backed mmap vectors, and C-level hash maps. It sits under ",
    "santoku-learn and santoku.sqlite.fts. ",
    "A few conventions hold everywhere: storage is zero-copy ",
    "(create adopts the vectors you pass, so mutating one side is visible from the ",
    "other), in-place operations return self so they chain, indices are 0-based ",
    "throughout, feature transforms follow a fit/apply idiom (fit returns the ",
    "learned weights, pass them back to apply), and gather operations accept an ",
    "out= destination to avoid allocation in hot loops. On native builds the dense ",
    "math routes through BLAS; under WebAssembly the same functions compile to ",
    "portable C loops, and that wasm build is the one this page ships. The ",
    "vector and matrix modules below (ivec, dvec, fvec, pvec, mtx, csr, spans) run ",
    "live in your browser; only the file-backed paths (persist, mmap) and the hash ",
    "map modules are shown for reading.",
  }),

  examples = {

    {
      title = "ivec: typed vector basics",
      desc = table.concat({
        "Vectors are growable typed arrays with 0-based indices. Sorting is in place, table converts to ",
        "a plain Lua table, and every range argument is a half-open [start, end) pair. max and min return ",
        "both the value and its index; find returns the index of the first match or nil.",
      }),
      code = [[
local ivec = require("santoku.ivec")
local arr = require("santoku.array")
local v = ivec.create({ 5, 2, 8, 1, 9 })
v:push(4)
print("size:", v:size())
print("sum:", v:sum())
local val, idx = v:max()
print("max:", val, "at index", idx)
v:asc()
print("sorted:", arr.concat(v:table(), " "))
print("head:", arr.concat(v:table(0, 3), " "))
v:insert(0, 0)
print("inserted:", arr.concat(v:table(), " "))
print("find(8):", v:find(8))
return v:size()
]],
    },

    {
      title = "dvec: elementwise math",
      desc = table.concat({
        "The float vectors carry the math surface: dot products, L2 magnitude, vector add and scalar ",
        "scale (both in place), elementwise pow, exp, and log, and rounding that chains into an integer ",
        "conversion. round goes half away from zero, so 2.5 becomes 3. dot, scale, and addv are BLAS ",
        "calls natively and plain loops in this wasm build.",
      }),
      code = [[
local dvec = require("santoku.dvec")
local arr = require("santoku.array")
local a = dvec.create({ 1, 2, 3 })
local b = dvec.create({ 4, 5, 6 })
print("dot:", a:dot(b))
print("magnitude:", dvec.create({ 3, 4 }):magnitude())
a:addv(b)
a:scale(2)
print("addv then scale:", arr.concat(a:table(), " "))
local p = dvec.create({ 1, 2, 3 })
p:pow(2)
print("pow:", arr.concat(p:table(), " "))
local r = dvec.create({ 1.4, 2.5, 3.6 })
local i = r:round():to_ivec()
print("round to_ivec:", arr.concat(i:table(), " "))
local e = dvec.create({ 0, 1, 2 })
e:exp()
e:log()
print("exp log roundtrip:", arr.concat(e:table(), " "))
return a:sum()
]],
    },

    {
      title = "selection, gather, and counting",
      desc = table.concat({
        "where returns the indices where a comparison holds (gt, lt, ge, le, eq, ne), and copy with an ",
        "index vector gathers those positions into a new vector. lookup rewrites each element by using ",
        "it as an index into a source vector, fill_segments broadcasts one value per csr-style segment, ",
        "and bincount histograms small integer ids, optionally weighted by a dvec.",
      }),
      code = [[
local ivec = require("santoku.ivec")
local dvec = require("santoku.dvec")
local arr = require("santoku.array")
local v = ivec.create({ 5, 0, 7, 0, 3 })
local idx = v:where("gt", 0)
print("hits:", arr.concat(idx:table(), " "))
local picked = ivec.create(idx:size())
picked:copy(v, idx)
print("picked:", arr.concat(picked:table(), " "))
local ids = ivec.create({ 2, 0, 1, 2 })
ids:lookup(ivec.create({ 100, 200, 300 }))
print("lookup:", arr.concat(ids:table(), " "))
local seg = ivec.create(5)
seg:zero()
seg:fill_segments(ivec.create({ 0, 2, 5 }), ivec.create({ 7, 9 }))
print("segments:", arr.concat(seg:table(), " "))
local bins = ivec.create({ 0, 2, 2, 1, 2 }):bincount(3)
print("bincount:", arr.concat(bins:table(), " "))
local wb = ivec.create({ 0, 2, 2, 1, 2 })
  :bincount(3, dvec.create({ 1, 0.5, 0.5, 2, 1 }))
print("weighted:", arr.concat(wb:table(), " "))
return picked:size()
]],
    },

    {
      title = "sorted ivecs as integer sets",
      desc = table.concat({
        "A sorted ivec doubles as an integer set: jaccard, overlap, dice, and tversky similarities, plus ",
        "materialized intersection and union. set_find is a binary search that returns the position on a ",
        "hit and an encoded negative insertion point on a miss, which pairs with set_insert to keep the ",
        "vector sorted.",
      }),
      code = [[
local ivec = require("santoku.ivec")
local arr = require("santoku.array")
local a = ivec.create({ 1, 2, 3, 4 })
local b = ivec.create({ 3, 4, 5, 6 })
print("jaccard:", a:set_jaccard(b))
print("overlap:", a:set_overlap(b))
print("dice:", a:set_dice(b))
print("intersect:", arr.concat(a:set_intersect(b):table(), " "))
print("union:", arr.concat(a:set_union(b):table(), " "))
local s = ivec.create({ 10, 20, 30, 40, 50 })
print("set_find(30):", s:set_find(30))
print("set_find(25):", s:set_find(25))
local t = ivec.create({ 10, 30, 50 })
t:set_insert(1, 20)
print("set_insert:", arr.concat(t:table(), " "))
return a:set_overlap(b)
]],
    },

    {
      title = "pvec: bounded top-k heaps",
      desc = table.concat({
        "pvec stores (i64, i64) pairs and compares on the second field. hmax(id, value, k) maintains a ",
        "max-heap capped at k entries that retains the k smallest values (hmin retains the k largest), ",
        "which is the streaming keep-the-best-k pattern used in retrieval. asc then sorts the survivors, ",
        "and keys and values split the pairs into ivecs. rvec is the (i64, f64) twin for float scores.",
      }),
      code = [[
local pvec = require("santoku.pvec")
local arr = require("santoku.array")
local heap = pvec.create()
heap:hmax(1, 50, 3)
heap:hmax(2, 10, 3)
heap:hmax(3, 30, 3)
heap:hmax(4, 40, 3)
heap:hmax(5, 20, 3)
print("kept:", heap:size())
heap:asc()
print("ids:", arr.concat(heap:keys():table(), " "))
print("values:", arr.concat(heap:values():table(), " "))
local i, p = heap:get(0)
print("best:", i, p)
return heap:size()
]],
    },

    {
      title = "mtx: wrap a vector, zero copies",
      desc = table.concat({
        "A dense matrix is a row-major view over a typed vector. Wrapping adopts the vector: data ",
        "returns the very same object, and writes through either side are visible in the other, here ",
        "in wasm linear memory. Allocation without data gives a ",
        "zeroed matrix, the element type is inferred from the wrapped vector, and from_pairs scatters ",
        "(row, col) index pairs into a count or weight matrix.",
      }),
      code = [[
local mtx = require("santoku.mtx")
local dvec = require("santoku.dvec")
local ivec = require("santoku.ivec")
local arr = require("santoku.array")
local v = dvec.create({ 1, 2, 3, 4, 5, 6 })
local M = mtx.create({ data = v, n_rows = 2, n_cols = 3 })
print("shape:", M:shape())
print("type:", M:type())
print("get(1, 2):", M:get(1, 2))
v:set(5, 60)
print("after vec set:", M:get(1, 2))
print("same object:", M:data() == v)
local Z = mtx.create({ n_rows = 2, n_cols = 2, type = "f64" })
print("zeroed:", Z:get(0, 0), Z:get(1, 1))
local I = mtx.create({ data = ivec.create({ 1, 2, 3, 4 }), n_rows = 2, n_cols = 2 })
print("inferred:", I:type())
local P = mtx.from_pairs(
  ivec.create({ 0, 0, 1, 2, 2, 2 }),
  ivec.create({ 0, 1, 1, 0, 0, 1 }), 3, 2)
print("from_pairs:", arr.concat(P:data():table(), " "))
return M:shape()
]],
    },

    {
      title = "mtx: axis reductions",
      desc = table.concat({
        "Every reduction takes an axis, \"row\" or \"col\", and returns a vector: sums, maxs, mins, mags ",
        "(L2 norm per slice), maxargs and minargs (the winning index per slice), and argsort, which ",
        "returns per-slice orderings concatenated into one ivec.",
      }),
      code = [[
local mtx = require("santoku.mtx")
local dvec = require("santoku.dvec")
local arr = require("santoku.array")
local M = mtx.create({ data = dvec.create({ 1, 2, 3, 4, 5, 6 }), n_rows = 2, n_cols = 3 })
print("row sums:", arr.concat(M:sums("row"):table(), " "))
print("col sums:", arr.concat(M:sums("col"):table(), " "))
print("row maxs:", arr.concat(M:maxs("row"):table(), " "))
print("col mins:", arr.concat(M:mins("col"):table(), " "))
local A = mtx.create({ data = dvec.create({ 1, 5, 2, 9, 3, 7 }), n_rows = 2, n_cols = 3 })
print("row maxargs:", arr.concat(A:maxargs("row"):table(), " "))
local G = mtx.create({ data = dvec.create({ 3, 4, 0, 5, 12, 0 }), n_rows = 2, n_cols = 3 })
print("row mags:", arr.concat(G:mags("row"):table(), " "))
local S = mtx.create({ data = dvec.create({ 5, 1, 3, 9, 2, 7 }), n_rows = 2, n_cols = 3 })
print("argsort:", arr.concat(S:argsort("row", "asc"):table(), " "))
return M:shape()
]],
    },

    {
      title = "mtx: transpose, gather, hcat, out=",
      desc = table.concat({
        "transpose, rows, and cols return new matrices (rows gathers whole rows by index vector, in the ",
        "order given), row extracts one row as a vector, and hcat concatenates columns in place, ",
        "returning self. Gathers accept an out= destination that is resized and reused, the pattern hot ",
        "loops rely on to avoid allocation.",
      }),
      code = [[
local mtx = require("santoku.mtx")
local dvec = require("santoku.dvec")
local ivec = require("santoku.ivec")
local arr = require("santoku.array")
local M = mtx.create({ data = dvec.create({ 1, 2, 3, 4, 5, 6 }), n_rows = 2, n_cols = 3 })
local T = M:transpose()
print("T shape:", T:shape())
print("T data:", arr.concat(T:data():table(), " "))
local N = mtx.create({
  data = dvec.create({ 1, 2, 3, 4, 5, 6, 7, 8, 9 }),
  n_rows = 3, n_cols = 3,
})
print("rows(2, 0):", arr.concat(N:rows(ivec.create({ 2, 0 })):data():table(), " "))
print("cols(2, 1):", arr.concat(N:cols(ivec.create({ 2, 1 })):data():table(), " "))
print("row(1):", arr.concat(N:row(1):table(), " "))
local A = mtx.create({ data = dvec.create({ 1, 2, 5, 6 }), n_rows = 2, n_cols = 2 })
local B = mtx.create({ data = dvec.create({ 3, 7 }), n_rows = 2, n_cols = 1 })
print("hcat is self:", A:hcat(B) == A)
print("hcat data:", arr.concat(A:data():table(), " "))
local out = mtx.create({ n_rows = 1, n_cols = 1 })
print("out reused:", N:rows(ivec.create({ 1 }), out) == out)
return A:shape()
]],
    },

    {
      title = "mtx: matrix products",
      desc = table.concat({
        "multiply is a full matmul with optional transpose flags for either operand and an out= ",
        "destination; multiplyv is the matrix-vector product, with a transpose flag that computes A ",
        "transposed times v. Natively these are cblas_dgemm and cblas_dgemv; in this wasm build they run ",
        "as portable C loops, same results.",
      }),
      code = [[
local mtx = require("santoku.mtx")
local dvec = require("santoku.dvec")
local arr = require("santoku.array")
local A = mtx.create({ data = dvec.create({ 1, 2, 3, 4 }), n_rows = 2, n_cols = 2 })
local B = mtx.create({ data = dvec.create({ 5, 6, 7, 8 }), n_rows = 2, n_cols = 2 })
local C = A:multiply(B)
print("A*B:", arr.concat(C:data():table(), " "))
local Ct = A:multiply(B, false, true)
print("A*Bt:", arr.concat(Ct:data():table(), " "))
local M = mtx.create({ data = dvec.create({ 1, 2, 3, 4, 5, 6 }), n_rows = 2, n_cols = 3 })
local y = M:multiplyv(dvec.create({ 1, 2, 3 }))
print("M*v:", arr.concat(y:table(), " "))
local yt = M:multiplyv(dvec.create({ 1, 2 }), true)
print("Mt*v:", arr.concat(yt:table(), " "))
local buf = dvec.create(0)
print("out reused:", M:multiplyv(dvec.create({ 1, 1, 1 }), false, buf) == buf)
return C:shape()
]],
    },

    {
      title = "mtx: fit and apply transforms",
      desc = table.concat({
        "center subtracts per-column means and returns them; pass those means to center held-out data ",
        "identically. standardize returns means and inverse standard deviations, and normalize scales ",
        "each row to unit L2 norm in place. The same fit/apply idiom runs through the whole library.",
      }),
      code = [[
local mtx = require("santoku.mtx")
local dvec = require("santoku.dvec")
local arr = require("santoku.array")
local M = mtx.create({ data = dvec.create({ 1, 10, 3, 20 }), n_rows = 2, n_cols = 2 })
local means = M:center()
print("means:", arr.concat(means:table(), " "))
print("centered:", arr.concat(M:data():table(), " "))
local N = mtx.create({ data = dvec.create({ 2, 15 }), n_rows = 1, n_cols = 2 })
N:center(means)
print("applied:", arr.concat(N:data():table(), " "))
local S = mtx.create({ data = dvec.create({ 1, 10, 3, 20 }), n_rows = 2, n_cols = 2 })
local mu, istd = S:standardize()
print("col sums now:", arr.concat(S:sums("col"):table(), " "))
print("istd size:", istd:size())
local L = mtx.create({ data = dvec.create({ 3, 4, 0, 0, 5, 12 }), n_rows = 2, n_cols = 3 })
L:normalize("row")
print("row mags:", arr.concat(L:mags("row"):table(), " "))
return mu:size()
]],
    },

    {
      title = "csr: build sparse rows",
      desc = table.concat({
        "A csr is offsets (length n_rows plus one), neighbors (column ids), and optional values; omit ",
        "values and it is a binary matrix with type \"none\". Wrap existing vectors zero-copy, or build ",
        "incrementally: push adds (column, value) pairs and row closes each row, including empty ones. ",
        "from_classes turns one label per row into one-hot rows, from_mask turns a 0/1 vector into a ",
        "single indicator column.",
      }),
      code = [[
local csr = require("santoku.csr")
local ivec = require("santoku.ivec")
local arr = require("santoku.array")
local X = csr.create({
  offsets = ivec.create({ 0, 2, 3, 5 }),
  neighbors = ivec.create({ 0, 2, 1, 0, 3 }),
  n_cols = 4,
})
print("shape:", X:shape())
print("nnz:", X:nnz())
print("type:", X:type())
local B = csr.create({ n_cols = 4, values = "f32" })
B:push(0, 1.5):push(2, 2.5):row()
B:row()
B:push(3):row()
print("offsets:", arr.concat(B:offsets():table(), " "))
print("neighbors:", arr.concat(B:neighbors():table(), " "))
print("value(1):", B:values():get(1))
local C = csr.from_classes(ivec.create({ 2, 0, 1, 2 }))
print("classes:", arr.concat(C:neighbors():table(), " "))
local M = csr.from_mask(ivec.create({ 1, 0, 1, 1, 0 }))
print("mask offsets:", arr.concat(M:offsets():table(), " "))
return X:nnz()
]],
    },

    {
      title = "csr: feature weighting",
      desc = table.concat({
        "bm25 with no weights fits BM25 idf per column, log((N - df + 0.5) / (df + 0.5)) floored at ",
        "1e-6, and the average row length, rewrites each value to its saturated BM25 weight (k1 = 1.2, ",
        "b = 0.75 unless passed as bm25(k1, b)), and returns both. Pass them back as bm25(w, avgdl) to ",
        "weight held-out rows with the fitted statistics; row lengths are measured per row. normalize ",
        "L2-scales each row and materializes f32 values on a binary matrix, and scale_cols multiplies ",
        "each column by a weight. bns and standardize follow the same fit and apply pattern for ",
        "supervised and z-score weighting.",
      }),
      code = [[
local csr = require("santoku.csr")
local ivec = require("santoku.ivec")
local fvec = require("santoku.fvec")
local X = csr.create({
  offsets = ivec.create({ 0, 1, 2, 4 }),
  neighbors = ivec.create({ 0, 0, 0, 1 }),
  values = fvec.create({ 1, 1, 1, 1 }),
  n_cols = 2,
})
local w, avgdl = X:bm25()
print("idf weights:", w:get(0), w:get(1))
print("average row length:", avgdl)
local Y = csr.create({
  offsets = ivec.create({ 0, 2 }),
  neighbors = ivec.create({ 0, 1 }),
  values = fvec.create({ 1, 1 }),
  n_cols = 2,
})
Y:bm25(w, avgdl)
print("applied:", Y:values():get(0), Y:values():get(1))
local N = csr.create({
  offsets = ivec.create({ 0, 2, 3 }),
  neighbors = ivec.create({ 0, 1, 1 }),
  n_cols = 2,
})
N:normalize()
print("materialized:", N:type())
print("values:", N:values():get(0), N:values():get(2))
N:scale_cols(fvec.create({ 10, 100 }))
print("scaled:", N:values():get(0), N:values():get(2))
return N:type()
]],
    },

    {
      title = "csr: gather, select, hcat, transpose",
      desc = table.concat({
        "rows gathers whole rows into a new csr, select keeps a subset of columns and remaps their ids ",
        "to a compact 0-based space, hcat concatenates feature blocks in place (shifting the right ",
        "block's column ids past the left block's width), and transpose flips rows and columns, ",
        "carrying values along.",
      }),
      code = [[
local csr = require("santoku.csr")
local ivec = require("santoku.ivec")
local fvec = require("santoku.fvec")
local arr = require("santoku.array")
local X = csr.create({
  offsets = ivec.create({ 0, 2, 4, 6 }),
  neighbors = ivec.create({ 10, 20, 30, 40, 50, 60 }),
  values = fvec.create({ 1, 2, 3, 4, 5, 6 }),
  n_cols = 100,
})
local Y = X:rows(ivec.create({ 0, 2 }))
print("gathered:", arr.concat(Y:neighbors():table(), " "))
local S = csr.create({
  offsets = ivec.create({ 0, 3, 5 }),
  neighbors = ivec.create({ 0, 1, 2, 1, 3 }),
  values = fvec.create({ 1, 2, 3, 4, 5 }),
  n_cols = 4,
})
local P = S:select(ivec.create({ 1, 3 }))
print("selected:", arr.concat(P:neighbors():table(), " "))
print("remapped shape:", P:shape())
local A = csr.create({
  offsets = ivec.create({ 0, 2, 3 }),
  neighbors = ivec.create({ 0, 1, 2 }),
  n_cols = 3,
})
local B = csr.create({
  offsets = ivec.create({ 0, 1, 2 }),
  neighbors = ivec.create({ 0, 1 }),
  n_cols = 2,
})
A:hcat(B)
print("hcat shifted:", arr.concat(A:neighbors():table(), " "))
local V = csr.create({
  offsets = ivec.create({ 0, 2, 3 }),
  neighbors = ivec.create({ 0, 1, 0 }),
  values = fvec.create({ 1, 2, 3 }),
  n_cols = 2,
})
local T = V:transpose()
print("T values:", T:values():get(0), T:values():get(1), T:values():get(2))
return A:shape()
]],
    },

    {
      title = "dense, sparse, and bit bridges",
      desc = table.concat({
        "to_sparse drops zeros (or anything under an optional epsilon) into a csr, to_dense expands ",
        "back, and the pair round-trips exactly. to_bits packs a binary csr into a bitmap vector for ",
        "the mtx bits layout, and from_bits unpacks it, so the same rows can move between the three ",
        "representations.",
      }),
      code = [[
local mtx = require("santoku.mtx")
local csr = require("santoku.csr")
local ivec = require("santoku.ivec")
local dvec = require("santoku.dvec")
local arr = require("santoku.array")
local M = mtx.create({
  data = dvec.create({ 1, 0, 3, 0, 2, 0 }),
  n_rows = 2, n_cols = 3,
})
local X = M:to_sparse()
print("offsets:", arr.concat(X:offsets():table(), " "))
print("neighbors:", arr.concat(X:neighbors():table(), " "))
print("value(1):", X:values():get(1))
local D = X:to_dense()
print("roundtrip:", D:eq(M))
local B = csr.create({
  offsets = ivec.create({ 0, 2, 3, 5 }),
  neighbors = ivec.create({ 0, 2, 1, 0, 3 }),
  n_cols = 4,
})
local bits = B:to_bits()
local Y = csr.from_bits(bits, 3, 4)
print("bits roundtrip:", B:eq(Y))
return X:nnz()
]],
    },

    {
      title = "bit matrices: popcount, hamming, bitwise ops",
      desc = table.concat({
        "A bits-tagged mtx wraps a packed bitmap and supports popcount, hamming distance, transpose, ",
        "and in-place band, bor, bxor, and bandnot. Hamming distance equals the popcount of the xor, ",
        "and transpose preserves popcount. This is the binary-fingerprint layout used for sign-hashed ",
        "embeddings.",
      }),
      code = [[
local csr = require("santoku.csr")
local mtx = require("santoku.mtx")
local ivec = require("santoku.ivec")
local A = csr.create({
  offsets = ivec.create({ 0, 2, 3 }),
  neighbors = ivec.create({ 0, 2, 1 }),
  n_cols = 4,
})
local B = csr.create({
  offsets = ivec.create({ 0, 1, 3 }),
  neighbors = ivec.create({ 0, 1, 3 }),
  n_cols = 4,
})
local MA = mtx.create({ data = A:to_bits(), n_rows = 2, n_cols = 4, bits = true })
local MB = mtx.create({ data = B:to_bits(), n_rows = 2, n_cols = 4, bits = true })
print("type:", MA:type())
print("popcounts:", MA:popcount(), MB:popcount())
print("hamming:", MA:hamming(MB))
local T = MA:transpose()
print("T shape:", T:shape())
print("T popcount:", T:popcount())
MA:band(MB)
print("after band:", MA:popcount())
return MA:popcount()
]],
    },

    {
      title = "topk: brute-force retrieval",
      desc = table.concat({
        "corpus:topk(queries, k) scores every corpus row against every query row by dot product (BLAS ",
        "natively, C loops here) and keeps each query's k best with a bounded heap. The result is a ",
        "csr with one row per query, neighbors holding corpus row ids and values holding scores, both ",
        "ordered by descending score. On a bits matrix, topk is an exhaustive Hamming search instead: ",
        "the values are distances, smallest first.",
      }),
      code = [[
local mtx = require("santoku.mtx")
local dvec = require("santoku.dvec")
local arr = require("santoku.array")
local corpus = mtx.create({
  data = dvec.create({ 1, 0, 0, 1, 0.5, 0.5 }),
  n_rows = 3, n_cols = 2,
})
local q = mtx.create({
  data = dvec.create({ 1, 0 }),
  n_rows = 1, n_cols = 2,
})
local P = corpus:topk(q, 2)
print("shape:", P:shape())
print("nnz:", P:nnz())
print("offsets:", arr.concat(P:offsets():table(), " "))
print("ids:", arr.concat(P:neighbors():table(), " "))
print("scores:", arr.concat(P:values():table(), " "))
return P:nnz()
]],
    },

    {
      title = "mtx: sign bits, ITQ, and Hamming top-k",
      desc = table.concat({
        "sign packs an f32 or f64 matrix into a raw sign-bit vector; wrap it with bits = true to get ",
        "a bits mtx. itq fits a rotation that balances those bits against the float geometry, with a ",
        "PCA step first when bits is below n_cols. Center and row-normalize the codes before fitting. ",
        "itq takes iterations (50), bits (n_cols) and rotate (true), and returns W, the loss per ",
        "iteration, the inner step counts, and the variance fraction PCA kept. topk on the bits mtx ",
        "then ranks by Hamming distance.",
      }),
      code = [[
local mtx = require("santoku.mtx")
local fvec = require("santoku.fvec")
local arr = require("santoku.array")
local function bits (M)
  local r, c = M:shape()
  return mtx.create({ data = M:sign(), n_rows = r, n_cols = c, bits = true })
end
local C = mtx.create({
  data = fvec.create({ 0.9, 0.1, -0.2, 0.8, 0.2, -0.1, -0.7, 0.6, 0.3, -0.8, 0.5, 0.2 }),
  n_rows = 4, n_cols = 3,
})
C:normalize("row")
C:center()
C:normalize("row")
local W, loss, _, kept = C:itq({ iterations = 20 })
print("W shape:", W:shape())
print("iterations:", loss:size(), "kept:", kept)
local B = bits(C:multiply(W))
print("type:", B:type())
local P = B:topk(B, 2)
print("ids:", arr.concat(P:neighbors():table(), " "))
print("hamming:", arr.concat(P:values():table(), " "))
return P:nnz()
]],
    },

    {
      title = "csr.fuse: hybrid result merging",
      desc = table.concat({
        "fuse merges two ranked result sets row by row: the default sums scores across sides (with ",
        "optional per-side weights), k keeps only the top k per row, and mode rrf switches to ",
        "reciprocal rank fusion over 0-based row positions, ignoring the raw scores. Output rows come ",
        "back sorted by descending fused score, ready to feed a hybrid lexical-plus-vector ranker.",
      }),
      code = [[
local csr = require("santoku.csr")
local ivec = require("santoku.ivec")
local fvec = require("santoku.fvec")
local arr = require("santoku.array")
local A = csr.create({
  offsets = ivec.create({ 0, 2 }),
  neighbors = ivec.create({ 10, 20 }),
  values = fvec.create({ 0.9, 0.5 }),
  n_cols = 100,
})
local B = csr.create({
  offsets = ivec.create({ 0, 2 }),
  neighbors = ivec.create({ 20, 30 }),
  values = fvec.create({ 0.8, 0.4 }),
  n_cols = 100,
})
local Y = csr.fuse(A, B)
print("ids:", arr.concat(Y:neighbors():table(), " "))
print("scores:", arr.concat(Y:values():table(), " "))
local W = csr.fuse(A, B, { weights = { 1, 10 } })
print("weighted ids:", arr.concat(W:neighbors():table(), " "))
local K = csr.fuse(A, B, { k = 2 })
print("top 2 nnz:", K:nnz())
local R = csr.fuse(A, B, { mode = "rrf", rrf_k = 1 })
print("rrf ids:", arr.concat(R:neighbors():table(), " "))
print("rrf scores:", arr.concat(R:values():table(), " "))
return Y:nnz()
]],
    },

    {
      title = "character trigrams as sorted id sets",
      desc = table.concat({
        "tokenize_raw packs character ",
        "trigrams into sorted unique int64 ids with per-document counts, and each document becomes a ",
        "one-row csr whose neighbors are the trigram ids (n_cols stays 0 since the id space is the ",
        "packed ngram space). Because the id vectors are sorted sets, query similarity falls out of ",
        "set_jaccard directly.",
      }),
      code = [[
local tokenizer = require("santoku.learn.tokenizer")
local csr = require("santoku.csr")
local ivec = require("santoku.ivec")
local function tokenize (text)
  local _, indices, values = tokenizer.tokenize_raw({
    texts = { text },
    n_samples = 1,
    ngram_min = 3,
    ngram_max = 3,
    normalize = true,
  })
  return indices, values
end
local function one_row_csr (indices, values)
  return csr.create({
    offsets = ivec.create({ 0, indices:size() }),
    neighbors = indices,
    values = values,
  })
end
local q, qv = tokenize("hello world")
print("trigrams:", q:size())
local X = one_row_csr(q, qv)
print("nnz:", X:nnz())
local a = tokenize("hello world")
local b = tokenize("hello there")
local c = tokenize("completely different")
print("close:", a:set_jaccard(b))
print("far:", a:set_jaccard(c))
return X:nnz()
]],
    },

    {
      title = "spans: labelled intervals per document",
      desc = table.concat({
        "spans stores per-document records with named integer columns, csr-style offsets marking ",
        "document boundaries. Build by declaring columns and pushing records (doc closes each ",
        "document, including empty ones), or wrap existing ivecs zero-copy. sort is a stable per-",
        "document sort by one column, filter drops records in place by 0/1 mask, and docs gathers ",
        "whole documents into a new spans.",
      }),
      code = [[
local spans = require("santoku.spans")
local ivec = require("santoku.ivec")
local arr = require("santoku.array")
local S = spans.create({ "s", "e", "ty" })
S:push(0, 3, 1):push(4, 7, 2):doc()
S:doc()
S:push(2, 5, 1):doc()
print("n:", S:n(), "docs:", S:n_docs())
print("offsets:", arr.concat(S:offsets():table(), " "))
print("starts:", arr.concat(S:col("s"):table(), " "))
print("names:", arr.concat(S:names(), " "))
local W = spans.create({
  offsets = ivec.create({ 0, 2, 2, 3 }),
  s = ivec.create({ 0, 4, 2 }),
  e = ivec.create({ 3, 7, 5 }),
  ty = ivec.create({ 1, 2, 1 }),
})
print("wrapped n:", W:n())
local U = spans.create({ "s", "lab" })
U:push(5, 10):push(1, 20):push(5, 30):doc()
U:push(9, 40):push(2, 50):doc()
U:sort("s")
print("sorted s:", arr.concat(U:col("s"):table(), " "))
print("labels follow:", arr.concat(U:col("lab"):table(), " "))
S:filter(ivec.create({ 1, 0, 1 }))
print("filtered n:", S:n())
local D = W:docs(ivec.create({ 2, 0 }))
print("gathered offsets:", arr.concat(D:offsets():table(), " "))
return S:n()
]],
    },

    {
      title = "spans: candidates and non-overlap selection",
      desc = table.concat({
        "enumerate_subspans expands runs of non-outer spans into candidate intervals up to a maximum ",
        "span count, the generation step for span classification. nms_dp takes k ranked (label, score) ",
        "hypotheses per candidate, weights each by the margin between its top two scores, drops ",
        "candidates whose best label is the reject label, and solves weighted interval scheduling per ",
        "document, returning a keep mask and the chosen class per candidate.",
      }),
      code = [[
local spans = require("santoku.spans")
local ivec = require("santoku.ivec")
local fvec = require("santoku.fvec")
local arr = require("santoku.array")
local S = spans.create({ "s", "e", "ty" })
S:push(0, 2, 1):push(2, 5, 1):push(5, 6, 0):doc()
S:push(0, 3, 0):doc()
local C = S:enumerate_subspans(2, 0)
print("candidates:", C:n())
print("starts:", arr.concat(C:col("s"):table(), " "))
print("ends:", arr.concat(C:col("e"):table(), " "))
local P = spans.create({ "s", "e" })
P:push(0, 2):push(0, 5):push(2, 5):doc()
local labels = ivec.create({ 1, 9, 1, 9, 2, 9 })
local scores = fvec.create({ 0.9, 0.1, 0.6, 0.5, 0.95, 0.05 })
local keep, cls = P:nms_dp(labels, scores, 2, 9)
print("keep:", arr.concat(keep:table(), " "))
print("classes:", arr.concat(cls:table(), " "))
return C:n()
]],
    },

    {
      title = "spans: union, overlay, surfaces",
      desc = table.concat({
        "union merges two span sets per document, deduplicating on the full record tuple. overlay ",
        "layers a list of span sets with list-order priority, keeping an earlier set's span wherever a ",
        "later one would overlap it. surfaces slices the underlying texts by each span's s and e ",
        "columns and interns the resulting strings, returning an id per span plus the unique surface ",
        "list, optionally lowercased. santoku-learn builds its NER metrics on this same metatable.",
      }),
      code = [[
local spans = require("santoku.spans")
local arr = require("santoku.array")
local A = spans.create({ "s", "e", "ty" })
A:push(0, 2, 1):push(2, 5, 1):doc()
local B = spans.create({ "s", "e", "ty" })
B:push(2, 5, 1):push(5, 6, 2):doc()
local U = A:union(B)
print("union starts:", arr.concat(U:col("s"):table(), " "))
print("union types:", arr.concat(U:col("ty"):table(), " "))
local H = spans.create({ "s", "e", "ty" })
H:push(2, 6, 10):doc()
local L = spans.create({ "s", "e", "ty" })
L:push(0, 3, 20):push(6, 9, 21):doc()
local O = spans.overlay({ H, L })
print("overlay starts:", arr.concat(O:col("s"):table(), " "))
print("overlay types:", arr.concat(O:col("ty"):table(), " "))
local S = spans.create({ "s", "e" })
S:push(0, 5):push(6, 11):doc()
S:push(0, 5):doc()
local ids, surfs = S:surfaces({ "Hello World", "HELLO again" }, true)
print("surface ids:", arr.concat(ids:table(), " "))
print("surfaces:", arr.concat(surfs, " "))
return U:n()
]],
    },

    {
      title = "vectors as SQL inputs: carray",
      desc = table.concat({
        "santoku-sqlite's carray virtual table binds a santoku-matrix vector as a table-valued SQL ",
        "input, read zero-copy from the vector's backing store at query time. Mutate the vector and ",
        "the next execution sees the new contents, no serialization in between. The sqlite tab ",
        "shows carray joins inside full statements.",
      }),
      code = [[
local sqlite = require("santoku.sqlite.db")
local sql = require("santoku.sqlite")
local ivec = require("santoku.ivec")
local arr = require("santoku.array")
local db = sql(sqlite.open_memory())
db.exec("create table items (id integer primary key, label text)")
local add = db.runner("insert into items (id, label) values (?, ?)")
add(1, "alpha")
add(2, "beta")
add(3, "gamma")
add(4, "delta")
local pick = db.all(
  "select label from items where id in (select value from carray(?)) order by id")
local ids = ivec.create({ 2, 4 })
print("labels:", arr.concat(pick(ids), ", "))
ids:set(0, 1)
print("after mutation:", arr.concat(pick(ids), ", "))
db.close()
return "ok"
]],
    },

    {
      title = "persist and mmap: vectors on disk",
      desc = table.concat({
        "Every object round-trips to a binary file with persist and a matching load (also on mtx, csr, ",
        "and spans). For arrays bigger than RAM, mmap_create allocates a zeroed file-backed vector, ",
        "mmap_sync flushes, and mmap_open reattaches later; an mmap vector can back an mtx so a large ",
        "encode writes straight to disk through the out= parameter. map (on fvec, dvec and ivec) ",
        "opens a headerless raw file as a private copy-on-write view, so writes never reach the ",
        "file. Needs a real filesystem, so it is shown for reading.",
      }),
      runnable = false,
      code = [[
local ivec = require("santoku.ivec")
local fvec = require("santoku.fvec")
local mtx = require("santoku.mtx")
local arr = require("santoku.array")
local v = ivec.create({ 1, 2, 3, 4 })
v:persist("vec.bin")
local w = ivec.load("vec.bin")
print("roundtrip:", arr.concat(w:table(), " "))
local m = fvec.mmap_create("big.bin", 1000000)
m:set(0, 1.5)
m:mmap_sync()
local r = fvec.mmap_open("big.bin")
print("first:", r:get(0))
local M = mtx.create({ data = r, n_rows = 1000, n_cols = 1000 })
print("disk-backed shape:", M:shape())
local raw = fvec.map("raw.f32")
print("mapped:", raw:size())
return M:shape()
]],
    },

    {
      title = "store: one allocation for many vectors",
      desc = table.concat({
        "A store declares typed vectors up front and backs them all with one zeroed allocation ",
        "at open. With disk = true a native build spills that allocation to an unlinked temp file ",
        "under TMPDIR (/var/tmp by default), checking free space first; under WebAssembly it stays ",
        "in RAM. Views stay empty until open, can't grow, and drop to size 0 at close. Declaring ",
        "after open raises. An mtx can wrap a view, which is how santoku-learn keeps large fold ",
        "codes and tokenizer output off the heap.",
      }),
      runnable = false,
      code = [[
local store = require("santoku.store")
local mtx = require("santoku.mtx")
local s = store.create({ disk = true })
local codes = s:fvec(6)
local ids = s:ivec(2)
print("before open:", codes:size(), ids:size())
s:open()
print("after open:", codes:size(), ids:size())
print("on disk:", s:on_disk(), "bytes:", s:bytes())
local M = mtx.create({ data = codes, n_rows = 2, n_cols = 3 })
codes:set(5, 9)
print("through mtx:", M:get(1, 2))
s:close()
print("after close:", codes:size())
return M:shape()
]],
    },

    {
      title = "hash maps: slot-based khash containers",
      desc = table.concat({
        "iumap and its siblings (iuset, dumap, duset, zumap, cuset) are khash-style containers exposed ",
        "with a slot API: put inserts a key and get looks one up, both returning a slot; setval and val ",
        "write and read the value at a slot; each iterates and destroy frees. ivec:index() builds an ",
        "iumap from value to position, the O(1) reverse lookup used to intern ids. The same containers ",
        "are header-only C templates for extensions.",
      }),
      runnable = false,
      code = [[
local iumap = require("santoku.iumap")
local ivec = require("santoku.ivec")
local m = iumap.create(0)
m:put(10)
m:setval(m:get(10), 100)
m:put(20)
m:setval(m:get(20), 200)
print("value for 10:", m:val(m:get(10)))
local count = 0
for _ in m:each() do
  count = count + 1
end
print("entries:", count)
m:destroy()
local v = ivec.create({ 10, 20, 30 })
local idx = v:index()
print("position of 20:", idx:val(idx:get(20)))
return count
]],
    },

  },

}
