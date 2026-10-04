#!/bin/sh
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Birch Point SWE
set -eu

unset LUAROCKS_SYSCONFDIR LUAROCKS_CONFIG LUA_PATH LUA_CPATH LUA_INIT || true

LUA_VERSION=5.1.5
LUA_URL=https://www.lua.org/ftp/lua-5.1.5.tar.gz
LUA_SHA256=2640fc56a795f29d28ef15e13c34a47e223960b0240e8cb0a82d9b0738695333
LUAROCKS_VERSION=3.13.0
LUAROCKS_URL=https://luarocks.github.io/luarocks/releases/luarocks-3.13.0.tar.gz
LUAROCKS_SHA256=245bf6ec560c042cb8948e3d661189292587c5949104677f1eecddc54dbe7e37
OPENRESTY_VERSION=1.31.1.1
OPENRESTY_URL=https://openresty.org/download/openresty-1.31.1.1.tar.gz
OPENRESTY_SHA256=65b78baadd3f0984055de89bf13f4a1932e5bfe9c31932037a134ea2b1a0ce42
OPENSSL_VERSION=3.5.8
OPENSSL_URL=https://github.com/openssl/openssl/releases/download/openssl-3.5.8/openssl-3.5.8.tar.gz
OPENSSL_SHA256=a8f84a39918ec6415ce765d9b429d313ba97b8143169c172e734b9514464f5b2
OPENSSL_PATCH=openssl-3.5.5-sess_set_get_cb_yield.patch
OPENSSL_PATCH_URL=https://raw.githubusercontent.com/openresty/openresty/0de3defb207c5557f5be2fce7d6f1d696b637ede/patches/openssl-3.5.5-sess_set_get_cb_yield.patch
OPENSSL_PATCH_SHA256=0a30cc762a9d72901e8415a33f7671bb68469d46121061e26afe7b718f47581e
PCRE2_VERSION=10.48
PCRE2_URL=https://github.com/PCRE2Project/pcre2/releases/download/pcre2-10.48/pcre2-10.48.tar.gz
PCRE2_SHA256=ebcc25aadf2a51fa1fefa9b8bc9e7a79b3dae86870a0f1152a22e42befd46888
ZLIB_VERSION=1.3.2
ZLIB_URL=https://github.com/madler/zlib/releases/download/v1.3.2/zlib-1.3.2.tar.gz
ZLIB_SHA256=bb329a0a2cd0274d05519d61c667c062e06990d72e125ee2dfa8de64f0119d16

ROOT="${XDG_DATA_HOME:-$HOME/.local/share}/toku"
REBUILD=0
RESTY=0
CLI_PIN="${TOKU_CLI_VERSION:-}"

usage () {
  printf 'usage: sh setup-toku.sh [--root DIR] [--rebuild] [--resty] [--cli-version VERSION]\n'
  printf '  --resty builds the pinned OpenResty into the managed tree; later runs keep it\n'
  printf '  --cli-version, or TOKU_CLI_VERSION, installs that santoku-cli version; the flag wins\n'
}

say () {
  printf '[setup]\t%s\n' "$1"
}

die () {
  printf '[setup]\terror: %s\n' "$1" >&2
  exit 1
}

while [ $# -gt 0 ]; do
  case "$1" in
    --root)
      [ $# -ge 2 ] || die "--root needs a directory"
      ROOT="$2"
      shift
      ;;
    --rebuild)
      REBUILD=1
      ;;
    --resty)
      RESTY=1
      ;;
    --cli-version)
      [ $# -ge 2 ] || die "--cli-version needs a santoku-cli version"
      CLI_PIN="$2"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      die "unknown argument: $1"
      ;;
  esac
  shift
done

case "$CLI_PIN" in
  *[!0-9A-Za-z.-]*) die "santoku-cli version may hold only digits, letters, . and -: $CLI_PIN" ;;
esac

