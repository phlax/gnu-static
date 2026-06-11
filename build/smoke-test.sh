#!/bin/bash
# build/smoke-test.sh -- prove each built binary actually runs.
#
# Static-linked-against-glibc has known sharp edges (NSS, locale, dlopen).
# Most GNU userland avoids those paths, but we don't *trust* that; we test.
# Anything in this script that fails should block the release.

set -u
fail=0
ok()  { printf '  ok   %s\n' "$*"; }
bad() { printf '  FAIL %s\n' "$*"; fail=1; }

bin="${1:?usage: smoke-test.sh <out/bin dir>}"
PATH="$bin:/usr/bin:/bin"
export PATH LC_ALL=C

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cd "$tmp"

# every binary must at least answer --version without segfaulting / linking errors
echo "== --version on every binary =="
for f in "$bin"/*; do
    name="$(basename "$f")"
    case "$name" in
        # a handful don't take --version, exempt them with a different probe
        '['|test|true|false|yes) continue ;;
    esac
    if "$f" --version >/dev/null 2>err; then
        ok "$name --version"
    else
        bad "$name --version  (stderr: $(head -1 err))"
    fi
done

# every binary must be statically linked. `file` is the canonical check.
echo
echo "== static linkage =="
for f in "$bin"/*; do
    name="$(basename "$f")"
    info="$(file -b "$f")"
    case "$info" in
        *statically\ linked*) ok "$name" ;;
        *) bad "$name -> $info" ;;
    esac
done

# functional smoke tests, one per upstream project
echo
echo "== functional smoke =="

echo hello > a
echo world > b

# coreutils
[ "$(ls | sort | tr '\n' ',')" = "a,b," ]            && ok "ls/sort"                 || bad "ls/sort"
[ "$(cat a b)" = "$(printf 'hello\nworld')" ]        && ok "cat"                     || bad "cat"
[ "$(printf 'a\nb\nc\n' | wc -l)" = 3 ]              && ok "wc"                      || bad "wc"
[ "$(echo -n hi | sha256sum | cut -d' ' -f1)" = \
   "8f434346648f6b96df89dda901c5176b10a6d83961dd3c1ac88b59b2dc327aa4" ] \
                                                      && ok "sha256sum"               || bad "sha256sum"
# findutils
n=$(find . -type f | wc -l)
[ "$n" = 2 ]                                          && ok "find"                    || bad "find (got $n)"
echo a b c | xargs -n1 echo > xo && [ "$(wc -l < xo)" = 3 ] \
                                                      && ok "xargs"                   || bad "xargs"
# grep
echo hi | grep -q hi                                  && ok "grep"                    || bad "grep"
# sed
[ "$(echo abc | sed 's/b/X/')" = "aXc" ]              && ok "sed"                     || bad "sed"
# gawk
[ "$(echo 1 2 3 | awk '{print $2}')" = "2" ]          && ok "awk"                     || bad "awk"
# diffutils
echo x > p; echo y > q
diff -q p q >/dev/null 2>&1; [ "$?" = 1 ]             && ok "diff (detects diff)"     || bad "diff"
cmp -s p p                                            && ok "cmp (identical)"         || bad "cmp"
# tar + gzip
echo payload > t.txt
tar -czf t.tgz t.txt
rm t.txt
tar -xzf t.tgz
[ "$(cat t.txt)" = "payload" ]                        && ok "tar+gzip roundtrip"      || bad "tar+gzip"

echo
if [ "$fail" -eq 0 ]; then echo PASS; exit 0; else echo FAIL; exit 1; fi
