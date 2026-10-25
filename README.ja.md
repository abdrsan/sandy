# Sandy

<img src="Resources/AppIcon.png" alt="Sandy" width="160">

[English](README.md) · [Русский](README.ru.md) · [Қазақша](README.kk.md) · [Deutsch](README.de.md) · [Français](README.fr.md) · [Español](README.es.md) · [简体中文](README.zh-Hans.md) · [日本語](README.ja.md)

詳しい設定ガイド：[English](README.md) · [Русский](README.ru.md)。
スマートフォンからのアクセスは開発予定です。Sandy は MIT ライセンスの
[Cyclop](https://github.com/akalikbergenov/cyclop) を基にしています。

MacBook のノッチを作業用パネルに変える、macOS ネイティブのユーティリティです。
ノッチにポインタを合わせると、メディア操作、ファイルシェルフ、クリップボード履歴、定型文、
カレンダー、翻訳、通貨換算、テレプロンプター、メモを開けます。

**エージェント**タブでは、ローカルの `sandy-agent` ヘルパーを使って、対応する
Claude Code と Codex のセッションを監視します。同時進行のセッション、現在の操作、
プロジェクト別の保存済み統計を表示します。回答の完了、入力待ち、エラーの通知は任意です。
設定で監視とソースを有効にしてください。Claude フックは専用ボタンを押した場合にのみ
インストールされます。設定方法と制限は[エージェントの監視](docs/agent-monitor.md)（ロシア語）を参照してください。

Sandy は Abdirakhym が開発しています。プロジェクトはバージョン **0.1.0** から
独立した Git 履歴を使用しています。第三者のコードに関する帰属表示は
`THIRD_PARTY_NOTICES.md` に記載されています。

## 言語

英語、ロシア語、カザフ語、ドイツ語、フランス語、スペイン語、簡体字中国語、日本語に対応しています。
「設定 → 一般 → 言語」で選択すると、パネルの表示言語がすぐに切り替わります。
「システムの言語」は macOS の言語設定に従います。システムの許可ダイアログは
Sandy を再起動した後に選択した言語を使用します。表示言語を変えても、翻訳タブの言語ペアは変わりません。

## キーボードショートカット

**Control + Option + スペース**で、ポインタのある画面にパネルを開きます。
同じショートカット、Esc、または別のアプリのクリックで閉じます。
キーボードで操作している間はパネルが開いたままになります。
「設定 → 一般」で別の組み合わせを選ぶか、ショートカットを無効にできます。
この機能にアクセシビリティの許可は必要ありません。

## ビルドと起動

macOS 15 以降と Swift 6 が必要です。Xcode Command Line Tools のみでもビルドできます。
プロジェクトのディレクトリで実行してください。

```sh
./Scripts/bundle.sh
open build/Sandy.app
```

ローカルビルドには ad-hoc 署名を使用します。Developer ID で署名し、Apple の公証を受けた
リリースを公開するには、ご自身の Apple Developer 認証情報が必要です。
[署名手順](docs/signing.md)（ロシア語）を参照してください。

```sh
./Scripts/test.sh        # テストと翻訳の整合性を確認
./Scripts/test-helper.sh # ビルド後にメディアヘルパーを確認
./Scripts/dmg.sh         # build/Sandy-0.1.0.dmg を作成
```

バージョンは `Scripts/version` で指定します。`Scripts/release.sh` を使用する前に、
ご自身のリモートリポジトリを設定してください。

## データと許可

- アプリ識別子：`com.abdirakhym.sandy`。
- 設定、定型文、メモ：`~/Library/Application Support/Sandy`。
- クリップボードの画像：`~/Pictures/Sandy`。
- カレンダーとキーボードロックは、それぞれの機能を使用したときにカレンダーとアクセシビリティの許可を求めます。
- エージェントの通知の許可は、通知を有効にした場合にのみ求めます。履歴は
  `~/Library/Application Support/Sandy/Agents/history.json` に保存されます。
  監視画面はプロンプトや回答を保存しません。
- 翻訳には macOS の Translation フレームワークとダウンロード済みの言語パックを使用します。
- 通貨換算は公開の為替レートを取得します。Spotify の代替処理ではアートワークをダウンロードする場合があります。
  エージェントの統計はこの Mac に保存され、テレメトリや自動更新サービスはありません。

Sandy は独自の設定と保存領域を使用します。ほかのアプリのデータは自動では取り込みません。
詳細は [SECURITY.md](SECURITY.md)（ロシア語）を参照してください。

## 開発

SwiftUI と AppKit のコードは `Sources/Sandy`、メディアヘルパーは
`Sources/SandyMediaHelper`、翻訳とアイコンは `Resources`、ビルドとパッケージ化の
スクリプトは `Scripts` にあります。

動作を変更する前に、[アーキテクチャ](docs/architecture.md)（英語）、
[開発ガイド](CONTRIBUTING.md)と[リリース前の確認項目](docs/release-checklist.md)（ロシア語）をお読みください。
Now Playing は macOS の非公開フレームワークとシステムの Perl ヘルパーを使います。
今後の macOS の変更に伴い、修正が必要になる場合があります。App Store での配布には適していません。

## ライセンス

[MIT](LICENSE)。ソースコードやアプリを配布する場合は、ライセンスと第三者コードの
帰属表示を保持してください。アプリに同梱する文書は `Sandy.app/Contents/Resources` にあります。
