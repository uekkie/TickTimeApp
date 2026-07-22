# TickTime

TickTimeは、作業時間をMac内だけに保存するWakaTime風のタイムトラッカーです。
macOSアプリとVS Code拡張機能の2つで動きます。

## できること

- VS Codeで開いているリポジトリの作業時間を自動記録
- リポジトリ、Gitブランチ、言語、相対ファイル名を記録
- 今日と直近7日の作業時間をダッシュボードに表示
- 操作がないときは自動で計測を停止
- データは `~/Library/Application Support/TickTime/activity.json` のみに保存

ネットワーク通信、アカウント、クラウド同期はありません。

## 使い方

1. `TickTime-macOS.zip` を展開し、`TickTime.app` を `/Applications` へ移動して起動します。
2. VS Codeで「Extensions: Install from VSIX...」を実行します。
3. `TickTime-vscode-0.1.0.vsix` を選び、VS Codeを再読み込みします。
4. VS Codeでリポジトリを開いて作業すると、15秒ほどでダッシュボードへ反映されます。

初回起動時にmacOSの警告が出る場合は、FinderでアプリをControlキーを押しながらクリックして「開く」を選択してください。

## ソースから開く

Xcodeで `Package.swift` を開いて実行できます。コマンドラインでは次のコマンドでテストできます。

```sh
swift test --disable-sandbox
cd VSCodeExtension && node --test
```

アプリ、VS Code拡張、ソースアーカイブをまとめて作る場合は次を実行します。成果物はアプリのバージョンに対応する `Releases/<version>`（例: `Releases/0.1.0`）に生成されます。

```sh
./Packaging/package.sh
```

## 計測の仕組み

VS Code拡張機能は、VS Codeがフォーカス中かつ直近に操作がある間、ハートビートを15秒ごとに書き出します。書き出し先は `~/Library/Application Support/TickTime/inbox` です。macOSアプリがファイルを取り込んだ後、日別・リポジトリ別に集計します。

アプリと拡張機能の記録が重なった区間は、合計時間で二重加算しません。

## 現在の制限

- macOS 14以降、Apple Silicon向けです。
- リポジトリ集計はVS Code拡張機能からの記録が対象です。
- データのエクスポート、プロジェクト名の編集、GitHub連携はまだありません。
