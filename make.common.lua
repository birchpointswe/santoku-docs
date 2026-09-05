local fs = require("santoku.fs")
local arr = require("santoku.array")
local sys = require("santoku.system")
local env = require("santoku.env")
local vendor = require("santoku.make.vendor")

local site = "https://santoku.dev"

local icon_sizes = { 192, 512, 1024 }
local apple_icon_size = 180
local icon_variants = {
  { suffix = "", svg = "res/icons/icon.svg", purpose = "any" },
  { suffix = "-maskable", svg = "res/icons/maskable.svg", purpose = "maskable" },
}

local banner_rocks = {}
for fp in fs.files("res/icons/banners") do
  if fp:match("%.svg$") then
    arr.push(banner_rocks, fs.stripextensions(fs.basename(fp)))
  end
end
table.sort(banner_rocks)

local public_files = { "index.css", "favicon.svg", "apple-touch-icon.png", "logo.svg", "logo.png" }
for _, variant in ipairs(icon_variants) do
  for _, size in ipairs(icon_sizes) do
    arr.push(public_files, "icon" .. variant.suffix .. "-" .. size .. ".png")
  end
end
for _, rock in ipairs(banner_rocks) do
  arr.push(public_files, "logo-" .. rock .. ".png")
end

local stable_files = {
  "llms.txt", "llms-full.txt", "sitemap.xml", "setup-toku.sh",
  "logo.svg", "logo.png",
}
for _, rock in ipairs(banner_rocks) do
  arr.push(stable_files, "logo-" .. rock .. ".png")
end

local scaffold_meta = fs.runfile("res/docs/scaffold_specs.lua")

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

local function generate_scaffold (out_path, work_dir)
  local project = require("santoku.make.project")
  local serialize = require("santoku.serialize")
  local scaffold = scaffold_meta.build(project.snapshot, function (key)
    return fs.join(work_dir, "scaffold-" .. key)
  end)
  fs.mkdirp(fs.dirname(out_path))
  fs.writefile(out_path, "return " .. serialize(scaffold) .. "\n")
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
      site = site,
      public = public_files,
      stable = stable_files,
      generated = {
        "lib/docs/scaffold.lua",
        "lib/docs/setup_script.lua",
        "lib/docs/highlighted.lua",
        "lib/docs/search_index.lua",
      },
      check_links = true,
      ldflags = {
        "-sWASM_BIGINT",
        "-sDEFAULT_LIBRARY_FUNCS_TO_INCLUDE='$stringToNewUTF8'",
        "-sEXPORTED_FUNCTIONS=_main,_malloc,_free",
        "-sEXPORTED_RUNTIME_METHODS=stringToUTF8,lengthBytesUTF8,UTF8ToString,stringToNewUTF8,HEAPU8",
        "-sENVIRONMENT=web,worker",
        "-sABORT_ON_WASM_EXCEPTIONS=0",
      },
      bundle_mods = fs.runfile("res/docs/bundle_mods.lua"),
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
      },
      test = {
        dependencies = {
          "santoku-make >= 5.1.0, < 6.0.0",
          "santoku-cli >= 2.12.0, < 3.0.0",
          "santoku-fs >= 2.1.3, < 3.0.0",
          "santoku-web >= 2.2.3, < 3.0.0",
          "santoku-http >= 2.0.0, < 3.0.0",
          "santoku-sqlite >= 3.2.1, < 4.0.0",
        }
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
      local docs_res = {}
      for fp in fs.files(fs.join(client_env.root_dir, "res/docs"), true) do
        arr.push(docs_res, fp)
      end
      local css_out = fs.join(client_env.public_dir, "index.css")
      local css_in = fs.join(client_env.build_dir, "res/index.css")
      submake.target({ client_env.target }, { css_out })
      submake.target({ css_out }, arr.flatten({ { css_in }, docs_res }), function ()
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
      local logo_svg = fs.join(client_env.public_dir, "logo.svg")
      local logo_png = fs.join(client_env.public_dir, "logo.png")
      submake.target({ client_env.target }, { logo_svg, logo_png })
      submake.target({ logo_svg }, { icon_svg }, function ()
        fs.writefile(logo_svg, fs.readfile(icon_svg))
      end)
      submake.target({ logo_png }, { icon_svg }, function ()
        sys.execute({
          "rsvg-convert", "-w", "192", "-h", "192",
          "-o", logo_png, icon_svg
        })
      end)
      local banner_pngs = {}
      for _, rock in ipairs(banner_rocks) do
        local svg = fs.join(client_env.root_dir, "res/icons/banners", rock .. ".svg")
        local png = fs.join(client_env.public_dir, "logo-" .. rock .. ".png")
        arr.push(banner_pngs, png)
        submake.target({ client_env.target }, { png })
        submake.target({ png }, { svg }, function ()
          sys.execute({ "rsvg-convert", "-h", "128", "-o", png, svg })
        end)
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
        local all_static_files = arr.flatten({
          { css_out, favicon_svg, apple_icon, logo_svg, logo_png }, icon_pngs, banner_pngs })
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
      local content_src = fs.join(client_env.root_dir, "res/docs/content.lua")
      local tabs_dir = fs.join(client_env.root_dir, "res/docs/tabs")
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
      local function content_deps ()
        local deps = { content_src, scaffold_src, setup_sh_mod }
        for fp in fs.files(tabs_dir) do
          deps[#deps + 1] = fp
        end
        return deps
      end
      local gen_dir = fs.join(client_env.work_dir, "lib")
      local highlighted_src = fs.join(client_env.work_dir, "lib/docs/highlighted.lua")
      local prism_names = {}
      for _, p in ipairs(prism_components) do
        prism_names[#prism_names + 1] = p.name
      end
      local loader_src = fs.join(client_env.root_dir, "res/docs/load.lua")
      local highlight_src = fs.join(client_env.root_dir, "res/docs/highlight.lua")
      local function content_loader ()
        return fs.runfile(loader_src)({
          readfile = fs.readfile,
          root_dir = client_env.root_dir,
          gen_dir = gen_dir,
        })
      end
      submake.target({ highlighted_src },
        arr.flatten({ content_deps(), { loader_src, highlight_src }, prism_files }),
        function ()
          fs.runfile(highlight_src)({
            content = content_loader()("docs.content"),
            work_dir = client_env.work_dir,
            vendor_dir = vendor_dir,
            prism = prism_names,
            out_path = highlighted_src,
          })
        end)
      local search_src = fs.join(client_env.root_dir, "res/docs/search.lua")
      local search_index_src = fs.join(client_env.work_dir, "lib/docs/search_index.lua")
      submake.target({ search_index_src },
        arr.flatten({ content_deps(), { loader_src, search_src } }),
        function ()
          local req = content_loader()
          fs.mkdirp(fs.dirname(search_index_src))
          fs.writefile(search_index_src,
            fs.runfile(search_src)(req("docs.content"), req("docs.ids")))
        end)
    end,

  }
}
