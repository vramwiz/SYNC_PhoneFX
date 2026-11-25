
# SYNC_PhoneFX 作業ノート

## プロジェクト

- Delphi プロジェクトはルートの `SYNC_PhoneFX.dproj`。AviUtl2 のラベルは `SYNC`、プラグイン名は「スマホ演出」。
- `SYNC_Mine` から Win64 のビルド設定、AviUtl2 SDK 定義、フィルターテーブル登録、描画とアイコン生成の必要部分を継承した。
- SDK の入力メディアオブジェクトとして登録する。標準の「映像再生」に座標・回転・透明度を任せる。映像と音声は別コールバックで、各オブジェクトの作業領域も映像・音声別に持つ。
- 筐体の基準は MINE の縦型と同じ420×820。画面の左上は (14, 18)、寸法は392×784、角丸は29、カメラ部は中央上部の84×16。画面を切り抜いた外枠と透過面を描き、SDK へ RGBA を渡す。
- キャラ51件は `Source\Lib\CharacterResources\SerifCharaVectorResource.RES` を埋め込み、既存の VectorRenderer で透過 PNG にする。生成先はマイドキュメントの `SYNC_PhoneFX\Icons\<リソース署名>\alpha`。指定した画像はパスで参照する。

## ビルド

Delphi 37.0 の IDE で `SYNC_PhoneFX.dproj` を開き、Win64 で Debug または Release をビルドする。DCU は `Win64\Debug\DCU` または `Win64\Release\DCU` に出力する。ビルド後イベントは DLL を `SYNC_PhoneFX.auf2` にコピーし、DLL を削除する。Release は RSM も削除する。

```powershell
cmd /c 'call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat" && msbuild SYNC_PhoneFX.dproj /t:Build /p:Config=Debug /p:Platform=Win64'
cmd /c 'call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat" && msbuild SYNC_PhoneFX.dproj /t:Build /p:Config=Release /p:Platform=Win64 /p:DCC_ExeOutput=.\Win64\Release'
```

既定の出力先は `C:\ProgramData\aviutl2\Plugin\SYNC_PhoneFX`。シェルからの検証では `/p:DCC_ExeOutput` でプロジェクト内へ出力できる。新しいユニットは `.dpr` の `in` 指定と `.dproj` の `DCCReference` を両方更新する。

## ソース配置

- `Source/Common/Effects` は共有タイムライン、タップ座標と時刻、振動、表示時計を担当する。
- `Source/Common/Render` は GDI+ 描画、円形クリッピング、合成音の生成を担当する。シーク位置と音声サンプル位置から結果を計算する。
- `Source/Common/Images` は組み込みキャラの列挙・透過 PNG 生成を担当する。
- `Source/Plugin/Filter` はパラメータ登録、設定の読み取り、AviUtl2 の映像・音声コールバックを担当する。
- `Source/Lib` は SDK 型およびフィルターテーブルの共通基盤。日本語を含む Delphi ソースは UTF-8 BOM、改行は CRLF とする。

## Setup

`Setup\make_release_zip.bat` は `Win64\Release\SYNC_PhoneFX.auf2` を収録したZIPを作成し、`Setup\SYNC_PhoneFX.catalog.json` にXXH3-128を記録する。詳細は [Setup の作業手順](Setup/README.md) を参照。

共通ユニットは `Source\Lib` に収録している。キャラ素材を更新する場合は、Delphi の環境を設定したうえで `Source\Lib\CharacterResources` から `brcc32 SerifCharaVectorResource.rc` を実行する。

## 確認

- Win64 Debug / Release の両構成を Delphi 37.0 でビルドした。
- 各 AUF2 を直接読み込み、登録項目と既定値、23種類の描画、逆シークでの画素一致、ビデオ通話の透明領域、組み込みアイコン、効果音の繰り返しと音量を検証した。
- 画面操作を使った検証は行っていない。
