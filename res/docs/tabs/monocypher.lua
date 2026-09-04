return {

  intro = table.concat({
    "santoku-monocypher binds the Monocypher cryptography library, plus a bundled ",
    "SHA-256, SHA-1, and the EFF diceware wordlist, into a single Lua module: ",
    "santoku.monocypher. Rather than exposing the full Monocypher API it ships an ",
    "opinionated identity and key model: a passphrase runs through Argon2id once to ",
    "produce a master secret, and everything else (a public account id, an EdDSA ",
    "signing pair via Monocypher's crypto_eddsa, an XChaCha20-Poly1305 data key, ",
    "domain-separated subkeys) is derived from that master with HMAC-SHA256 under ",
    "fixed labels. On top sit HMAC utilities, constant-time comparison, key ",
    "wrapping, and passphrase quality checks. The same C compiles to native Lua and ",
    "to WebAssembly, so every example on this page runs live in your ",
    "browser. All base64 output is ",
    "standard alphabet with padding: 44 characters for 32-byte values, 88 for ",
    "64-byte signatures. One honesty note: the defaults are 65536 Argon2id blocks ",
    "(64 MiB) and 3 passes, which is deliberately slow; the examples pass 1024 and ",
    "1 so the page stays snappy. Never use the reduced parameters in production.",
  }),

  examples = {

    {
      title = "generate and validate a passphrase",
      desc = table.concat({
        "generate rolls six words from the EFF large wordlist using rejection-sampled ",
        "system randomness. validate tokenizes on whitespace, lowercases, and requires ",
        "at least six words that all appear on the list, so ordinary passwords and ",
        "short diceware phrases are rejected.",
      }),
      code = [[
local crypto = require("santoku.monocypher")
local secret = crypto.generate()
print("passphrase:", secret)
print("valid:", crypto.validate(secret))
print("case-insensitive:", crypto.validate(secret:upper()))
print("five words:", crypto.validate("abacus abdomen abdominal abide abiding"))
print("not on the list:", crypto.validate("hunter2 hunter2 hunter2 hunter2 hunter2 hunter2"))
return crypto.validate(secret)
]],
    },

    {
      title = "phrase_audit: the weak-pattern taxonomy",
      desc = table.concat({
        "phrase_audit flags human-picked phrases that a dice roll would almost never ",
        "produce. It returns one of four strings, checked in priority order: ",
        "repeated_word, same_letter (all words share a first letter), sequential ",
        "(first letters step through the alphabet), alphabetical (fully sorted either ",
        "direction), or nil for a healthy phrase.",
      }),
      code = [[
local crypto = require("santoku.monocypher")
print("repeated:", crypto.phrase_audit("dog dog canyon ethics sushi hazelnut"))
print("same letter:", crypto.phrase_audit("sand sushi salad sixth sizzle serving"))
print("sequential:", crypto.phrase_audit("apple bat crab dove echo flag"))
print("sorted:", crypto.phrase_audit("apple canyon ethics hazelnut opera trend"))
print("reverse sorted:", crypto.phrase_audit("trend opera hazelnut ethics canyon apple"))
print("random:", crypto.phrase_audit("canyon ethics sushi hazelnut opera trend"))
return crypto.phrase_audit("canyon ethics sushi hazelnut opera trend") == nil
]],
    },

    {
      title = "derive_identity: Argon2id into an identity",
      desc = table.concat({
        "One Argon2id run over the passphrase (fixed salt, memory-hard) yields a ",
        "master secret, and from it a public sub (the account id) and an EdDSA ",
        "keypair, each under its own HMAC label. The same passphrase always produces ",
        "the same identity on any machine. Parameters below 8 blocks or 1 pass are ",
        "rejected; err.pcall unwraps the structured error cleanly.",
      }),
      code = [[
local crypto = require("santoku.monocypher")
local err = require("santoku.error")
local id = crypto.derive_identity("canyon ethics sushi hazelnut opera trend", 1024, 1)
print("sub:", id:sub())
print("public key:", id:public_key())
local again = crypto.derive_identity("canyon ethics sushi hazelnut opera trend", 1024, 1)
print("deterministic:", id:sub() == again:sub())
local exported = id:export()
print("argon2:", exported.argon2_memory, exported.argon2_passes)
print("bad params:", err.pcall(crypto.derive_identity, "x", 4, 1))
return id:public_key()
]],
    },

    {
      title = "detached EdDSA signatures",
      desc = table.concat({
        "sign produces a detached 64-byte signature, base64 encoded to 88 ",
        "characters. EdDSA is deterministic: the same identity and message always ",
        "give the same bytes, and any change to the message changes the signature. ",
        "The module exposes no bare verify for these; verification is done through ",
        "verify_request over the sub:body framing shown next.",
      }),
      code = [[
local crypto = require("santoku.monocypher")
local id = crypto.derive_identity("secret one", 1024, 1)
local sig = id:sign("release-v1.2.0")
print("signature:", sig)
print("length:", #sig)
print("deterministic:", id:sign("release-v1.2.0") == sig)
print("message-bound:", id:sign("release-v1.2.1") ~= sig)
return #sig
]],
    },

    {
      title = "sign_request and verify_request",
      desc = table.concat({
        "sign_request signs sub .. \":\" .. body, binding a request to the account ",
        "that sent it; verify_request checks it given only public values, so a ",
        "server can hold no passwords, just public ",
        "keys, with every mutation arriving signed. Failures, including undecodable ",
        "signatures, come back as nil plus invalid_signature.",
      }),
      code = [[
local crypto = require("santoku.monocypher")
local id = crypto.derive_identity("secret one", 1024, 1)
local body = "PUT:/items:42"
local sig = id:sign_request(body)
print("ok:", crypto.verify_request(id:public_key(), sig, id:sub(), body))
print("tampered body:", crypto.verify_request(id:public_key(), sig, id:sub(), "PUT:/items:43"))
local other = crypto.derive_identity("secret two", 1024, 1)
print("wrong signer:", crypto.verify_request(id:public_key(), other:sign_request(body), id:sub(), body))
print("garbage sig:", crypto.verify_request(id:public_key(), "AAAA", id:sub(), body))
return crypto.verify_request(id:public_key(), sig, id:sub(), body)
]],
    },

    {
      title = "derive_key and the AEAD round trip",
      desc = table.concat({
        "derive_key turns the same passphrase into an XChaCha20-Poly1305 data key ",
        "(reusing the identity's cached master, so Argon2id does not run again). ",
        "encrypt returns a self-contained base64 blob; decrypt authenticates before ",
        "returning a single byte, so a wrong key yields nil and an error string, ",
        "never garbage plaintext.",
      }),
      code = [[
local crypto = require("santoku.monocypher")
local id = crypto.derive_identity("secret one", 1024, 1)
local key = crypto.derive_key("secret one", id)
local ct = key:encrypt("attack at dawn")
print("ciphertext:", ct)
print("plaintext:", key:decrypt(ct))
local id2 = crypto.derive_identity("secret two", 1024, 1)
local other = crypto.derive_key("secret two", id2)
print("wrong key:", other:decrypt(ct))
return key:decrypt(ct)
]],
    },

    {
      title = "fresh nonces every time",
      desc = table.concat({
        "Each encrypt call draws a random 24-byte XChaCha20 nonce, so encrypting ",
        "the same plaintext twice under the same key produces unrelated ciphertexts ",
        "that both decrypt fine. Equal ciphertexts never leak equal contents.",
      }),
      code = [[
local crypto = require("santoku.monocypher")
local id = crypto.derive_identity("secret one", 1024, 1)
local key = crypto.derive_key("secret one", id)
local a = key:encrypt("same message")
local b = key:encrypt("same message")
print("distinct ciphertexts:", a ~= b)
print("a decrypts:", key:decrypt(a))
print("b decrypts:", key:decrypt(b))
return a ~= b
]],
    },

    {
      title = "anatomy of a ciphertext",
      desc = table.concat({
        "The blob layout is one version byte (1 plain, 2 AAD-bound), the 24-byte ",
        "nonce, the ciphertext (same length as the plaintext), and the 16-byte ",
        "Poly1305 tag, all base64 encoded. santoku.string's codec functions let you ",
        "take it apart and look.",
      }),
      code = [[
local crypto = require("santoku.monocypher")
local str = require("santoku.string")
local id = crypto.derive_identity("secret one", 1024, 1)
local key = crypto.derive_key("secret one", id)
local pt = "attack at dawn"
local raw = str.from_base64(key:encrypt(pt))
print("version:", raw:byte(1))
print("total bytes:", #raw, "= 1 + 24 + " .. #pt .. " + 16")
print("nonce:", str.to_hex(raw:sub(2, 25)))
print("tag:", str.to_hex(raw:sub(#raw - 15)))
print("aad version:", str.from_base64(key:encrypt(pt, "ctx")):byte(1))
return #raw == 1 + 24 + #pt + 16
]],
    },

    {
      title = "AAD-bound ciphertext",
      desc = table.concat({
        "Passing associated data to encrypt binds the blob to a context string that ",
        "is authenticated but not stored inside it. Pin each encrypted record to its ",
        "id and clock this way, so a valid blob replayed under a ",
        "different context refuses to open.",
      }),
      code = [[
local crypto = require("santoku.monocypher")
local id = crypto.derive_identity("secret one", 1024, 1)
local key = crypto.derive_key("secret one", id)
local ct = key:encrypt("hello", "sub:id-1")
print("right aad:", key:decrypt(ct, "sub:id-1"))
print("wrong aad:", key:decrypt(ct, "sub:id-2"))
print("no aad:", key:decrypt(ct))
return key:decrypt(ct, "sub:id-1")
]],
    },

    {
      title = "the decrypt failure taxonomy",
      desc = table.concat({
        "decrypt never raises; it returns nil plus one of three strings. ",
        "unsupported version covers truncated blobs and unknown version bytes, aad ",
        "mismatch means the caller's AAD presence disagrees with the blob's version ",
        "byte, and decryption failed means the Poly1305 tag rejected the key, the ",
        "AAD value, or a flipped ciphertext bit.",
      }),
      code = [[
local crypto = require("santoku.monocypher")
local str = require("santoku.string")
local id = crypto.derive_identity("secret one", 1024, 1)
local key = crypto.derive_key("secret one", id)
print("truncated:", key:decrypt("AA"))
print("unknown version:", key:decrypt(str.to_base64(string.char(3) .. string.rep("x", 40))))
local ct = key:encrypt("hello", "sub:1")
print("missing aad:", key:decrypt(ct))
print("wrong aad:", key:decrypt(ct, "sub:2"))
local raw = str.from_base64(key:encrypt("hello"))
local flipped = raw:sub(1, 29) .. string.char((raw:byte(30) + 1) % 256) .. raw:sub(31)
print("bit flipped:", key:decrypt(str.to_base64(flipped)))
return select(2, key:decrypt(ct, "sub:2"))
]],
    },

    {
      title = "domain-separated subkeys",
      desc = table.concat({
        "derive spawns a deterministic subkey per label (HMAC of the parent key ",
        "over the label), and bytes exposes the raw 32-byte material for handing to ",
        "other systems, such as feeding a subkey's bytes to an encrypting SQLite ",
        "VFS. Subkeys never decrypt each other's output.",
      }),
      code = [[
local crypto = require("santoku.monocypher")
local id = crypto.derive_identity("secret one", 1024, 1)
local key = crypto.derive_key("secret one", id)
local dbkey = key:derive("db")
local searchkey = key:derive("search")
print("deterministic:", dbkey:bytes() == key:derive("db"):bytes())
print("separated:", dbkey:bytes() ~= searchkey:bytes())
print("distinct from parent:", dbkey:bytes() ~= key:bytes())
print("raw length:", #dbkey:bytes())
local ct = dbkey:encrypt("row data")
print("cross-domain decrypt:", searchkey:decrypt(ct))
return dbkey:decrypt(ct)
]],
    },

    {
      title = "key:hmac, a keyed fingerprint",
      desc = table.concat({
        "key:hmac(msg) is exactly hmac_sha256 keyed by the key's raw bytes, ",
        "returned as 64 hex characters: a deterministic, key-private fingerprint ",
        "for naming files or rows without revealing what they are.",
      }),
      code = [[
local crypto = require("santoku.monocypher")
local id = crypto.derive_identity("secret one", 1024, 1)
local key = crypto.derive_key("secret one", id)
local h = key:hmac("doc:42")
print("keyed hex:", h)
print("equals module fn:", h == crypto.hmac_sha256(key:bytes(), "doc:42"))
print("stable:", key:hmac("doc:42") == h)
print("input-bound:", key:hmac("doc:43") ~= h)
return #h
]],
    },

    {
      title = "hmac_sha256, hmac_sha1, const_eq",
      desc = table.concat({
        "The standalone HMACs take any key string and return lowercase hex. The ",
        "SHA-1 variant exists for legacy protocols (TOTP below) and matches the RFC ",
        "2202 test vectors. const_eq compares strings in constant time, returning ",
        "false immediately only on length mismatch: always use it for comparing ",
        "secrets, never ==.",
      }),
      code = [[
local crypto = require("santoku.monocypher")
local mac = crypto.hmac_sha256("server-pepper", "user@example.com")
print("hmac_sha256:", mac)
print("hex length:", #mac)
print("rfc 2202:", crypto.hmac_sha1("Jefe", "what do ya want for nothing?"))
print("equal:", crypto.const_eq(mac, crypto.hmac_sha256("server-pepper", "user@example.com")))
print("different key:", crypto.const_eq(mac, crypto.hmac_sha256("other-pepper", "user@example.com")))
print("length mismatch:", crypto.const_eq(mac, mac:sub(1, 32)))
return crypto.const_eq(mac, crypto.hmac_sha256("server-pepper", "user@example.com"))
]],
    },

    {
      title = "pattern: webhook signature verification",
      desc = table.concat({
        "The Stripe-style webhook check is three lines: recompute the HMAC over ",
        "timestamp.payload with the endpoint secret and compare with const_eq. The ",
        "same shape works for ",
        "any HMAC-signed callback.",
      }),
      code = [[
local crypto = require("santoku.monocypher")
local whsec = "whsec_demo_secret"
local payload = '1724000000.{"id":"evt_1","type":"invoice.paid"}'
local signature = crypto.hmac_sha256(whsec, payload)
local function verify (sig, body)
  return crypto.const_eq(sig, crypto.hmac_sha256(whsec, body))
end
print("genuine:", verify(signature, payload))
print("tampered:", verify(signature, payload .. "x"))
print("forged:", verify(string.rep("0", 64), payload))
return verify(signature, payload)
]],
    },

    {
      title = "pattern: a complete TOTP generator",
      desc = table.concat({
        "hmac_sha1 is enough to implement RFC 6238 time-based one-time codes in a ",
        "dozen lines: big-endian counter, dynamic truncation from the last hex ",
        "nibble, modulo 10^digits. ",
        "For the RFC test key at t=59 this prints the published vector 94287082.",
      }),
      code = [[
local crypto = require("santoku.monocypher")
local function totp (key, now, period, digits)
  local counter = math.floor(now / period)
  local msg = {}
  for i = 8, 1, -1 do
    msg[i] = string.char(counter % 256)
    counter = math.floor(counter / 256)
  end
  local hex = crypto.hmac_sha1(key, table.concat(msg))
  local offset = tonumber(hex:sub(40, 40), 16)
  local v = tonumber(hex:sub(offset * 2 + 1, offset * 2 + 8), 16) % 0x80000000
  local code = tostring(math.floor(v % 10 ^ digits))
  while #code < digits do code = "0" .. code end
  return code
end
print("rfc 6238 t=59:", totp("12345678901234567890", 59, 30, 8))
print("rfc 6238 t=1111111109:", totp("12345678901234567890", 1111111109, 30, 8))
print("6-digit now-style:", totp("12345678901234567890", 1724000000, 30, 6))
return totp("12345678901234567890", 59, 30, 8)
]],
    },

    {
      title = "hash_ivec: bulk keyed hashing",
      desc = table.concat({
        "hash_ivec HMACs every int64 in a santoku.ivec in place, replacing each ",
        "element with the leading 8 bytes of its keyed hash, and returns the same ",
        "vector. It exists to blind whole token-id vectors (search indexes) in one ",
        "C-side pass: deterministic per key, unlinkable across keys.",
      }),
      code = [[
local crypto = require("santoku.monocypher")
local ivec = require("santoku.ivec")
local id = crypto.derive_identity("secret one", 1024, 1)
local key = crypto.derive_key("secret one", id)
local tokens = ivec.create({ 101, 202, 303 })
local hashed = key:hash_ivec(tokens)
print("same object:", hashed == tokens)
local again = ivec.create({ 101, 202, 303 })
key:hash_ivec(again)
print("deterministic:", tokens:get(0) == again:get(0))
local other = key:derive("other"):hash_ivec(ivec.create({ 101, 202, 303 }))
print("key-dependent:", tokens:get(0) ~= other:get(0))
return tokens:size()
]],
    },

    {
      title = "export and import",
      desc = table.concat({
        "export serializes an identity to a plain table (sub, signing_key, ",
        "public_key, Argon2 parameters) and a key to one base64 string, ready for ",
        "JSON or sessionStorage. Imported identities sign identically, and because ",
        "the Argon2 parameters travel along, derive_key on an imported identity ",
        "re-runs Argon2id with the original settings and lands on the same key.",
      }),
      code = [[
local crypto = require("santoku.monocypher")
local id = crypto.derive_identity("secret one", 1024, 1)
local key = crypto.derive_key("secret one", id)
local blob = id:export()
print("fields:", blob.sub == id:sub(), blob.public_key == id:public_key())
print("params travel:", blob.argon2_memory, blob.argon2_passes)
local id2 = crypto.import_identity(blob)
print("signs identically:", id2:sign("x") == id:sign("x"))
local key2 = crypto.import_key(key:export())
print("key roundtrip:", key2:bytes() == key:bytes())
local rekeyed = crypto.derive_key("secret one", id2)
print("re-derived from import:", rekeyed:bytes() == key:bytes())
return key2:export()
]],
    },

    {
      title = "wrap_key and unwrap_key",
      desc = table.concat({
        "wrap_key seals a key's 32 bytes under an external 32-byte secret using the ",
        "same AEAD envelope: the primitive for handing custody to something outside ",
        "the passphrase, like a hardware-held secret that restores the data key on ",
        "biometric unlock. Wrong wrap bytes fail authentication, wrong sizes are ",
        "rejected outright, and each wrap uses a fresh nonce.",
      }),
      code = [[
local crypto = require("santoku.monocypher")
local id = crypto.derive_identity("secret one", 1024, 1)
local key = crypto.derive_key("secret one", id)
local wrap = string.rep(string.char(0x42), 32)
local wrapped = crypto.wrap_key(key, wrap)
print("wrapped:", wrapped)
local unwrapped = crypto.unwrap_key(wrapped, wrap)
print("roundtrip:", unwrapped:bytes() == key:bytes())
print("wrong wrap:", crypto.unwrap_key(wrapped, string.rep(string.char(0x43), 32)))
print("bad size:", crypto.wrap_key(key, "tooshort"))
print("fresh nonce:", crypto.wrap_key(key, wrap) ~= wrapped)
return unwrapped:bytes() == key:bytes()
]],
    },

    {
      title = "capstone: a tiny end-to-end vault",
      desc = table.concat({
        "Everything together: one passphrase, one Argon2id run, a db subkey, each ",
        "record AEAD-sealed with its own id as AAD so blobs cannot be shuffled, and ",
        "a signed manifest the server can verify without ever seeing a key.",
      }),
      code = [[
local crypto = require("santoku.monocypher")
local secret = "canyon ethics sushi hazelnut opera trend"
local id = crypto.derive_identity(secret, 1024, 1)
local key = crypto.derive_key(secret, id)
local dbkey = key:derive("db")
local rows = { ["note:1"] = "buy milk", ["note:2"] = "renew passport" }
local sealed, ids = {}, {}
for rid, text in pairs(rows) do
  sealed[rid] = dbkey:encrypt(text, rid)
  ids[#ids + 1] = rid
end
table.sort(ids)
local manifest = table.concat(ids, ";")
local sig = id:sign_request(manifest)
print("manifest ok:", crypto.verify_request(id:public_key(), sig, id:sub(), manifest))
print("note:1:", dbkey:decrypt(sealed["note:1"], "note:1"))
print("shuffled blob:", dbkey:decrypt(sealed["note:1"], "note:2"))
return dbkey:decrypt(sealed["note:2"], "note:2")
]],
    },

  },

}
