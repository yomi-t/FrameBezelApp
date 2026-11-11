---
description: ユニットテスト（FrameBezelAppTests）を実行して結果を報告
allowed-tools: Bash(xcodebuild:*)
---
UI テストは除き、ユニットテストのみ実行してください。失敗したテストがあれば原因を調べて報告します（勝手にテストを書き換えない）。

```
xcodebuild -project FrameBezelApp.xcodeproj -scheme FrameBezelApp -derivedDataPath build -only-testing:FrameBezelAppTests test
```
