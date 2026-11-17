#!/usr/bin/env bash
# Fetch and build the pinned versions of the benchmarked shells into bench/.tools/.
# Requires: git, go (>=1.25), node (>=22), npm.
set -euo pipefail
cd "$(dirname "$0")"
T=.tools
mkdir -p "$T/bin"

GBASH_REV=64eb59678c116708f96c9172da15a0ed52dd8daf      # 2026-10-23
RSHELL_REV=d59917e60a341380c91996fefb3afc676e303b5a     # 2026-11-03, last commit of the archived standalone repo
JUST_BASH_VERSION=3.6.1
TINYSANDBOX_VERSION=0.9.0

clone() { # name url rev
  [ -d "$T/$1/.git" ] || git clone -q "$2" "$T/$1"
  git -C "$T/$1" fetch -q --depth 1 origin "$3" && git -C "$T/$1" checkout -q "$3"
}

clone gbash https://github.com/ewhauser/gbash "$GBASH_REV"
(cd "$T/gbash/contrib/extras" && GOBIN="$PWD/../../../bin" go install ./cmd/gbash-extras)

clone rshell https://github.com/DataDog/rshell "$RSHELL_REV"
(cd "$T/rshell" && GOBIN="$PWD/../bin" go install ./cmd/rshell)

mkdir -p "$T/jb" && (cd "$T/jb" && [ -f package.json ] || npm init -y >/dev/null) && (cd "$T/jb" && npm i -s "just-bash@$JUST_BASH_VERSION")
mkdir -p "$T/ts" && (cd "$T/ts" && [ -f package.json ] || npm init -y >/dev/null) && (cd "$T/ts" && npm i -s "@tinysandbox/tinysandbox@$TINYSANDBOX_VERSION")

# Policy adapters (bench/POLICY.md): Go programs embedding gbash and rshell against the clones above.
(cd adapters/gbash-policy && GOWORK=off GOFLAGS=-mod=mod go build -o ../../.tools/bin/gbash-policy .)
(cd adapters/rshell-policy && GOWORK=off GOFLAGS=-mod=mod go build -o ../../.tools/bin/rshell-policy .)
