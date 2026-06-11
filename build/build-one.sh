#!/bin/bash
# build/build-one.sh -- build ONE GNU tool statically linked against glibc.
#
# Usage:  build-one.sh <tool>
# Inputs:
#   ../tools.tsv             pin file: <tool> <version> <sha256>
# Outputs:
#   out/bin/<binaries>       stripped static binaries
#   out/manifest.<tool>.txt  list of binaries this tool contributed
#
# Per-tool configure flags are kept in this script (the table is the
# single source of truth for "what does it take to get $TOOL to build
# fully static on glibc"). If a new tool is added to tools.tsv, also
# add a case below.

set -euo pipefail

tool="${1:?usage: build-one.sh <tool>}"
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
out="$root/out"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# ------- look up version + sha from tools.tsv -----------------------------
pin="$(awk -v t="$tool" '
    $1 == t && $1 !~ /^#/ { print $2, $3; exit }
' "$root/tools.tsv")"
[ -n "$pin" ] || { echo "ERROR: $tool not in tools.tsv" >&2; exit 2; }
ver="${pin% *}"
sha="${pin#* }"

tarball="${tool}-${ver}.tar.xz"
url="https://ftp.gnu.org/gnu/${tool}/${tarball}"

echo "::group::fetch $tarball"
cd "$work"
curl -fsSL --retry 5 --retry-delay 5 -o "$tarball" "$url"
echo "$sha  $tarball" | sha256sum -c -
echo "::endgroup::"

echo "::group::unpack"
tar -xf "$tarball"
cd "${tool}-${ver}"
echo "::endgroup::"

# ------- per-tool configure invocations ------------------------------------
# Common rules:
#   --disable-nls        we never want translations in a sandbox; drops gettext
#   --disable-dependency-tracking   faster, deterministic
#   LDFLAGS=-static      the whole point
#   CFLAGS=-O2 -g0       small, no debug info (we strip anyway)
#   We pass --prefix=/ so 'make install DESTDIR=...' lays out a clean /bin tree
common_flags=(
    --disable-nls
    --disable-dependency-tracking
    --prefix=/
)
common_env=(
    CFLAGS="-O2 -g0"
    LDFLAGS="-static"
)

case "$tool" in
    coreutils)
        # coreutils is the sticky one. These flags drop libselinux, libacl,
        # libattr, libcap, gmp, openssl, libsystemd. We lose `ls -Z`,
        # `cp -a`-preserves-ACLs/xattrs, and arbitrary-precision factor/expr.
        # All acceptable in a sandbox.
        ./configure "${common_flags[@]}" \
            --disable-acl --disable-xattr \
            --without-selinux --without-gmp --without-libcap \
            --without-openssl --without-libsystemd \
            "${common_env[@]}"
        ;;
    tar)
        ./configure "${common_flags[@]}" \
            --without-selinux --without-posix-acls --without-xattrs \
            "${common_env[@]}"
        ;;
    findutils)
        ./configure "${common_flags[@]}" \
            --without-selinux \
            "${common_env[@]}"
        ;;
    grep|sed|diffutils|gzip)
        ./configure "${common_flags[@]}" "${common_env[@]}"
        ;;
    gawk)
        # gawk's loadable-extension machinery wants -ldl which fights static
        # linking; disable it. We also don't need MPFR (--disable-mpfr).
        ./configure "${common_flags[@]}" \
            --disable-extensions \
            --without-mpfr --without-readline \
            "${common_env[@]}"
        ;;
    *)
        echo "ERROR: no configure recipe for $tool" >&2
        exit 2
        ;;
esac

echo "::group::compile"
make -j"$(nproc)"
echo "::endgroup::"

echo "::group::install + strip"
destdir="$work/dest"
make install DESTDIR="$destdir"

mkdir -p "$out/bin"
manifest="$out/manifest.${tool}.txt"
: > "$manifest"

# Copy every regular executable from the install tree into out/bin,
# strip it, and record it. We ignore /share, /man, /info, /lib (gawk
# ships some .so but --disable-extensions kills the install side too).
find "$destdir/bin" -maxdepth 1 -type f -executable | sort | while read -r f; do
    name="$(basename "$f")"
    cp "$f" "$out/bin/$name"
    strip --strip-all "$out/bin/$name" 2>/dev/null || true
    printf '%s\n' "$name" >> "$manifest"
done
echo "::endgroup::"

echo "built $tool $ver -> $(wc -l < "$manifest") binaries"
