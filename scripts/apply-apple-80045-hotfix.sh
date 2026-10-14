#!/bin/sh
set -eu

repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
altsign="$repo/Dependencies/AltSign"

if [ ! -e "$altsign/.git" ]; then
    git -C "$repo" submodule update --init --recursive
fi

for name in apple-80045-altsign.patch xcode-27-altsign-build.patch; do
    patch="$repo/Patches/$name"
    if git -C "$altsign" apply --reverse --check "$patch" 2>/dev/null; then
        printf '%s\n' "$name is already applied."
    elif git -C "$altsign" apply --check "$patch"; then
        git -C "$altsign" apply "$patch"
        printf '%s\n' "Applied $name to AltSign."
    else
        printf '%s\n' "$name does not match this AltSign revision. Stopping." >&2
        exit 1
    fi
done