SRC="$ROOT/src"
MANIFEST="$ROOT/manifest.lua"

need () {
  command -v "$1" >/dev/null 2>&1 || die "missing required tool: $1"
}

sha () {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum -- "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 -- "$1" | awk '{print $1}'
  elif command -v openssl >/dev/null 2>&1; then
    openssl dgst -sha256 -r "$1" | awk '{print $1}'
  else
    die "missing sha256sum, shasum, or openssl"
  fi
}

have_gnu_wget () {
  command -v wget >/dev/null 2>&1 || return 1
  wget --version 2>&1 | head -n 1 | grep -q 'GNU Wget'
}

get () {
  if command -v curl >/dev/null 2>&1; then
    curl -fSL -o "$1" "$2"
  elif have_gnu_wget; then
    wget -q -O "$1" -- "$2"
  else
    die "missing curl or GNU wget"
  fi
}

fetch () {
  dest="$SRC/$1"
  url="$2"
  want="$3"
  if [ -f "$dest" ] && [ "$(sha "$dest")" = "$want" ]; then
    say "cached $1"
    return
  fi
  rm -f "$dest" "$dest.part"
  say "fetching $url"
  get "$dest.part" "$url"
  got="$(sha "$dest.part")"
  [ "$got" = "$want" ] || die "sha256 mismatch for $1 (want $want got $got)"
  mv "$dest.part" "$dest"
  say "ok $dest"
}

extract () {
  rm -rf "$SRC/$1"
  tar -xzf "$SRC/$1.tar.gz" -C "$SRC"
  [ -d "$SRC/$1" ] || die "extraction did not produce $SRC/$1"
}

patch_lua () {
  f="$SRC/lua-$LUA_VERSION/src/luaconf.h"
  [ -f "$f" ] || die "missing $f"
  cat >> "$f" <<'EOF'

#undef LUA_TMPNAMBUFSIZE
#define LUA_TMPNAMBUFSIZE	256
#undef lua_tmpnam
#define lua_tmpnam(b,e) { \
	const char *tk_td = getenv("TMPDIR"); \
	if (tk_td == NULL || *tk_td == '\0') tk_td = "/tmp"; \
	if (strlen(tk_td) + 12 > LUA_TMPNAMBUFSIZE) tk_td = "/tmp"; \
	strcpy(b, tk_td); strcat(b, "/lua_XXXXXX"); \
	e = mkstemp(b); \
	if (e != -1) close(e); \
	e = (e == -1); }
EOF
  grep -q 'tk_td' "$f" || die "luaconf.h tmpnam patch did not apply"
  cat >> "$f" <<EOF

#undef LUA_PATH_DEFAULT
#define LUA_PATH_DEFAULT \\
	"$ROOT/rocks/share/lua/5.1/?.lua;" \\
	"$ROOT/rocks/share/lua/5.1/?/init.lua;" \\
	"$ROOT/lua/share/lua/5.1/?.lua;" \\
	"$ROOT/lua/share/lua/5.1/?/init.lua;" \\
	"./?.lua"
#undef LUA_CPATH_DEFAULT
#define LUA_CPATH_DEFAULT \\
	"$ROOT/rocks/lib/lua/5.1/?.so;" \\
	"$ROOT/lua/lib/lua/5.1/?.so;" \\
	"./?.so"
EOF
  grep -q 'rocks/share/lua/5.1' "$f" ||
    die "luaconf.h search-path patch did not apply"
}

