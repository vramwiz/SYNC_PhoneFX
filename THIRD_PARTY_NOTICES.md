# ライセンスと使用コンポーネント

スマホ演出（SYNC_PhoneFX） Copyright (c) 2026 VRAMの魔術師

プログラムのソースコードは GNU General Public License v3.0（GPL-3.0）です。[ライセンス全文](LICENSE) · [v1.0.0 のソースコード](https://github.com/vramwiz/SYNC_PhoneFX/tree/v1.0.0)

- **SYNC_Mine** — Delphi プロジェクト、AviUtl2 への登録、透過描画、スマホ筐体と円形アイコンの描画、ベクターデータからのPNG生成を流用しています。[SYNC_Mine](https://github.com/vramwiz/SYNC_MINE)
- **SYNC_Nicomea / Syncroh2 / SYNC_Lyrics** — SYNC_Mine が継承した AviUtl2 SDK の Delphi 型定義とフィルターテーブルの登録処理を使用しています。
- **AviUtl2PluginLib** — VectorRenderer、VectorRendererData、VectorRendererImageList、RTTI保存基盤、SectionFileManager、SerifCharaVectorResource を使用しています。対応するユニットと、埋め込んだ画像リソースのデータを公開ソースに収録しています。
- **実行環境** — Windows の GDI+ と Delphi RTL / VCL を使用します。描画と音声の出力には AviUtl2 のフィルタープラグイン API を使用します。

## 画像素材と効果音

- 組み込みキャラのアイコンは、既存の `SerifCharaVectorResource` から生成します。キャラクターと、利用者が指定した画像には各素材の利用条件が適用されます。
- README のプレビューはプラグインから出力したサンプル画面です。
- 配布版の着信音・通知音・アラーム・タップ音などは、本プラグイン内で生成する自作の合成音です。生成音は動画作品に使用できます。
