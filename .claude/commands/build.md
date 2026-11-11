---
description: Debug ビルドして、エラーがあれば要約して直す
allowed-tools: Bash(xcodebuild:*)
---
次を実行してビルドし、結果を報告してください。エラーがあれば原因を特定して修正し、再ビルドしてください。

```
xcodebuild -project FrameBezelApp.xcodeproj -scheme FrameBezelApp -configuration Debug -derivedDataPath build -quiet build
```