patch_luarocks () {
  d="$SRC/luarocks-$LUAROCKS_VERSION"
  f="$d/src/luarocks/core/sysdetect.lua"
  [ -f "$f" ] || die "missing $f"
  sed 's/local libname = fd:read(64):gsub("%z\.\*", "")/local libname = (fd:read(64) or ""):gsub("%z.*", "")/' \
    "$f" > "$f.patched"
  mv -- "$f.patched" "$f"
  grep -q 'fd:read(64) or ""' "$f" || die "luarocks sysdetect patch did not apply"
  f="$d/src/luarocks/fs/unix/tools.lua"
  [ -f "$f" ] || die "missing $f"
  sed 's/fs\.execute(vars\.LN \.\. force_flag, tempfile, lockfile)/fs.execute(vars.LN .. " -s" .. force_flag, tempfile, lockfile)/' \
    "$f" > "$f.patched"
  mv -- "$f.patched" "$f"
  grep -q 'vars\.LN \.\. " -s"' "$f" || die "luarocks lockfile patch did not apply"
}

patch_openresty () {
  d="$SRC/openresty-$OPENRESTY_VERSION"
  f="$d/bundle/nginx-1.31.1/src/event/modules/ngx_epoll_module.c"
  [ -f "$f" ] || die "missing $f"
  (cd "$d" && patch -p1) <<'EOF' || die "openresty epoll patch did not apply"
--- a/bundle/nginx-1.31.1/src/event/modules/ngx_epoll_module.c
+++ b/bundle/nginx-1.31.1/src/event/modules/ngx_epoll_module.c
@@ -591,16 +591,10 @@
     if (event == NGX_READ_EVENT) {
         e = c->write;
         prev = EPOLLOUT;
-#if (NGX_READ_EVENT != EPOLLIN|EPOLLRDHUP)
-        events = EPOLLIN|EPOLLRDHUP;
-#endif

     } else {
         e = c->read;
         prev = EPOLLIN|EPOLLRDHUP;
-#if (NGX_WRITE_EVENT != EPOLLOUT)
-        events = EPOLLOUT;
-#endif
     }

     if (e->active) {
EOF
  grep -q 'NGX_WRITE_EVENT != EPOLLOUT' "$f" && die "openresty epoll patch did not apply"
  f="$d/bundle/resty-cli-0.32/bin/resty"
  [ -f "$f" ] || die "missing $f"
  (cd "$d" && patch -p1) <<'EOF' || die "resty tmp patch did not apply"
--- a/bundle/resty-cli-0.32/bin/resty
+++ b/bundle/resty-cli-0.32/bin/resty
@@ -626,7 +626,7 @@
     mkdir $prefix_dir or die "failed to mkdir $prefix_dir: $!";

 } else {
-    if ($is_win32 || !-d '/tmp') {
+    if ($is_win32 || !-w '/tmp') {
         require File::Temp;
         $prefix_dir = File::Temp::tempdir(CLEANUP => 1);

EOF
  grep -q "!-w '/tmp'" "$f" || die "resty tmp patch did not apply"
}

for t in cc make tar unzip; do
  need "$t"
done
if command -v wget >/dev/null 2>&1 && ! have_gnu_wget; then
  die "wget on PATH is busybox wget, not GNU wget (Alpine and similar).
	luarocks prefers wget over curl and passes GNU-only flags to it, so
	INSTALLING CURL DOES NOT HELP: it still picks busybox wget and every
	download fails later as a misleading 'No results matching query'.
	Install GNU wget so it takes precedence:  apk add wget"
fi

if ! command -v curl >/dev/null 2>&1 && ! have_gnu_wget; then
  die "missing curl or GNU wget"
fi
command -v sha256sum >/dev/null 2>&1 || command -v shasum >/dev/null 2>&1 ||
  command -v openssl >/dev/null 2>&1 || die "missing sha256sum, shasum, or openssl"

case "$ROOT" in
  *' '*) die "managed root contains whitespace: $ROOT" ;;
esac

if [ "$REBUILD" -eq 0 ] && [ -f "$MANIFEST" ] && grep -q 'mode = "managed"' "$MANIFEST"; then
  built_lua="$(sed -n 's/^ *lua = "\(.*\)",$/\1/p' "$MANIFEST")"
  built_luarocks="$(sed -n 's/^ *luarocks = "\(.*\)",$/\1/p' "$MANIFEST")"
  if [ -n "$built_lua$built_luarocks" ] &&
    { [ "$built_lua" != "$LUA_VERSION" ] || [ "$built_luarocks" != "$LUAROCKS_VERSION" ]; }; then
    die "managed tree was built from lua ${built_lua:-?} and luarocks ${built_luarocks:-?}, not the pinned $LUA_VERSION and $LUAROCKS_VERSION; rerun with --rebuild (from toku: toku setup --upgrade)"
  fi
  built_resty="$(sed -n 's/^ *openresty = "\(.*\)",$/\1/p' "$MANIFEST")"
  if [ -n "$built_resty" ] && [ "$built_resty" != "$OPENRESTY_VERSION" ]; then
    die "managed tree was built with openresty $built_resty, not the pinned $OPENRESTY_VERSION; rerun with --rebuild (from toku: toku setup --upgrade)"
  fi
fi

if [ -f "$MANIFEST" ] && grep -q '^ *openresty = ' "$MANIFEST"; then
  RESTY=1
fi

if [ "$RESTY" -eq 1 ]; then
  for t in patch perl; do
    need "$t"
  done
fi

if [ "$REBUILD" -eq 1 ]; then
  say "rebuilding toolchain, keeping $ROOT/rocks"
  rm -rf "$ROOT/lua" "$ROOT/luarocks" "$ROOT/openresty" "$SRC"
  rm -f "$MANIFEST"
fi

mkdir -p "$SRC"

[ -f "$0" ] || die "cannot read my own source at $0 to store it in $ROOT"
cp -- "$0" "$ROOT/setup-toku.sh.new"
mv -- "$ROOT/setup-toku.sh.new" "$ROOT/setup-toku.sh"
chmod +x "$ROOT/setup-toku.sh"

PLAT="$(uname -s)"

if [ ! -x "$ROOT/lua/bin/lua" ]; then
  fetch "lua-$LUA_VERSION.tar.gz" "$LUA_URL" "$LUA_SHA256"
  extract "lua-$LUA_VERSION"
  patch_lua
  say "building lua $LUA_VERSION ($PLAT)"
  case "$PLAT" in
    Darwin)
      (cd "$SRC/lua-$LUA_VERSION" && make macosx)
      ;;
    Linux)
      (cd "$SRC/lua-$LUA_VERSION" && make -C src all CC=cc \
        "MYCFLAGS=-DLUA_USE_POSIX -DLUA_USE_DLOPEN" "MYLIBS=-Wl,-E -ldl")
      ;;
    *)
      (cd "$SRC/lua-$LUA_VERSION" && make -C src all CC=cc \
        "MYCFLAGS=-DLUA_USE_POSIX -DLUA_USE_DLOPEN" "MYLIBS=-Wl,-E")
      ;;
  esac
  (cd "$SRC/lua-$LUA_VERSION" && make install "INSTALL_TOP=$ROOT/lua")
  [ -x "$ROOT/lua/bin/lua" ] || die "lua build did not produce $ROOT/lua/bin/lua"
