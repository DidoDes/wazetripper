#!/usr/bin/env bash
# Runs INSIDE the toolchain container (cwd = repo root); called by verify_waze_apks() in lib.sh,
# which passes the expected values in the environment. Fails unless apk/ holds genuine Waze:
#  - base.apk and every split_*.apk verify with apksigner and are signed ONLY by WAZE_CERT_SHA256;
#  - base.apk is WAZE_PACKAGE at WAZE_VERSION / WAZE_VERSION_CODE;
#  - base.apk matches WAZE_BASE_SHA256, when that optional pin is set.
set -euo pipefail

: "${WAZE_CERT_SHA256:?}" "${WAZE_PACKAGE:?}" "${WAZE_VERSION:?}" "${WAZE_VERSION_CODE:?}"
WAZE_BASE_SHA256="${WAZE_BASE_SHA256:-}"

fail() {
    echo "FATAL: $*" >&2
    echo "Delete the apk/ folder and run scripts/fetch-apk.sh again (or try APK_SOURCE=google-play)." >&2
    exit 1
}

shopt -s nullglob
apks=(apk/base.apk apk/split_*.apk)
[ -f apk/base.apk ] || fail "apk/base.apk missing"

for a in "${apks[@]}"; do
    if ! out="$(apksigner verify --print-certs "$a" 2>&1)"; then
        echo "$out" >&2
        fail "$a: the APK signature does not verify (corrupt or tampered file)"
    fi
    digests="$(printf '%s\n' "$out" \
        | sed -nE 's/^Signer #[0-9]+ certificate SHA-256 digest: *([0-9a-fA-F]+).*/\1/p' \
        | tr 'A-F' 'a-f' | sort -u)"
    [ -n "$digests" ] || fail "$a: no signer certificate found"
    if [ "$digests" != "$WAZE_CERT_SHA256" ]; then
        fail "$a is not signed by Waze's certificate (found: $(printf '%s ' "$digests" | tr '\n' ' '))"
    fi
done
echo "signature: ${#apks[@]} apk(s) signed by Waze's certificate"

badging="$(aapt2 dump badging apk/base.apk 2>/dev/null | grep -m1 '^package:' || true)"
[ -n "$badging" ] || fail "aapt2 could not read apk/base.apk"
echo "$badging"
field() { printf '%s\n' "$badging" | sed -nE "s/.* $1='([^']*)'.*/\1/p"; }
[ "$(field name)" = "$WAZE_PACKAGE" ] || fail "apk/base.apk is $(field name), not $WAZE_PACKAGE"
[ "$(field versionName)" = "$WAZE_VERSION" ] || fail "apk/base.apk is version $(field versionName), not $WAZE_VERSION"
[ "$(field versionCode)" = "$WAZE_VERSION_CODE" ] || fail "apk/base.apk is versionCode $(field versionCode), not $WAZE_VERSION_CODE"

sum="$(sha256sum apk/base.apk | cut -d' ' -f1)"
echo "apk/base.apk sha256: $sum"
if [ -n "$WAZE_BASE_SHA256" ] && [ "$sum" != "$(printf '%s' "$WAZE_BASE_SHA256" | tr 'A-F' 'a-f')" ]; then
    fail "apk/base.apk does not match WAZE_BASE_SHA256 ($WAZE_BASE_SHA256)"
fi
echo "Waze signature and version OK"
