#!/bin/sh
# ジェスチャー判定ロジックを Mac 上でビルドしてテストする
set -e
cd "$(dirname "$0")/.."
OUT="${TMPDIR:-/tmp}/spatialcue-tests"
swiftc -O -o "$OUT" Shared/WSProtocol.swift Shared/HeadTracking.swift Shared/Localization.swift Watch/Core/*.swift Tests/main.swift
"$OUT"
