return {

  intro = table.concat({
    "santoku-imap is an IMAP4rev1 client covering the subset a mail application ",
    "actually issues: LOGIN, SELECT and EXAMINE, UID SEARCH, UID FETCH (including ",
    "Gmail's X-GM-THRID and X-GM-MSGID, header fields, partial body ranges and ",
    "BODYSTRUCTURE), UID STORE, EXPUNGE, APPEND, and LIST with SPECIAL-USE ",
    "detection. The core owns the protocol and nothing else: it takes an injected ",
    "stream driver, so the same client code runs over LuaSocket, over node tls in a ",
    "wasm build, and over ngx cosockets under OpenResty. Around it sit four ",
    "companion modules: headers for parsing and RFC 2047 decoding, bodystructure for ",
    "locating the text part without downloading the message, mime for turning a ",
    "fetched body into plain paragraphs and for building a draft, and thread for ",
    "assembling a forest from References with an X-GM-THRID fallback. Everything ",
    "here needs a socket and a mailbox, so the examples are shown for reading. They ",
    "run in order: connecting, the command set, the driver contract, what a fetch ",
    "returns, headers, bodystructure, message text, threading, and appending a ",
    "draft.",
  }),

  examples = {

    {
      title = "Connecting: the module is a function of a driver",
      desc = table.concat({
        "Requiring santoku.imap gives a function, not a client. Apply it to a stream ",
        "driver and it returns a library whose connect(opts, done) dials the server ",
        "and calls done(ok, client) once the greeting has arrived. A greeting of ",
        "* BYE settles with ok false and the server's reason instead. Every command ",
        "on the returned client is callback-shaped, and the connection is closed by ",
        "logout for the polite path or close for the abrupt one.",
      }),
      runnable = false,
      code = [[
local imap = require("santoku.imap")(require("santoku.socket.stream"))
imap.connect({
  host = "imap.gmail.com",
  port = 993,
  step_ms = 500,
  timeout_ms = 30000,
}, function (ok, client)
  if not ok then
    return print("connect failed:", client)
  end
  client.login("me@example.com", "app-password", function (okl, res)
    if not okl then
      return print("login refused:", res.status, res.text)
    end
    client.logout(function () end)
  end)
end)
return true
]],
    },

    {
      title = "The command set",
      desc = table.concat({
        "Commands are tagged and queued: one is in flight at a time and the rest ",
        "wait, so ordering is whatever order you issue them in. Callbacks that ",
        "parse hand back the parsed value (examine gives exists, uidvalidity and ",
        "uidnext; search gives an array of numeric uids; fetch gives one table per ",
        "message; list gives name and attrs). The rest hand back the raw result ",
        "table, { status, text, untagged }, where status is the IMAP completion ",
        "word and untagged holds the server's untagged lines for that command. ok ",
        "is status == \"OK\", so a NO or BAD arrives as ok false with the server's ",
        "text rather than as an error.",
      }),
      runnable = false,
      code = [[
client.login(user, pass, cb)                  -- cb(ok, res)
client.examine(mailbox, cb)                   -- read-only select
client.select(mailbox, cb)                    -- cb(ok, { exists, uidvalidity, uidnext })
client.search(criteria, cb)                   -- cb(ok, { uid, uid, ... })
client.fetch(set, items, cb)                  -- cb(ok, { msg, msg, ... })
client.store(set, flags, cb)                  -- UID STORE, flags verbatim
client.expunge(cb)
client.append(mailbox, flags, message, cb)    -- flags may be nil
client.list(cb)                               -- cb(ok, { { name, attrs }, ... })
client.drafts_mailbox(cb)                     -- cb(ok, name) via SPECIAL-USE
client.logout(cb)
client.close()                                -- drop the socket, no LOGOUT
]],
    },

    {
      title = "The driver contract",
      desc = table.concat({
        "A driver is one function, connect(opts, done), where opts carries host, ",
        "port, a data callback and a closed callback, and done receives ok and a ",
        "conn exposing write and close. Inbound bytes are pushed: data is called ",
        "with whatever fragmentation the network produced, and the core reassembles ",
        "CRLF lines and IMAP literals from it. A driver on a blocking runtime with ",
        "no event loop additionally exposes step(ms), one bounded read delivered ",
        "through the same data callback; the core detects step and pumps internally ",
        "during connect and each command, so a consumer writes the same callbacks ",
        "either way and only the timing differs, synchronous on a pull driver and ",
        "event-driven on a push driver. step_ms sizes each pump and timeout_ms ",
        "bounds the wait: a command that goes timeout_ms with no bytes from the ",
        "server fails and the connection is closed. Ready-made drivers are ",
        "santoku.socket.stream (LuaSocket and LuaSec, pull), santoku.web.stream ",
        "(node tls under wasm, push) and santoku.resty.stream (ngx cosockets, ",
        "push); anything implementing the contract works.",
      }),
      runnable = false,
      code = [[
local driver = {}
driver.connect = function (opts, done)
  -- opts.host, opts.port
  -- opts.data(chunk)    every byte the socket produces, any fragmentation
  -- opts.closed(err)    once, when the connection is gone
  local conn = {
    write = function (data) end,
    close = function () end,
    step = function (ms) end,   -- pull drivers only; returns true, "timeout"
  }
  done(true, conn)
  return conn
end
local imap = require("santoku.imap")(driver)
]],
    },

    {
      title = "What a fetch returns",
      desc = table.concat({
        "fetch takes the uid set and the item list as strings and passes them ",
        "through, so anything the server understands is available. Each message ",
        "comes back as a table holding only the items present in the response: uid, ",
        "thrid and msgid from the Gmail extensions, header from a HEADER.FIELDS ",
        "section, body from a BODY[TEXT] section (a partial range like <0.65536> is ",
        "recognised and stripped), and structure from BODYSTRUCTURE. Literals are ",
        "reassembled before parsing, so a header arriving as {512} followed by ",
        "512 bytes is indistinguishable from a quoted string. Use BODY.PEEK rather ",
        "than BODY unless you want the message marked read.",
      }),
      runnable = false,
      code = [[
local arr = require("santoku.array")
client.search("UID 1:* SINCE 1-Jan-2026", function (ok, uids)
  client.fetch(arr.concat(uids, ","),
    "UID X-GM-THRID BODY.PEEK[HEADER.FIELDS (SUBJECT FROM DATE MESSAGE-ID REFERENCES)]",
    function (ok2, msgs)
      for i = 1, #msgs do
        print(msgs[i].uid, msgs[i].thrid, #msgs[i].header)
      end
    end)
end)

client.fetch("5", "UID BODY.PEEK[TEXT]<0.65536>", function (ok, msgs)
  print(msgs[1].body)
end)
]],
    },

    {
      title = "headers: parse, decode, ids, address",
      desc = table.concat({
        "santoku.imap.headers turns the raw header block from a fetch into a table ",
        "keyed by lowercased field name. Folded continuation lines are joined ",
        "first, and a repeated field keeps its first occurrence. decode applies RFC ",
        "2047 to an encoded-word string, handling both B and Q encodings and ",
        "stitching adjacent encoded words that a mailer split across a fold; ",
        "undecodable base64 falls through as the raw data rather than raising. ids ",
        "pulls the angle-bracketed identifiers out of a References or In-Reply-To ",
        "value in order, and address splits a From or To value into the bare ",
        "address and the display name, decoding the name on the way.",
      }),
      runnable = false,
      code = [[
local headers = require("santoku.imap.headers")
local h = headers.parse(msg.header)
print(h.subject, h["message-id"])
print(headers.decode(h.subject))
local addr, name = headers.address(h.from)
print(addr, name)
local refs = headers.ids(h.references)
print(#refs, refs[1])
]],
    },

    {
      title = "bodystructure: find the text part before downloading it",
      desc = table.concat({
        "A BODYSTRUCTURE fetch costs one round trip and no body bytes. The parsed ",
        "structure is a tree: leaves carry type, subtype, params, encoding and ",
        "size, and a multipart node carries subtype and parts. text_part walks it ",
        "for the first text/plain leaf and falls back to the first text/html one, ",
        "returning the IMAP part number along with the subtype, encoding, charset ",
        "and size. That part number is what goes in the next fetch, so a ",
        "multi-megabyte message with attachments costs only the few kilobytes of ",
        "text you wanted.",
      }),
      runnable = false,
      code = [[
local bs = require("santoku.imap.bodystructure")
client.fetch("5", "UID BODYSTRUCTURE", function (ok, msgs)
  local part = bs.text_part(msgs[1].structure)
  print(part.part, part.subtype, part.encoding, part.charset, part.size)
  client.fetch("5", "BODY.PEEK[" .. part.part .. "]", function (ok2, got)
    print(#got[1].body)
  end)
end)
]],
    },

    {
      title = "mime: fetched bytes to readable paragraphs",
      desc = table.concat({
        "extract_text(content_type, content_transfer_encoding, raw) returns plain ",
        "text or nil. It decodes base64 and quoted-printable, descends multipart ",
        "bodies up to four levels preferring text/plain over text/html, and strips ",
        "tags and the common entities out of HTML when plain text is absent. It ",
        "never raises: a malformed body returns nil. paragraphs then collapses that ",
        "text into an array of whitespace-normalised blocks, bounded on three axes ",
        "at once (max_len 2000 bytes per block, max_count 64 blocks, max_total ",
        "16384 bytes overall) and appending a literal [truncated] block when any ",
        "bound bites. Cuts land on a UTF-8 boundary rather than mid-sequence.",
      }),
      runnable = false,
      code = [[
local mime = require("santoku.imap.mime")
local headers = require("santoku.imap.headers")
local h = headers.parse(msg.header)
local text = mime.extract_text(h["content-type"], h["content-transfer-encoding"], msg.body)
local blocks = mime.paragraphs(text, { max_count = 8, max_len = 400 })
for i = 1, #blocks do
  print(i, blocks[i])
end
]],
    },

    {
      title = "thread: a forest from References, with a Gmail fallback",
      desc = table.concat({
        "forest takes an array of messages carrying msgid, refs, thrid and uid, and ",
        "returns root nodes of { msg, children }. Parenting walks each message's ",
        "refs from the nearest ancestor outward and takes the first one present in ",
        "the batch, which is the standard rule and the one that survives a mailer ",
        "rewriting the middle of a chain. Cycles introduced by duplicate or forged ",
        "Message-IDs are detected and broken rather than looping. Messages left ",
        "without a parent are then grouped by thrid, with the lowest uid becoming ",
        "the root of its group, so a Gmail conversation still comes back as one ",
        "tree when the References headers are missing entirely. Children are sorted ",
        "by uid at every level.",
      }),
      runnable = false,
      code = [[
local thread = require("santoku.imap.thread")
local headers = require("santoku.imap.headers")
local str = require("santoku.string")
local msgs = {}
for i = 1, #fetched do
  local h = headers.parse(fetched[i].header)
  msgs[i] = {
    uid = fetched[i].uid,
    thrid = fetched[i].thrid,
    msgid = h["message-id"] and headers.ids(h["message-id"])[1],
    refs = headers.ids(h.references),
    subject = headers.decode(h.subject),
  }
end
local roots = thread.forest(msgs)
local function show (node, depth)
  print(str.rep("  ", depth) .. node.msg.subject)
  for i = 1, #node.children do
    show(node.children[i], depth + 1)
  end
end
for i = 1, #roots do
  show(roots[i], 0)
end
]],
    },

    {
      title = "Appending a draft",
      desc = table.concat({
        "mime.build assembles an RFC 5322 message from a table: From, To, Subject, ",
        "Date, Message-ID, In-Reply-To and References, then a text/plain utf-8 body ",
        "made of the paragraphs array joined by blank lines, with line endings ",
        "normalised to CRLF. A subject outside printable ASCII is wrapped as a ",
        "base64 encoded word, which is what encode_word does on its own if you need ",
        "it elsewhere. append sends it as an IMAP literal, so the byte count is ",
        "computed for you and the continuation handshake is handled internally. ",
        "drafts_mailbox finds the target by SPECIAL-USE rather than by guessing at ",
        "a name, which differs across servers and locales.",
      }),
      runnable = false,
      code = [[
local mime = require("santoku.imap.mime")
local message = mime.build({
  from = "me@example.com",
  to = "you@example.com",
  subject = "Re: the proposal",
  date = "Thu, 18 Sep 2026 09:00:00 +0000",
  message_id = "draft-1@example.com",
  in_reply_to = "abc@example.com",
  references = { "abc@example.com" },
  paragraphs = { "Looks good.", "One question about the timeline." },
})
client.drafts_mailbox(function (ok, box)
  if not ok then
    return print("no drafts mailbox:", box.text)
  end
  client.append(box, "\\Draft", message, function (oka, res)
    print(oka, res.status, res.text)
  end)
end)
]],
    },

  },

}
