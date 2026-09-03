#!/bin/sh
set -eu

unset LUAROCKS_SYSCONFDIR LUAROCKS_CONFIG LUA_PATH LUA_CPATH LUA_INIT || true

LUA_VERSION=5.1.5
LUA_URL=https://www.lua.org/ftp/lua-5.1.5.tar.gz
LUA_SHA256=2640fc56a795f29d28ef15e13c34a47e223960b0240e8cb0a82d9b0738695333
LUAROCKS_VERSION=3.13.0
LUAROCKS_URL=https://luarocks.github.io/luarocks/releases/luarocks-3.13.0.tar.gz
LUAROCKS_SHA256=245bf6ec560c042cb8948e3d661189292587c5949104677f1eecddc54dbe7e37

ROOT="${XDG_DATA_HOME:-$HOME/.local/share}/toku"
REBUILD=0

usage () {
  printf 'usage: sh setup-toku.sh [--root DIR] [--rebuild]\n'
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
fi

if [ "$REBUILD" -eq 1 ]; then
  say "rebuilding toolchain, keeping $ROOT/rocks"
  rm -rf "$ROOT/lua" "$ROOT/luarocks" "$SRC"
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

CFG="$ROOT/luarocks/etc/luarocks/config-5.1.lua"
[ -f "$CFG" ] || die "luarocks config not found: $CFG"
grep -q 'name = "toku"' "$CFG" ||
  printf 'rocks_trees = {\n  { name = "toku", root = "%s/rocks" },\n}\n' "$ROOT" >> "$CFG"

for lock in "$ROOT/rocks/lockfile.lfs" "$ROOT/rocks/lib/luarocks/lockfile.lfs"; do
  if [ -e "$lock" ]; then
    say "clearing stale lock $lock"
    rm -f "$lock"
  fi
done

if [ "$REBUILD" -eq 1 ] || [ ! -x "$ROOT/rocks/bin/toku" ]; then
  say "installing santoku-cli into $ROOT/rocks"
  (cd "$ROOT" &&
    PATH="$ROOT/rocks/bin:$ROOT/luarocks/bin:$ROOT/lua/bin:$PATH" \
    LUAROCKS_CONFIG="$CFG" \
    "$ROOT/luarocks/bin/luarocks" install santoku-cli)
  [ -x "$ROOT/rocks/bin/toku" ] || die "santoku-cli install did not produce $ROOT/rocks/bin/toku"
fi

CLI_VERSION="$("$ROOT/rocks/bin/toku" --version 2>/dev/null | awk '{print $2}')"
[ -n "$CLI_VERSION" ] || CLI_VERSION=unknown

printf 'return {\n  cli = "%s",\n  created = "%s",\n  lua = "%s",\n  luarocks = "%s",\n  mode = "managed",\n  platform = "%s",\n}\n' \
  "$CLI_VERSION" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$LUA_VERSION" "$LUAROCKS_VERSION" "$PLAT" \
  > "$MANIFEST"

say "managed toolchain ready at $ROOT"
say "managed toku: $ROOT/rocks/bin/toku"
say "optional PATH wiring:"
say "  export PATH=\"$ROOT/rocks/bin:$ROOT/luarocks/bin:$ROOT/lua/bin:\$PATH\""
say "verify with: toku doctor"