fi

if [ ! -x "$ROOT/luarocks/bin/luarocks" ]; then
  fetch "luarocks-$LUAROCKS_VERSION.tar.gz" "$LUAROCKS_URL" "$LUAROCKS_SHA256"
  extract "luarocks-$LUAROCKS_VERSION"
  patch_luarocks
  say "building luarocks $LUAROCKS_VERSION"
  (cd "$SRC/luarocks-$LUAROCKS_VERSION" &&
    sh ./configure "--prefix=$ROOT/luarocks" "--with-lua=$ROOT/lua" "--rocks-tree=$ROOT/rocks" &&
    make -f GNUmakefile all &&
    make -f GNUmakefile install)
  [ -x "$ROOT/luarocks/bin/luarocks" ] || die "luarocks build did not produce $ROOT/luarocks/bin/luarocks"
fi

if [ "$RESTY" -eq 1 ] && [ ! -x "$ROOT/openresty/bin/openresty" ]; then
  fetch "openresty-$OPENRESTY_VERSION.tar.gz" "$OPENRESTY_URL" "$OPENRESTY_SHA256"
  fetch "openssl-$OPENSSL_VERSION.tar.gz" "$OPENSSL_URL" "$OPENSSL_SHA256"
  fetch "$OPENSSL_PATCH" "$OPENSSL_PATCH_URL" "$OPENSSL_PATCH_SHA256"
  fetch "pcre2-$PCRE2_VERSION.tar.gz" "$PCRE2_URL" "$PCRE2_SHA256"
  fetch "zlib-$ZLIB_VERSION.tar.gz" "$ZLIB_URL" "$ZLIB_SHA256"
  extract "openresty-$OPENRESTY_VERSION"
  patch_openresty
  extract "openssl-$OPENSSL_VERSION"
  extract "pcre2-$PCRE2_VERSION"
  extract "zlib-$ZLIB_VERSION"
  (cd "$SRC/openssl-$OPENSSL_VERSION" && patch -p1 < "$SRC/$OPENSSL_PATCH") ||
    die "openssl patch $OPENSSL_PATCH did not apply"
  JOBS="$(getconf _NPROCESSORS_ONLN 2>/dev/null || printf 1)"
  say "building openresty $OPENRESTY_VERSION with openssl $OPENSSL_VERSION, pcre2 $PCRE2_VERSION, zlib $ZLIB_VERSION ($PLAT)"
  (cd "$SRC/openresty-$OPENRESTY_VERSION" &&
    ./configure "--prefix=$ROOT/openresty" \
      "--with-cc-opt=-O2 -DMAXNS=3" \
      --with-pcre-jit \
      "--with-openssl=$SRC/openssl-$OPENSSL_VERSION" \
      "--with-pcre=$SRC/pcre2-$PCRE2_VERSION" \
      "--with-zlib=$SRC/zlib-$ZLIB_VERSION" \
      "-j$JOBS" &&
    make "-j$JOBS" &&
    make install)
  [ -x "$ROOT/openresty/bin/openresty" ] || die "openresty build did not produce $ROOT/openresty/bin/openresty"
