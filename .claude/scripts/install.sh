#!/bin/bash
# /install コマンド専用: Release ビルドして /Applications/FrameBezelApp.app を置き換える。
# /Applications への書き込みはこのスクリプトだけに許可している（.claude/commands/install.md の allowed-tools）。
# 置き換え先とビルド成果物のパスは固定で、引数では変えられない。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SRC="$ROOT/build/Build/Products/Release/FrameBezelApp.app"
DEST="/Applications/FrameBezelApp.app"

cd "$ROOT"
xcodebuild -project FrameBezelApp.xcodeproj -scheme FrameBezelApp -configuration Release \
  -derivedDataPath build build | tail -n 3

[ -d "$SRC" ] || { echo "エラー: ビルド成果物がありません: $SRC" >&2; exit 1; }

if pgrep -x FrameBezelApp >/dev/null; then
  echo "注意: FrameBezelApp が起動中です。置き換え後に終了して起動し直してください。"
fi

rm -rf "$DEST"
cp -R "$SRC" "$DEST"
echo "配置しました: $DEST"
