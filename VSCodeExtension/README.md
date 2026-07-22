# TickTime for VS Code

TickTime macOSアプリへ、作業中のリポジトリ・ブランチ・言語・ファイルを15秒ごとに記録します。
データは `~/Library/Application Support/TickTime/inbox` を経由し、ネットワークには送信されません。
エディタ、統合ターミナル、Source Controlを利用中でも、VS Codeが前面にありMacを操作している間はリポジトリ時間として記録します。統合ターミナルはVS CodeのShell Integrationが作業ディレクトリを取得できる場合に、そのGitリポジトリへ記録します。取得できない場合は誤ったリポジトリへ付けず、ターミナル区間をスキップします。

## インストール

1. VS Codeで「Extensions: Install from VSIX...」を実行します。
2. `TickTime-vscode-0.1.0.vsix` を選びます。
3. VS Codeを再読み込みし、TickTime.appを起動します。

ステータスバーの `TickTime` をクリックするとダッシュボードを開けます。