fi

if [ "$RESTY" -eq 1 ]; then
  if [ "$(uname -o 2>/dev/null)" = Android ]; then
    need patchelf
    NGINX_BIN="$ROOT/openresty/nginx/sbin/nginx"
    LJ_LIB="$ROOT/openresty/luajit/lib"
    RP="$(patchelf --print-rpath "$NGINX_BIN")"
    case "$RP" in
      "$LJ_LIB":*) ;;
      *)
        say "putting $LJ_LIB first in nginx's runpath, ahead of the system libluajit"
        patchelf --set-rpath "$LJ_LIB:$RP" "$NGINX_BIN"
        ;;
    esac
  fi
  "$ROOT/openresty/bin/openresty" -v >/dev/null 2>&1 ||
    die "$ROOT/openresty/bin/openresty does not run; check its output with: $ROOT/openresty/bin/openresty -v"
fi

CFG="$ROOT/luarocks/etc/luarocks/config-5.1.lua"
[ -f "$CFG" ] || die "luarocks config not found: $CFG"
grep -q 'name = "toku"' "$CFG" ||
  printf 'rocks_trees = {\n  { name = "toku", root = "%s/rocks" },\n}\n' "$ROOT" >> "$CFG"

CC_PATH="$(command -v cc)"
SYS_PREFIX="$(dirname "$(dirname "$CC_PATH")")"
case "$SYS_PREFIX" in
  /|/usr|/usr/local) SYS_PREFIX="" ;;
  *) [ -d "$SYS_PREFIX/include" ] || SYS_PREFIX="" ;;
esac

