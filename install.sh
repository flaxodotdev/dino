#!/usr/bin/env sh
# dino installer — Flaxo (https://github.com/flaxodotdev/dino)
# Usage: curl -fsSL https://raw.githubusercontent.com/flaxodotdev/dino/master/install.sh | sh
#        curl -fsSL https://raw.githubusercontent.com/flaxodotdev/dino/master/install.sh | sh -s -- --prefix ~/.local
set -eu

REPO="flaxodotdev/dino"
VERSION="${DINO_VERSION:-0.0.1}"
PREFIX="${PREFIX:-/usr/local}"
BIN_DIR=""
INSTALL_PATH=""

# parse args
while [ $# -gt 0 ]; do
  case "$1" in
    --prefix) PREFIX="$2"; shift 2;;
    --prefix=*) PREFIX="${1#--prefix=}"; shift;;
    --version) VERSION="$2"; shift 2;;
    --version=*) VERSION="${1#--version=}"; shift;;
    --help|-h)
      echo "Usage: install.sh [--prefix DIR] [--version VERSION]"
      echo "  --prefix  install dir (default: /usr/local, fallback: ~/.local if not writable)"
      echo "  --version release tag without v (default: 0.0.1, use 'latest' for latest)"
      exit 0;;
    *) echo "unknown arg: $1" >&2; exit 1;;
  esac
done

# detect OS/arch
OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"

case "$OS" in
  darwin) OS="macos" ;;
  linux)  OS="linux" ;;
  *) echo "unsupported OS: $OS (only macos/linux)" >&2; exit 1;;
esac

case "$ARCH" in
  x86_64|amd64) ARCH="x86_64" ;;
  arm64|aarch64) ARCH="aarch64" ;;
  *) echo "unsupported arch: $ARCH" >&2; exit 1;;
esac

# map to release asset
# assets are: dino-macos-universal, dino-aarch64-macos, dino-x86_64-macos,
#             dino-x86_64-linux-musl, dino-aarch64-linux-musl, etc.
if [ "$OS" = "macos" ]; then
  # prefer universal on macos
  ASSET="dino-macos-universal"
  # fallback to arch-specific if universal missing
  FALLBACK="dino-${ARCH}-macos"
else
  # prefer static musl on linux
  ASSET="dino-${ARCH}-linux-musl"
  FALLBACK="dino-${ARCH}-linux-gnu"
fi

# resolve version -> tag
if [ "$VERSION" = "latest" ]; then
  TAG="latest"
  URL="https://github.com/${REPO}/releases/latest/download/${ASSET}.tar.gz"
  URL_FALLBACK="https://github.com/${REPO}/releases/latest/download/${FALLBACK}.tar.gz"
else
  # strip leading v
  VERSION="${VERSION#v}"
  TAG="v${VERSION}"
  URL="https://github.com/${REPO}/releases/download/${TAG}/${ASSET}.tar.gz"
  URL_FALLBACK="https://github.com/${REPO}/releases/download/${TAG}/${FALLBACK}.tar.gz"
fi

# choose bin dir
mkdir -p "$PREFIX/bin" 2>/dev/null || true
if [ -w "$PREFIX/bin" ] 2>/dev/null; then
  BIN_DIR="$PREFIX/bin"
else
  # fallback to ~/.local
  BIN_DIR="$HOME/.local/bin"
  mkdir -p "$BIN_DIR"
  echo "note: $PREFIX not writable, installing to $BIN_DIR (add to PATH)" >&2
fi
INSTALL_PATH="$BIN_DIR/dino"

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT INT TERM

echo "→ dino $TAG ($OS/$ARCH) → $INSTALL_PATH" >&2

# download with curl or wget
download() {
  _url="$1"
  _out="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$_url" -o "$_out"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$_out" "$_url"
  else
    echo "curl or wget required" >&2; exit 1
  fi
}

TARBALL="$TMPDIR/dino.tar.gz"
if ! download "$URL" "$TARBALL" 2>/dev/null; then
  echo "asset $ASSET not found, trying $FALLBACK" >&2
  URL="$URL_FALLBACK"
  ASSET="$FALLBACK"
  download "$URL" "$TARBALL"
fi

# extract (tar.gz contains single file dino-XXX)
tar -xzf "$TARBALL" -C "$TMPDIR"

# find binary inside (may be nested)
BIN_SRC="$(find "$TMPDIR" -type f -name "dino-*" | head -n 1)"
if [ -z "$BIN_SRC" ]; then
  # try direct file (if asset was raw binary not tar? fallback)
  BIN_SRC="$TARBALL"
fi
# if tar contained single file named dino-*, rename to dino
if [ -f "$BIN_SRC" ]; then
  # ensure executable
  chmod +x "$BIN_SRC"
  # move to install path (need sudo if not writable)
  if [ -w "$BIN_DIR" ]; then
    mv -f "$BIN_SRC" "$INSTALL_PATH"
  else
    echo "→ trying sudo mv to $INSTALL_PATH" >&2
    sudo mv -f "$BIN_SRC" "$INSTALL_PATH"
  fi
else
  echo "failed to find binary in tarball" >&2; exit 1
fi

chmod +x "$INSTALL_PATH"

echo "✓ installed dino $TAG to $INSTALL_PATH" >&2
if ! command -v dino >/dev/null 2>&1; then
  echo "  add to PATH: export PATH=\"$BIN_DIR:\$PATH\"" >&2
else
  echo "  run: dino" >&2
fi

# verify
if [ -x "$INSTALL_PATH" ]; then
  echo "→ $(ls -lh "$INSTALL_PATH" | awk '{print $9, $5}')" >&2
fi
