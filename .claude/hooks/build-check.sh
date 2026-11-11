#!/bin/bash
# Swift ファイル編集後にビルドし、エラーがあれば Claude に返す（exit 2）。
# 編集の途中状態でも走るため、警告は無視しエラー行だけ返す。
input=$(cat)
file=$(printf '%s' "$input" | /usr/bin/python3 -c 'import sys,json; print(json.load(sys.stdin).get("tool_input",{}).get("file_path",""))' 2>/dev/null)
case "$file" in
  *.swift) ;;
  *) exit 0 ;;
esac

cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0
out=$(xcodebuild -project FrameBezelApp.xcodeproj -scheme FrameBezelApp -configuration Debug \
  -derivedDataPath build -quiet build 2>&1)
if [ $? -ne 0 ]; then
  printf '%s\n' "$out" | grep -E 'error:' | sort -u | head -20 >&2
  exit 2
fi
exit 0
