#!/bin/zsh
# Verify that two different binaries signed with the local identity share a DR.
set -eu
umask 077
signing_identity="${CALENDAR_STUDIO_SIGNING_IDENTITY:-Calendar Studio Local Development}"
verification_dir=$(mktemp -d /private/tmp/calendar-studio-signature-check.XXXXXX)
trap 'rm -rf "$verification_dir"' EXIT
for version in 1 2; do
    printf 'int main(void) { return %s; }\n' "$version" > "$verification_dir/version$version.c"
    xcrun clang -target arm64-apple-macos14.0 "$verification_dir/version$version.c" -o "$verification_dir/version$version"
    codesign --force --sign "$signing_identity" --identifier com.devon.calendarstudio "$verification_dir/version$version"
    codesign --verify --strict "$verification_dir/version$version"
    codesign -d -r- "$verification_dir/version$version" 2>&1 | sed -n 's/^.*designated => /designated => /p' > "$verification_dir/requirement$version"
    codesign -dvvv "$verification_dir/version$version" 2>&1 | sed -n 's/^CDHash=//p' > "$verification_dir/hash$version"
done
[[ -s "$verification_dir/requirement1" && -s "$verification_dir/hash1" && -s "$verification_dir/hash2" ]]
cmp -s "$verification_dir/requirement1" "$verification_dir/requirement2"
if cmp -s "$verification_dir/hash1" "$verification_dir/hash2"; then
    echo 'Verification failed: test binaries must have different code hashes.' >&2
    exit 1
fi
if grep -iq 'cdhash' "$verification_dir/requirement1"; then
    echo 'Verification failed: identity still depends on the individual build hash.' >&2
    exit 1
fi
cat "$verification_dir/requirement1"
echo 'Verified: different code hashes, identical certificate-based identity, valid signatures.'
