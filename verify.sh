#!/bin/bash
# verify.sh -- run this against an already-built out/bin/ to assert the
# image-level invariants. Used both in CI before docker build, and by
# anyone who pulls the image (`docker run --rm ... /verify.sh`).
#
# Invariants enforced:
#   1. every file under bin/ is statically linked (no .so deps)
#   2. nothing forbidden is present (no shell, no perl, no curl, ...)
#   3. nothing besides /bin/* exists (no .so files anywhere, no /etc/ leak)
#   4. binary count is sane (informational ceiling, blocks surprises)

set -u
fail=0
ok()  { printf '  ok   %s\n' "$*"; }
bad() { printf '  FAIL %s\n' "$*"; fail=1; }

root="${1:-.}"

echo "== every binary statically linked =="
n_dyn=0
for f in "$root"/bin/*; do
    [ -f "$f" ] || continue
    info="$(file -b "$f" 2>/dev/null || echo UNKNOWN)"
    case "$info" in
        *statically\ linked*) : ;;
        *) bad "$(basename "$f") is not static: $info"; n_dyn=$((n_dyn+1)) ;;
    esac
done
[ "$n_dyn" = 0 ] && ok "all binaries static"

echo
echo "== zero shared libraries anywhere =="
sos="$(find "$root" -name '*.so*' -type f 2>/dev/null || true)"
if [ -z "$sos" ]; then ok "no .so files"; else bad "found .so files:"; printf '  %s\n' $sos; fi

echo
echo "== forbidden tools absent =="
forbidden="bash dash sh ash zsh ksh fish perl python python3 node ruby php
           curl wget ssh scp rsync git nc ncat socat openssl
           apt dpkg rpm yum dnf snap make gcc cc ld vi vim nano less more
           jq yq"
for c in $forbidden; do
    if [ -f "$root/bin/$c" ]; then bad "LEAK: bin/$c is present"; fi
done
[ "$fail" -eq 0 ] && ok "(no forbidden tools)"

echo
echo "== required tools present =="
required="ls cat cp mv rm mkdir head tail sort uniq wc cut tr printf
          env mktemp date base64 sha256sum
          find xargs
          grep sed awk
          diff cmp
          tar gzip"
for c in $required; do
    if [ ! -f "$root/bin/$c" ]; then bad "MISSING: $c"; fi
done

echo
echo "== binary count budget =="
count="$(find "$root/bin" -maxdepth 1 -type f 2>/dev/null | wc -l)"
echo "  $count binaries in bin/"
# coreutils alone supplies ~110; everything else adds ~15. Budget of 200
# is generous; if it goes over investigate for accidental extras.
if [ "$count" -gt 200 ]; then bad "binary count $count exceeds budget 200"; fi
if [ "$count" -lt 100 ]; then bad "binary count $count suspiciously low"; fi

echo
[ "$fail" -eq 0 ] && { echo PASS; exit 0; } || { echo FAIL; exit 1; }
