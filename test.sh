#!/bin/sh
# test.sh — RFC 4648 test vectors for base64, plus a round-trip check.
set -e
fail=0

check() {
    got=$(printf '%s' "$1" | ./base64)
    [ "$got" = "$2" ] || { echo "FAIL encode '$1': got '$got' want '$2'"; fail=1; }
    got=$(printf '%s' "$2" | ./base64 -d)
    [ "$got" = "$1" ] || { echo "FAIL decode '$2': got '$got' want '$1'"; fail=1; }
}

check ""       ""
check "f"      "Zg=="
check "fo"     "Zm8="
check "foo"    "Zm9v"
check "foob"   "Zm9vYg=="
check "fooba"  "Zm9vYmE="
check "foobar" "Zm9vYmFy"

if [ "$fail" = 0 ]; then
    echo "All tests passed."
else
    exit 1
fi
