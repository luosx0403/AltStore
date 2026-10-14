#!/bin/sh
set -eu

repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
altsign="$repo/Dependencies/AltSign"
patch="$repo/Patches/apple-80045-altsign.patch"

if [ ! -e "$altsign/.git" ]; then
    git -C "$repo" submodule update --init --recursive
fi

if git -C "$altsign" apply --reverse --check "$patch" 2>/dev/null; then
    printf '%s\n' 'Apple -80045 hotfix is already applied.'
elif git -C "$altsign" apply --check "$patch"; then
    git -C "$altsign" apply "$patch"
    printf '%s\n' 'Applied Apple -80045 hotfix to AltSign.'
else
    printf '%s\n' 'Patch does not match this AltSign revision. No files were changed.' >&2
    exit 1
fi
