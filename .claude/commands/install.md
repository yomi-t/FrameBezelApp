---
description: Release ビルドして /Applications に配置する
disable-model-invocation: true
allowed-tools: Bash(.claude/scripts/install.sh)
---
/Applications/FrameBezelApp.app を Release ビルドで置き換えます。

1. 先に、既存アプリを上書きしてよいかユーザーに確認する（既に /Applications にあるか、起動中かも伝える）。承認されなければ何もしない。
2. 承認されたら、プロジェクトのルートで `.claude/scripts/install.sh` を実行する（ビルドから配置までをこのスクリプトが行う。他の方法で /Applications に書き込まない）。
3. 結果（成功・失敗、起動中の注意）を報告する。
