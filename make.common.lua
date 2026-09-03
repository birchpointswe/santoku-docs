local fs = require("santoku.fs")
local arr = require("santoku.array")
local sys = require("santoku.system")
local env = require("santoku.env")
local build = require("santoku.make.build")
local vendor = require("santoku.make.vendor")
local lp = require("santoku.lpeg")

local icon_sizes = { 192, 512, 1024 }
local apple_icon_size = 180
local icon_variants = {
  { suffix = "", svg = "res/icons/icon.svg", purpose = "any" },
  { suffix = "-maskable", svg = "res/icons/maskable.svg", purpose = "maskable" },
}

local public_files = { "index.css", "favicon.svg", "apple-touch-icon.png" }
for _, variant in ipairs(icon_variants) do
  for _, size in ipairs(icon_sizes) do
    arr.push(public_files, "icon" .. variant.suffix .. "-" .. size .. ".png")
  end
end

local function pusher (out)
  return function (...)
    for i = 1, select("#", ...) do
      out[#out + 1] = (select(i, ...))
    end
  end
end

local scaffold_langs = {
  lua = "lua", c = "c", h = "c", html = "markup", js = "javascript",
  css = "css", sql = "sql", conf = "nginx", json = "json",
}

local scaffold_specs = {
  {
    key = "lib",
    name = "my-lib",
    mod = "my_lib",
    create = "create_lib",
    files = {
      "make.lua",
      "lib/%m.tk.lua",
      "lib/%m/capi.c",
      "bin/%s.lua",
      "test/spec/%m.lua",
      "res/migrations/0.0.1.sql",
    },
  },
  {
    key = "web",
    name = "my-app",
    create = "create_web",
    files = {
      "make.lua",
      "client/bin/bundle.lua",
      "client/lib/%s/main.lua",
      "client/lib/%s/db.tk.lua",
      "client/static/index.html",
      "client/res/pre.tk.js",
      "server/nginx.tk.conf",
      "server/lib/%s/web/init.lua",
      "server/lib/%s/web/sync.lua",
      "res/client/migrations/0.0.1.sql",
    },
  },
  {
    key = "api",
    name = "my-api",
    mod = "my_api",
    create = "create_api",
    files = {
      "make.lua",
      "res/server/migrations/0.0.1.sql",
      "server/lib/%m/db.tk.lua",
      "server/lib/%m/web/init.lua",
      "server/lib/%m/web/init_worker.lua",
      "server/lib/%m/web/items.lua",
      "server/nginx.tk.conf",
      "server/test/spec/%m.lua",
    },
  },
}

local prism_components = {
  { name = "core", sha256 = "6caad316dd991f24f8004e0b9c19c055cb5829ff65e973fbee406f96d81b8e7e" },
  { name = "markup", sha256 = "879fc9d256c352d980e053857fa707330853b8bfb67ce284ea661a24dec5756e" },
  { name = "clike", sha256 = "c76ba4e240932bdc75546be30e550f5ba5e13815ff71511c76e9e27ac3072444" },
  { name = "c", sha256 = "9e05cf21207bff46afbf80cb8f43bb58bc4a4a87b68f28bc0470342f69345209" },
  { name = "javascript", sha256 = "0345ea83e12b7b974e953c79a64dea35a40308309449db70b82020fb688ac321" },
  { name = "sql", sha256 = "3fc5f8ce69950ec73adc972f061df42aaea78faa4864709134ea2adc083f3a33" },
  { name = "nginx", sha256 = "7cfd310f8cb3a53f2c4c71c371c0701a0b2d8aef82298d890d696448df5625ed" },
  { name = "lua", sha256 = "f6ca280a77564667cc1006e59e31e338b01eee0ef840ae02a9bd5a0fc5ea4553" },
  { name = "bash", sha256 = "6260814110e5182f2956e3bd257429548d9dbf2a9b66a63719b26cf9fac966a7" },
}

local prism_pre_js = {}
for _, p in ipairs(prism_components) do
  prism_pre_js[#prism_pre_js + 1] = "--pre-js"
  prism_pre_js[#prism_pre_js + 1] = "../../../vendor/prism-" .. p.name .. ".min.js"
end

local function scaffold_lang (path)
  local ext = string.match(path, "%.([^.]+)$")
  return ext and scaffold_langs[string.lower(ext)] or "text"
end

local function generate_scaffold (out_path, work_dir)
  local project = require("santoku.make.project")
  local out = {}
  local push = pusher(out)
  push("return {\n")
  for _, spec in ipairs(scaffold_specs) do
    local dir = fs.join(work_dir, "scaffold-" .. spec.key)
    sys.execute({ "rm", "-rf", dir })
    project[spec.create]({ name = spec.name, dir = dir, git = false, quiet = true })
    local mod = spec.mod or spec.name
    local subs = { ["%s"] = spec.name, ["%m"] = mod }
    push("  ", spec.key, " = {\n")
    push("    name = ", string.format("%q", spec.name), ",\n")
    push("    mod = ", string.format("%q", mod), ",\n")
    push("    files = {\n")
    for _, pattern in ipairs(spec.files) do
      local rel = string.gsub(pattern, "%%[sm]", subs)
      local fp = fs.join(dir, rel)
      if not fs.exists(fp) then
        error("scaffold file missing from the " .. spec.key ..
          " boilerplate: " .. rel .. " (update scaffold_specs in make.common.lua)")
      end
      push("      { path = ", string.format("%q", rel), ",\n")
      push("        lang = ", string.format("%q", scaffold_lang(rel)), ",\n")
      push("        code = ", string.format("%q", fs.readfile(fp)), " },\n")
    end
    push("    },\n")
    local all = {}
    for fp in fs.files(dir, true) do
      all[#all + 1] = string.sub(fp, #dir + 2)
    end
    table.sort(all)
    push("    all = {\n")
    for _, rel in ipairs(all) do
      push("      ", string.format("%q", rel), ",\n")
    end
    push("    },\n  },\n")
    sys.execute({ "rm", "-rf", dir })
  end
  push("}\n")
  fs.mkdirp(fs.dirname(out_path))
  fs.writefile(out_path, table.concat(out))
end

local function load_docs_content (root_dir, gen_dir)
  local saved_path = package.path
  package.path = fs.join(root_dir, "client/lib/?.lua") .. ";" .. saved_path
  if gen_dir then
    package.path = fs.join(gen_dir, "?.lua") .. ";" .. package.path
  end
  for k in pairs(package.loaded) do
    if string.match(k, "^docs%.") then
      package.loaded[k] = nil
    end
  end
  local ok, content = pcall(require, "docs.content")
  package.path = saved_path
  if not ok then
    error(content)
  end
  return content
end

local function render_llms (content)
  local out = {}
  local push = pusher(out)
  push("# ", content.title, "\n\n")
  push("> ", content.summary, "\n\n")
  push("## About\n\n")
  push(content.about, "\n\n")
  push("## Lua version\n\n")
  push(content.lua_position, "\n\n")
  local order, groups = {}, {}
  for i = 1, #content.tabs do
    local tab = content.tabs[i]
    local name = tab.group or "Libraries"
    if not groups[name] then
      groups[name] = {}
      order[#order + 1] = name
    end
    local items = groups[name]
    items[#items + 1] = tab
  end
  for i = 1, #order do
    local name = order[i]
    push("## ", name, "\n\n")
    local items = groups[name]
    for j = 1, #items do
      local tab = items[j]
      if tab.url then
        push("- [", tab.label, "](", tab.url, "): ", tab.desc, "\n")
      else
        push("- ", tab.label, ": ", tab.desc, "\n")
      end
    end
    push("\n")
  end
  return table.concat(out)
end

local function render_llms_full (content)
  local out = {}
  local push = pusher(out)
  push("# ", content.title, "\n\n")
  push("> ", content.summary, "\n\n")
  push("## About\n\n")
  push(content.about, "\n\n")
  push("## Lua version\n\n")
  push(content.lua_position, "\n\n")
  for i = 1, #content.tabs do
    local tab = content.tabs[i]
    if tab.content then
      push("\n## ", tab.label, "\n\n")
      push(tab.content.intro, "\n")
      for j = 1, #tab.content.examples do
        local ex = tab.content.examples[j]
        push("\n### ", ex.title, "\n\n")
        push(ex.desc, "\n\n")
        push("```", ex.lang or "lua", "\n", ex.code)
        if not string.match(ex.code, "\n$") then
          push("\n")
        end
        push("```\n")
      end
    end
  end
  return table.concat(out)
end

return {
  env = {

    name = "santoku-docs",
    version = "0.0.2-1",
    license = "MIT",

    build = {
      dependencies = {
        "santoku-web >= 2.2.3, < 3.0.0",
      }
    },

    client = {
      public = public_files,
      ldflags = {
        "-sWASM_BIGINT",
        "-sDEFAULT_LIBRARY_FUNCS_TO_INCLUDE='$stringToNewUTF8'",
        "-sEXPORTED_FUNCTIONS=_main,_malloc,_free",
        "-sEXPORTED_RUNTIME_METHODS=stringToUTF8,lengthBytesUTF8,UTF8ToString,stringToNewUTF8,HEAPU8",
        "-sENVIRONMENT=web,worker",
        "-sABORT_ON_WASM_EXCEPTIONS=0",
      },
      bundle_mods = {
        "docs.sandbox",
        "santoku.array",
        "santoku.string",
        "santoku.table",
        "santoku.functional",
        "santoku.num",
        "santoku.fracidx",
        "santoku.web.val",
        "santoku.web.js",
        "santoku.monocypher",
        "santoku.template",
        "santoku.lpeg",
        "santoku.lpeg.strip",
        "santoku.re",
        "santoku.mustache",
        "santoku.markdown",
        "santoku.sqlite",
        "santoku.sqlite.db",
        "santoku.fs",
        "santoku.fs.posix",
        "santoku.mtx",
        "santoku.csr",
        "santoku.ivec",
        "santoku.dvec",
        "santoku.fvec",
        "santoku.spans",
        "santoku.learn.tokenizer",
        "santoku.learn.aho",
        "santoku.learn.booleanizer",
        "santoku.learn.decide",
        "santoku.error",
        "santoku.pvec",
        "santoku.re.core",
        "santoku.op",
        "santoku.validate",
        "santoku.utc",
        "santoku.random",
        "santoku.async",
        "santoku.serialize",
        "santoku.autoserialize",
        "santoku.co",
        "santoku.inherit",
        "santoku.geo",
        "santoku.env",
        "santoku.test",
        "santoku.web.pwa.csp",
        "santoku.sqlite.search",
        "santoku.sqlite.migrate",
        "santoku.sqlite.sync",
      },
      dependencies = {
        "lua == 5.1",
        "santoku >= 2.0.0, < 3.0.0",
        "santoku-web >= 2.2.3, < 3.0.0",
        "santoku-fs >= 2.0.0, < 3.0.0",
        "santoku-lpeg >= 2.0.0, < 3.0.0",
        "santoku-matrix >= 2.0.1, < 3.0.0",
        "santoku-sqlite >= 3.2.1, < 4.0.0",
        "santoku-sqlite-migrate >= 2.0.0, < 3.0.0",
        "santoku-learn >= 2.0.1, < 3.0.0",
        "santoku-template >= 2.0.0, < 3.0.0",
        "santoku-mustache >= 2.1.0, < 3.0.0",
        "santoku-markdown >= 2.1.0, < 3.0.0",
        "santoku-monocypher >= 2.0.1, < 3.0.0",
      },
      rules = {
        ["bundle$"] = {
          ldflags = arr.flatten({ prism_pre_js, {
            "--pre-js", "../../../vendor/codejar-global.js",
          } })
        }
      },
      pwa = {
        title = "santoku",
        name = "santoku",
        description = "A Lua framework for building applications end to end.",
        theme_color = "#1e293b",
        background_color = "#f5f5f4",
        transforms = {
          css = build.minify_css,
          html = lp.minify_html,
        },
      },
    },

    nginx = {
      ssl_self_signed = true,
      hsts = false,
      ssl_port = "8444",
      domain = "localhost",
      port = "8081",
      workers = "auto",
      acme_root = "/home/app",
    },

    server = {
      dependencies = {
        "lua == 5.1",
        "santoku >= 2.0.0, < 3.0.0",
      }
    },

    configure = function (submake, envs)
      local server_env = envs.server
      local nginx_cfg = envs.root.nginx
      if server_env then
        local env_cert = env.var("SSL_CERT", nil)
        local env_key = env.var("SSL_KEY", nil)
        if env_cert and env_key then
          nginx_cfg.ssl_cert = env_cert
          nginx_cfg.ssl_key = env_key
        elseif nginx_cfg.ssl_self_signed then
          local ssl_dir = fs.join(server_env.work_dir, "ssl")
          local ssl_cert = fs.join(ssl_dir, "localhost.crt")
          local ssl_key = fs.join(ssl_dir, "localhost.key")
          if not (fs.exists(ssl_cert) and fs.exists(ssl_key)) then
            fs.mkdirp(ssl_dir)
            sys.execute({
              "openssl", "req", "-x509", "-nodes", "-days", "365",
                "-newkey", "rsa:2048",
                "-keyout", ssl_key,
                "-out", ssl_cert,
                "-subj", "/CN=localhost/O=DEV ONLY - NOT FOR PRODUCTION",
                "-addext", "subjectAltName=DNS:localhost,IP:127.0.0.1"
            })
          end
          nginx_cfg.ssl_cert = ssl_cert
          nginx_cfg.ssl_key = ssl_key
        end
      end
      local client_env = envs.client
      if not client_env then return end
      local css_out = fs.join(client_env.public_dir, "index.css")
      local css_in = fs.join(client_env.build_dir, "res/index.css")
      submake.target({ client_env.target }, { css_out })
      submake.target({ css_out }, { css_in }, function ()
        sys.execute({
          "tailwindcss",
          "--cwd", client_env.root_dir,
          "-i", css_in,
          "-o", css_out,
          "--minify"
        })
      end)
      local icon_svg = fs.join(client_env.root_dir, "res/icons/icon.svg")
      local favicon_svg = fs.join(client_env.public_dir, "favicon.svg")
      submake.target({ client_env.target }, { favicon_svg })
      submake.target({ favicon_svg }, { icon_svg }, function ()
        fs.writefile(favicon_svg, fs.readfile(icon_svg))
      end)
      local stable_dir = fs.join(client_env.dist_dir, "public")
      local logo_svg = fs.join(stable_dir, "logo.svg")
      local logo_png = fs.join(stable_dir, "logo.png")
      submake.target({ client_env.target }, { logo_svg, logo_png })
      submake.target({ logo_svg }, { icon_svg }, function ()
        fs.mkdirp(stable_dir)
        fs.writefile(logo_svg, fs.readfile(icon_svg))
      end)
      submake.target({ logo_png }, { icon_svg }, function ()
        fs.mkdirp(stable_dir)
        sys.execute({
          "rsvg-convert", "-w", "192", "-h", "192",
          "-o", logo_png, icon_svg
        })
      end)
      local banner_dir = fs.join(client_env.root_dir, "res/icons/banners")
      if fs.exists(banner_dir) then
        for fp in fs.files(banner_dir) do
          if fp:match("%.svg$") then
            local rock = fs.stripextensions(fs.basename(fp))
            local png = fs.join(stable_dir, "logo-" .. rock .. ".png")
            submake.target({ client_env.target }, { png })
            submake.target({ png }, { fp }, function ()
              fs.mkdirp(stable_dir)
              sys.execute({ "rsvg-convert", "-h", "128", "-o", png, fp })
            end)
          end
        end
      end
      local manifest_icons = {}
      local icon_pngs = {}
      for _, variant in ipairs(icon_variants) do
        for _, size in ipairs(icon_sizes) do
          local icon_name = "icon" .. variant.suffix .. "-" .. size .. ".png"
          local icon_file = fs.join(client_env.public_dir, icon_name)
          local source = fs.join(client_env.root_dir, variant.svg)
          submake.target({ client_env.target }, { icon_file })
          submake.target({ icon_file }, { source }, function ()
            sys.execute({
              "rsvg-convert", "-w", tostring(size), "-h", tostring(size),
              "-o", icon_file, source
            })
          end)
          arr.push(icon_pngs, icon_file)
          arr.push(manifest_icons, {
            src = "/" .. icon_name,
            sizes = size .. "x" .. size,
            type = "image/png",
            purpose = variant.purpose,
          })
        end
      end
      local apple_icon = fs.join(client_env.public_dir, "apple-touch-icon.png")
      submake.target({ client_env.target }, { apple_icon })
      submake.target({ apple_icon }, { icon_svg }, function ()
        sys.execute({
          "rsvg-convert", "-w", tostring(apple_icon_size), "-h", tostring(apple_icon_size),
          "--background-color", "#1e293b",
          "-o", apple_icon, icon_svg
        })
      end)
      envs.root.client.pwa.icons = manifest_icons
      if client_env.static_files_ok then
        local all_static_files = arr.flatten({ { css_out, favicon_svg, apple_icon }, icon_pngs })
        submake.target({ client_env.static_files_ok }, all_static_files)
      end
      local vendor_dir = fs.join(client_env.work_dir, "vendor")
      local codejar_esm = fs.join(vendor_dir, "codejar.esm.js")
      local codejar_global = fs.join(vendor_dir, "codejar-global.js")
      local prism_files = {}
      for _, p in ipairs(prism_components) do
        local dest = fs.join(vendor_dir, "prism-" .. p.name .. ".min.js")
        prism_files[#prism_files + 1] = dest
        submake.target({ dest }, { "make.common.lua" }, function ()
          vendor.fetch({
            url = "https://cdn.jsdelivr.net/npm/prismjs@1.30.0/components/prism-" ..
              p.name .. ".min.js",
            sha256 = p.sha256,
          }, dest)
        end)
      end
      submake.target({ codejar_esm }, { "make.common.lua" }, function ()
        vendor.fetch({
          url = "https://cdn.jsdelivr.net/npm/codejar@4.2.0/dist/codejar.js",
          sha256 = "82a66955e2c2785967b12a819c7feb80c1a2bb9db9a210e1c60d5816ba6c25c4",
        }, codejar_esm)
      end)
      submake.target({ codejar_global }, { codejar_esm, "make.common.lua" }, function ()
        local src = fs.readfile(codejar_esm)
        local out, n = string.gsub(src, "export function CodeJar", "function CodeJar", 1)
        if n ~= 1 then
          error("unexpected codejar module shape: " .. codejar_esm)
        end
        fs.writefile(codejar_global, out .. "\nwindow.CodeJar = CodeJar;\n")
      end)
      local bundle_post = fs.join(client_env.bundler_post_dir, "bundle")
      submake.target({ bundle_post },
        arr.flatten({ prism_files, { codejar_global } }))
      local content_src = fs.join(client_env.root_dir, "client/lib/docs/content.lua")
      local tabs_dir = fs.join(client_env.root_dir, "client/lib/docs/tabs")
      local hash_ok = fs.join(client_env.dist_dir, "hash.ok")
      local scaffold_src = fs.join(client_env.work_dir, "lib/docs/scaffold.lua")
      local scaffold_deps = {}
      for _, mod in ipairs({
        "santoku.make.project.lib",
        "santoku.make.project.web",
        "santoku.make.project.api",
      }) do
        local fp = env.searchpath(mod, package.path)
        if fp then
          scaffold_deps[#scaffold_deps + 1] = fp
        end
      end
      local scaffold_work = client_env.work_dir
      submake.target({ scaffold_src }, scaffold_deps, function ()
        generate_scaffold(scaffold_src, scaffold_work)
      end)
      local setup_sh_src = fs.join(client_env.root_dir, "res/setup-toku.sh")
      local setup_sh_mod = fs.join(client_env.work_dir, "lib/docs/setup_script.lua")
      submake.target({ setup_sh_mod }, { setup_sh_src }, function ()
        fs.mkdirp(fs.dirname(setup_sh_mod))
        fs.writefile(setup_sh_mod,
          "return { lang = \"bash\", code = " ..
          string.format("%q", fs.readfile(setup_sh_src)) .. " }\n")
      end)
      submake.target({ fs.join(client_env.work_dir, "lua_modules.ok") },
        { scaffold_src, setup_sh_mod })
      local setup_sh_pub = fs.join(client_env.dist_dir, "public", "setup-toku.sh")
      submake.target({ client_env.target }, { setup_sh_pub })
      submake.target({ setup_sh_pub }, { setup_sh_src }, function ()
        fs.mkdirp(fs.dirname(setup_sh_pub))
        fs.writefile(setup_sh_pub, fs.readfile(setup_sh_src))
      end)
      local function llms_deps ()
        local deps = { content_src, hash_ok, scaffold_src, setup_sh_mod }
        for fp in fs.files(tabs_dir) do
          deps[#deps + 1] = fp
        end
        return deps
      end
      local gen_dir = fs.join(client_env.work_dir, "lib")
      local claims_src = fs.join(client_env.root_dir, "res/claims.lua")
      local claims_ok = fs.join(client_env.work_dir, "claims.ok")
      submake.target({ client_env.target }, { claims_ok })
      local claims_deps = {
        claims_src, scaffold_src, setup_sh_src,
        fs.join(client_env.work_dir, "lua_modules.ok"),
      }
      for fp in fs.files(tabs_dir) do
        claims_deps[#claims_deps + 1] = fp
      end
      submake.target({ claims_ok }, claims_deps,
        function ()
          fs.runfile(claims_src)({
            root_dir = client_env.root_dir,
            gen_dir = gen_dir,
            lua_path = client_env.lua_path,
          })
          fs.mkdirp(fs.dirname(claims_ok))
          fs.writefile(claims_ok, "")
        end)
      local llms_txt = fs.join(client_env.dist_dir, "public", "llms.txt")
      local llms_full_txt = fs.join(client_env.dist_dir, "public", "llms-full.txt")
      submake.target({ client_env.target }, { llms_txt, llms_full_txt })
      submake.target({ llms_txt }, llms_deps(), function ()
        fs.mkdirp(fs.dirname(llms_txt))
        fs.writefile(llms_txt, render_llms(load_docs_content(client_env.root_dir, gen_dir)))
      end)
      submake.target({ llms_full_txt }, llms_deps(), function ()
        fs.mkdirp(fs.dirname(llms_full_txt))
        fs.writefile(llms_full_txt, render_llms_full(load_docs_content(client_env.root_dir, gen_dir)))
      end)
    end,

  }
}