if [ -n "$SYS_PREFIX" ] && ! grep -q 'toku: system prefix' "$CFG"; then
  say "C libraries live under $SYS_PREFIX (from $CC_PATH)"
  printf '\n-- toku: system prefix, derived from %s\n' "$CC_PATH" >> "$CFG"
  printf 'external_deps_dirs = { "%s", "/usr/local", "/usr", "/" }\n' "$SYS_PREFIX" >> "$CFG"
  printf 'variables = variables or {}\n' >> "$CFG"
  printf 'variables.LIBFLAG = "-shared -Wl,-rpath,%s/lib"\n' "$SYS_PREFIX" >> "$CFG"
fi

for lock in "$ROOT/rocks/lockfile.lfs" "$ROOT/rocks/lib/luarocks/lockfile.lfs"; do
  if [ -e "$lock" ]; then
    say "clearing stale lock $lock"
    rm -f "$lock"
  fi
done

installed_cli () {
  [ -x "$ROOT/rocks/bin/toku" ] || return 0
  v="$("$ROOT/rocks/bin/toku" --version 2>/dev/null | awk '{print $2}')"
  case "$CLI_PIN" in
    *-*) printf '%s' "$v" ;;
    *) printf '%s' "${v%-*}" ;;
  esac
}

INSTALL_CLI=0
if [ "$REBUILD" -eq 1 ] || [ ! -x "$ROOT/rocks/bin/toku" ]; then
  INSTALL_CLI=1
elif [ -n "$CLI_PIN" ] && [ "$(installed_cli)" != "$CLI_PIN" ]; then
  INSTALL_CLI=1
fi

if [ "$INSTALL_CLI" -eq 1 ]; then
  say "installing santoku-cli${CLI_PIN:+ $CLI_PIN} into $ROOT/rocks"
  (cd "$ROOT" &&
    PATH="$ROOT/rocks/bin:$ROOT/luarocks/bin:$ROOT/lua/bin:$PATH" \
    LUAROCKS_CONFIG="$CFG" \
    "$ROOT/luarocks/bin/luarocks" install santoku-cli ${CLI_PIN:+"$CLI_PIN"})
  [ -x "$ROOT/rocks/bin/toku" ] || die "santoku-cli install did not produce $ROOT/rocks/bin/toku"
fi

if [ -n "$CLI_PIN" ] && [ "$(installed_cli)" != "$CLI_PIN" ]; then
  die "santoku-cli $CLI_PIN was requested, but $ROOT/rocks/bin/toku reports $(installed_cli)"
fi

CLI_VERSION="$("$ROOT/rocks/bin/toku" --version 2>/dev/null | awk '{print $2}')"
[ -n "$CLI_VERSION" ] || CLI_VERSION=unknown

RESTY_LINE=""
RESTY_PATH=""
if [ "$RESTY" -eq 1 ]; then
  RESTY_LINE="$(printf '  openresty = "%s",\n' "$OPENRESTY_VERSION")"
  RESTY_PATH="$ROOT/openresty/bin:"
fi

{
  printf 'return {\n  cli = "%s",\n  created = "%s",\n  lua = "%s",\n  luarocks = "%s",\n  mode = "managed",\n' \
    "$CLI_VERSION" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$LUA_VERSION" "$LUAROCKS_VERSION"
  [ -z "$RESTY_LINE" ] || printf '%s\n' "$RESTY_LINE"
  printf '  platform = "%s",\n}\n' "$PLAT"
} > "$MANIFEST"

say "managed toolchain ready at $ROOT"
say "managed toku: $ROOT/rocks/bin/toku"
[ "$RESTY" -eq 0 ] || say "managed openresty: $ROOT/openresty/bin/openresty"
say "optional PATH wiring:"
say "  export PATH=\"$ROOT/rocks/bin:$ROOT/luarocks/bin:$ROOT/lua/bin:$RESTY_PATH\$PATH\""
say "verify with: toku doctor"
