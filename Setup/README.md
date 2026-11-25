# SYNC_PhoneFX の配布パッケージ

利用者向けのインストールと使い方は [プロジェクトの README](../README.md) を参照してください。

## v1.0.0 の配布準備

1. Delphi で Win64 Release をビルドし、`Win64\Release\SYNC_PhoneFX.auf2` に出力します。コマンドは [作業ノート](../note.md) に記載しています。
2. xxHash の Windows x64 版から、`xxhsum.exe` を PATH または `Win64\Dependencies\xxHash-0.8.4\` に置きます。オプション `-XxhsumPath` でファイルを指定することもできます。[xxHash v0.8.4](https://github.com/Cyan4973/xxHash/releases/tag/v0.8.4)
3. `make_release_zip.bat` を実行します。既定以外のビルド先を使う場合は `-ReleaseDirectory` でフォルダーを指定します。
4. `SYNC_PhoneFX.catalog.json` の末尾バージョンと公開日を確認し、該当するタグの GitHub Release に `SYNC_PhoneFX.zip` を添付します。カタログもリリースから取得できます。

バッチは配布ZIPを作成し、ZIPに収録したAUF2のXXH3-128をカタログへ記録します。ZIPにはプラグイン、利用ガイド、プレビュー、ライセンス本文と使用コンポーネントの表示を収録します。
