![version](https://img.shields.io/badge/version-17%2B-3E8B93)
![platform](https://img.shields.io/static/v1?label=platform&message=mac-intel%20|%20mac-arm%20|%20win-64&color=blue)
[![license](https://img.shields.io/github/license/miyako/4d-plugin-poppler)](LICENSE)
![downloads](https://img.shields.io/github/downloads/miyako/4d-plugin-poppler/total)

[English](README.md) | **日本語**

### 依存関係とライセンス

* [4D Plug-in SDK](https://github.com/4d/4D-Plugin-SDK) を使用して開発された本プラグインのソースコードは MIT ライセンスです。
* **Poppler**（共有ライブラリ）のライセンスについては [Poppler](https://poppler.freedesktop.org) を参照してください。
* 本プラグインのバイナリ製品のライセンスは、すべての依存ライブラリのライセンスに従います。
* Windows 版では、Poppler（GPL-2.0-or-later）およびその依存ライブラリ（GLib、Cairo、pixman、FreeType、libiconv、gettext-libintl（LGPL/MPL）、libpng、zlib、brotli など）が `Poppler.4DX` に**静的リンク**されています。そのため配布バイナリは GPL に基づく結合著作物となります。また LGPL コンポーネントを静的リンクしているため、受領者がそれらを再リンクできる必要があります（対応するソースは、すべての依存バージョンを固定している [`vcpkg.json`](vcpkg.json) から入手できます）。

#### Windows でのビルド

`Poppler.vcxproj` は vcpkg（`x64-windows-static-release`、静的 CRT）が生成する静的ライブラリをリンクします。

```
vcpkg install --triplet x64-windows-static-release --host-triplet x64-windows-static-release --overlay-triplets=vcpkg-triplets --x-install-root=vcpkg_installed
msbuild Poppler.sln /p:Configuration=Release /p:Platform=x64
```

`/p:PopplerLinkage=dynamic` を指定すると、代わりに `lib/windows64` の従来のインポートライブラリをリンクします。その場合は `test/Plugins/Poppler.bundle/Contents/Windows64` の DLL（および VC++ ランタイム）を `Poppler.4DX` と一緒に配布する必要があります。

リリースワークフローは、Windows ランナー上の vcpkg のコンパイラに合わせて、プロジェクトの v145 ツールセットを使用します。これらの静的ライブラリをリンクする際に、古いツールセットで上書きしないでください。ダウンロードの一時的な失敗に備えて、マニフェストで固定された vcpkg のブートストラップを最大 4 回（間隔 10、20、40 秒）試行します。ブートストラップに失敗するか `vcpkg.exe` が見つからない場合、依存関係のインストール前にジョブを停止します。ベースライン、トリプレット、バイナリキャッシュのキーは変更されていません。

# 4d-plugin-poppler

Poppler プラグインは PDF レンダリングライブラリ [Poppler](https://poppler.freedesktop.org/) を（SVG/PNG 出力には Cairo を介して）ラップし、4D に 3 つのコマンドを提供します。PDF ページの `Picture`（SVG または PNG）または SVG テキスト（`Text`）へのレンダリング、PDF のプレーンテキストの抽出、PDF のページ数の取得です。元の PDF は常に `Blob`（例：`DOCUMENT TO BLOB` で読み込んだもの）として渡し、ファイルパスでは渡しません。プラグイン自身はファイルシステムに一切アクセスしません。

| コマンド | 戻り値 | 用途 |
|---|---|---|
| [`PDF Convert`](#pdf-convert) | `Longint` | PDF の各ページを `Picture` 配列（任意の解像度の SVG または PNG）または `Text` 配列（SVG マークアップ）にレンダリングします。ページごとのコールバックとオプションオブジェクトを指定できます |
| [`PDF Get page count`](#pdf-get-page-count) | `Longint` | PDF のページ数を返します |
| [`PDF Get text`](#pdf-get-text) | `Longint` | 各ページのプレーンテキストを `Text` 配列に抽出します。ページごとのコールバックを指定できます |

**プラットフォーム:** Windows および macOS

---

## 動作要件とプラットフォームに関する注意

- 3 つのコマンドはすべて、プラグインのマニフェストで**スレッドセーフ**と宣言されています。
- 元の PDF は常に `Blob`（第 1 引数）です。`DOCUMENT TO BLOB` を使うか、生のバイトを BLOB 変数に読み込んで作成してください。プラグインにはパスやファイルを受け取る引数はありません。
- **ページ番号はすべての引数とコールバックで 1 始まり**です。ページ 1 が最初のページで、`PDF Convert`/`PDF Get text` が書き込む配列のインデックスと一致します。
- **開始/終了ページとパスワードは実質的に省略可能です。** 4D では末尾の引数を省略でき、省略した場合（または `0`/`""` を渡した場合）、プラグインが適切な既定値を使用します（各コマンドの説明を参照）。プラグイン付属のテストメソッドもこれを利用しており、[`PDF2SVG_TEST_EASY.4dm`](#例) は 7 つある `PDF Convert` の引数のうち 2 つだけを指定して呼び出しています。
- **末尾の `Text` 引数（`PDF Get text` と `PDF Get page count` の最後の引数）は内部変数に読み込まれますが、現在のソースではどこにも使われていません。** 渡しても効果はありません。付属のサンプルメソッドもすべて省略しています。現時点では予約済みとして扱い、仕様として当てにしないでください。
- **無効な PDF データやパスワードの誤りでは 4D のエラーは発生しません。** コマンドはエラーコード（各コマンドの表を参照）を返し、出力配列や変数は元のまま（通常は空）にします。必ず戻り値を確認してください。
- **コールバックメソッドが `True` を返すと残りのページの処理が中止され**、コマンドの戻り値は「ユーザーによる中止」のエラーコードになります。`PDF Convert`/`PDF Get text` を途中で止める方法はこれだけで、キャンセルやタイムアウトの引数はありません。

---

## PDF Convert

### シンタックス

```4d
$error:=PDF Convert($pdf; $pages; $startPage; $endPage; $password; $callback; $options) -> Longint
```

| 引数 | 型 | 説明 |
|---|---|---|
| `pdf` | Blob | PDF ファイルの生のバイト列。 |
| `pages` | Array Picture, Array Text | 出力配列。宣言済みの `ARRAY PICTURE` または `ARRAY TEXT`、あるいは未宣言の変数（プラグインが `ARRAY PICTURE` として宣言します）を渡します。それ以外の型の場合の動作は説明を参照してください。 |
| `startPage` | Longint | レンダリングする最初のページ（1 始まり）。省略するか `0`/負数を渡すと「1 ページ目から」になります。 |
| `endPage` | Longint | レンダリングする最後のページ（1 始まり）。省略するか、`0`、`startPage` 以下の値、ドキュメントのページ数を超える値を渡すと「最後のページまで」になります。 |
| `password` | Text | PDF のオーナー/ユーザーパスワード。暗号化されていないドキュメントでは省略するか `""` を渡します。 |
| `callback` | Text | 各ページのレンダリング後に呼び出されるプロジェクトメソッドの名前（説明を参照）。省略するか `""` を渡すと無効になります。 |
| `options` | Object | 出力形式、解像度、レンダリングのオプション。[オプション](#オプション)を参照してください。省略するか `Null`/`{}` を渡すと既定値（従来と同じ 72 DPI の SVG）になります。 |
| 戻り値 | Longint | 成功時は `0`。PDF データが無効かパスワードが誤っている場合は `-1`。`pages` が `Array Picture`/`Array Text` 以外（その他のサポートされない型）の場合、または `format` が `"png"` で `Array Text` を渡した場合は `-2`。コールバックが `True` を返して中止した場合は `-3`。`options` に無効な値（不明な `format`、0 以下の `dpi`、負の `width`/`height`）が含まれる場合は `-4`（配列は変更されません）。 |

### 説明

`PDF Convert` を呼び出した時点での `pages` の宣言型によって出力形式が決まります。
- **未宣言/`Null`** の変数 → プラグインが `Array Picture` として宣言します（`ARRAY PICTURE` と同等）。
- **`Array Picture` として宣言済み** → 既定では、各要素がそのページを **SVG** でレンダリングした `Picture` になります（`Array Text` で返されるものと同じ SVG マークアップ）。`options` の `format` に `"png"` を指定すると、Poppler が指定の解像度で直接レンダリングした **PNG** ビットマップになります。
- **`Array Text` として宣言済み** →（SVG のみ。`format` が `"png"` の場合は `-2`）各要素がそのページをレンダリングした **SVG マークアップ**（ページごとに完全な `<svg>...</svg>` ドキュメント）になります。配列の型は `Text` ですが、内容はプレーンテキストではなく SVG ソースです。ページごとの SVG はこの方法で返されます。`.svg` ファイルへの書き出し方は [`PDF2SVG_TEST_WITH_CB.4dm`](#例) を参照してください。
- **その他の型**（Blob 配列対応でビルドされていない限り `Array Blob` も含む）→ コマンドは何もせず、配列のサイズ変更や変更を行わずに直ちに `-2` を返します。

配列は常に PDF の総ページ数にリサイズされ、絶対ページ番号による 1 始まりのインデックスで格納されます（`startPage` に関係なく、要素 `pageInd` にページ `pageInd` が入ります）。`startPage`/`endPage` の範囲外のページは配列から削除されず、要素型の既定値（空の `Picture`、空文字列）のままになります。

### オプション

| プロパティ | 型 | 既定値 | 説明 |
|---|---|---|---|
| `format` | Text | `"svg"` | `"svg"`（ベクター）または `"png"`（ビットマップ）。大文字と小文字は区別しません。 |
| `dpi` | Real | `72` | 出力解像度。72 ではページは PDF ポイント単位のサイズになります（A4 = 595 × 842）。300 では A4 ページは 2479 × 3508 px（PNG）、または同じサイズの SVG になります。 |
| `width` | Real | — | 目標の幅（ピクセル、SVG ではユーザー単位）。`dpi` より優先され、ページの縦横比は保持されます。 |
| `height` | Real | — | 目標の高さ（ピクセル）。`dpi` より優先されます。`width` と `height` の両方を指定すると、ページはその枠の**内側**に収まるように縮小・拡大されます（サムネイルに便利です）。 |
| `transparent` | Boolean | `False` | PNG のみ。`False` では（PDF ビューアと同様に）白い背景を塗ります。`True` ではページの背景を透明のままにします。 |
| `antialias` | Boolean | `True` | `False` にすると図形とテキストのアンチエイリアスを無効にします。バーコードや FAX/OCR 処理など、輪郭のはっきりした 2 値に近い出力が必要な場合に便利です。 |
| `printing` | Boolean | `True` | `True` では印刷用にレンダリングします（Poppler の印刷用パス。印刷不可に設定された注釈やフォームフィールドは表示されません）。`False` では PDF ビューアの画面表示と同じようにレンダリングします。 |

**出力サイズ。** 既定では、各ページは PDF ページそのものの大きさ（PDF ポイント = 1/72 インチ単位）になります。たとえば A4 は 595 × 842、US レターは 612 × 792 で、4D では 72 DPI 相当で表示されます。変更するには `dpi`、`width`、`height` を使用します。ページは `/Rotate` を適用した向きでレンダリングされます。

PNG について:
- PNG は解像度情報（`pHYs` チャンク）を持つため、300 DPI のページは 300 DPI としてタグ付けされます。このメタデータを尊重するアプリケーション（高解像度表示や印刷時の 4D を含む）では、物理サイズで表示される場合があります。つまり、画面上の大きさは 72 DPI 版と同じで、より鮮明になります。`PICTURE PROPERTIES` やピクセル数は実際の解像度を反映します。
- 各辺は 32767 ピクセル（Cairo の上限）までです。それを超える指定は縦横比を保って縮小されます。メモリにも注意してください。レンダリング中は 1 ピクセルあたり 4 バイトが必要です（600 DPI の A4 ページで約 140 MB）。
- 埋め込み画像は出力解像度に合わせてリサンプリングされます。ベクターの内容とテキストは、どの解像度でも鮮明にラスタライズされます。

`callback` に有効なプロジェクトメソッド名を指定すると、各ページの配列要素が設定された**後に**、ページごとに 1 回、次のシグネチャで呼び出されます。

```4d
#DECLARE($pos : Integer; $total : Integer; $pageNumber : Integer; $page : Picture)->$stop : Boolean
```

（`pages` が `Array Text` の場合、`$page` は `Picture` ではなく `Text` 型になります。テキスト版のシグネチャは [`PDF2TEXT_CB.4dm`](#例) を参照してください。使い方は同じです。）`$pos` はこの呼び出しで処理済みのページ数（1 始まり、絶対ページ番号ではありません）、`$total` はこの呼び出しで処理する総ページ数（`endPage - startPage + 1`）、`$pageNumber` は 1 始まりの絶対ページ番号、`$page` はそのページのレンダリング結果です（配列の要素とは独立した新しいコピー）。以降のページの処理を中止するには、コールバックから `True` を返します。

パスワードの扱い: 空または省略された `password` は、`""` ではなく `NULL` として Poppler に渡されます。これは Poppler が「パスワードなし」と「空文字列のパスワード」を区別することに合わせたものです。

### 例

プラグイン付属のテストメソッド（コールバックなし、`PDF2SVG_TEST_EASY.4dm`）より:

```4d
$path:=Get 4D folder:C485(Current resources folder:K5:16)+"doc.pdf"

DOCUMENT TO BLOB:C525($path;$PDF)

ARRAY PICTURE:C279($pages;0)

$error:=PDF Convert ($PDF;$pages)

PICTURE PROPERTIES:C457($pages{1};$w;$h)

WRITE PICTURE FILE:C680(System folder:C487(Desktop:K41:16)+"doc-1.svg";$pages{1};".svg")
```

コールバック、ページ範囲、パスワードを指定する例（`PDF2SVG_TEST_WITH_CB.4dm` から下記の [`PDF2SVG_CB`](#pdf2svg_cb) を呼び出します）:

```4d
$path:=Get 4D folder:C485(Current resources folder:K5:16)+"doc.pdf"

DOCUMENT TO BLOB:C525($path; $PDF)

ARRAY PICTURE:C279($pages; 0)

$startPage:=0
$endPage:=0
$password:=""
$callback:="PDF2SVG_CB"

$error:=PDF Convert($PDF; $pages; $startPage; $endPage; $password; $callback)

PICTURE PROPERTIES:C457($pages{1}; $w; $h)

WRITE PICTURE FILE:C680(System folder:C487(Desktop:K41:16)+"doc-1.svg"; $pages{1}; ".svg")
```

ピクチャではなくページごとの SVG マークアップを得るために `Array Text` を渡す例:

```4d
ARRAY TEXT:C222($svgPages;0)
$error:=PDF Convert($PDF;$svgPages)
 // $svgPages{1} にはページ 1 の SVG マークアップがテキストとして入ります。
 // お使いの 4D のバージョンに合ったテキスト/ドキュメント書き込みコマンド
 // （例：TEXT TO DOCUMENT）で書き出してください。正確な構文は未検証です。
```

白い背景の高解像度 PNG（300 DPI）:

```4d
ARRAY PICTURE:C279($pages; 0)
$error:=PDF Convert($PDF; $pages; 0; 0; ""; ""; New object:C1471("format"; "png"; "dpi"; 300))
WRITE PICTURE FILE:C680(System folder:C487(Desktop:K41:16)+"doc-1.png"; $pages{1}; ".png")
```

200 × 200 ピクセルに収まる、背景が透明で画面表示どおりにレンダリングしたサムネイル:

```4d
ARRAY PICTURE:C279($thumbnails; 0)
$error:=PDF Convert($PDF; $thumbnails; 0; 0; ""; ""; New object:C1471("format"; "png"; "width"; 200; "height"; 200; "transparent"; True:C214; "printing"; False:C215))
```

2 倍（144 DPI）に拡大した SVG:

```4d
ARRAY PICTURE:C279($pages; 0)
$error:=PDF Convert($PDF; $pages; 0; 0; ""; ""; New object:C1471("dpi"; 144))
```

プラグインは各 SVG 文字列の所有権を出力配列に移します。以前のビルドでは代入直後に
その文字列を解放していたため、配列の要素が無効なメモリを指し、Windows で読み取りや
クリアの際に 4D がクラッシュすることがありました。コールバックには別に確保した文字列が
渡されるため、そのコピーを破棄しても配列は影響を受けません。

Windows または macOS の 4D テストプロジェクトでこの不具合の回帰テストを行うには、
`PDF2SVG_TEXT_TEST` を実行します。`Resources/doc.pdf` を使用し、コールバックの
有無それぞれで SVG 出力を確認し、配列を読み取る前にテキストの割り当てを繰り返し、
配列の再利用と明示的なクリアの両方で変換を繰り返します。

目的のページが見つかったらコールバックで早期に終了する例:

```4d
 // コールバックメソッド内
#DECLARE($pos : Integer; $total : Integer; $pageNumber : Integer; $page : Picture)->$stop : Boolean
$stop:=($pageNumber=$targetPage)
```

---

## PDF Get page count

### シンタックス

```4d
$error:=PDF Get page count($pdf; $password) -> Longint
```

| 引数 | 型 | 説明 |
|---|---|---|
| `pdf` | Blob | PDF ファイルの生のバイト列。 |
| `password` | Text | PDF のオーナー/ユーザーパスワード。暗号化されていないドキュメントでは省略するか `""` を渡します。 |
| *（未使用）* | Text | コマンドのシンタックスには宣言されていますが、現在のプラグインのビルドではまったく読み取られません。省略できます。 |
| 戻り値 | Longint | 成功時はページ数。PDF データが無効かパスワードが誤っている場合は `-1`。 |

### 説明

3 つのコマンドの中で最も単純なものです。ページ数を読み取るためだけに PDF を開き、直ちに解放します。配列やコールバックは使用しません。

### 例

このコマンド専用のテストメソッドはプラグインに付属していないため、この例は上記の他のテストファイルで確認済みの BLOB 読み込みパターンをもとにしています。

```4d
$path:=Get 4D folder:C485(Current resources folder:K5:16)+"doc.pdf"
DOCUMENT TO BLOB:C525($path;$PDF)

$count:=PDF Get page count($PDF)
If($count>=0)
    ALERT:C41("This PDF has "+String:C10($count)+" page(s).")
Else
    ALERT:C41("Could not read this PDF.")
End if
```

パスワードを指定する場合:

```4d
$count:=PDF Get page count($PDF;"correct horse battery staple")
```

---

## PDF Get text

### シンタックス

```4d
$error:=PDF Get text($pdf; $pages; $startPage; $endPage; $password; $callback) -> Longint
```

| 引数 | 型 | 説明 |
|---|---|---|
| `pdf` | Blob | PDF ファイルの生のバイト列。 |
| `pages` | Array Text | 出力配列。**`Array Text` として宣言済みである必要があります。** `PDF Convert` と異なり、このコマンドは配列の型を確認したり自動宣言したりしません。 |
| `startPage` | Longint | 抽出する最初のページ（1 始まり）。省略するか `0`/負数を渡すと「1 ページ目から」になります。 |
| `endPage` | Longint | 抽出する最後のページ（1 始まり）。省略するか、`0`、`startPage` 以下の値、ドキュメントのページ数を超える値を渡すと「最後のページまで」になります。 |
| `password` | Text | PDF のオーナー/ユーザーパスワード。暗号化されていないドキュメントでは省略するか `""` を渡します。 |
| `callback` | Text | 各ページのテキスト抽出後に呼び出されるプロジェクトメソッドの名前（説明を参照）。省略するか `""` を渡すと無効になります。 |
| *（未使用）* | Text | 受け付けますが、現在のプラグインのビルドでは効果はありません。省略できます。 |
| 戻り値 | Longint | 成功時は `0`。PDF データが無効かパスワードが誤っている場合は `-1`。コールバックが `True` を返して中止した場合は `-3`。 |

### 説明

`PDF Convert` の出力配列と異なり、ここでの `pages` はページごとの配列要素ではなく、ひとつの連続した文字列です。抽出した各ページのテキストは、`pages{pageNumber}` に書き込まれるのではなく、同じひとつの配列要素（`pages{1}`）に**追加**されます。ページごとにテキストを分けたい場合は、独自の区切り文字で分割するか、1 ページ分のテキストを受け取れるコールバックの `$page` 引数（下記）を使用してください。

`callback` に有効なプロジェクトメソッド名を指定すると、ページごとに 1 回、次のシグネチャで呼び出されます。

```4d
#DECLARE($pos : Integer; $total : Integer; $pageNumber : Integer; $page : Text)->$stop : Boolean
```

`$pos`、`$total`、`$pageNumber` は [`PDF Convert`](#pdf-convert) と同じです。`$page` はそのページから抽出したプレーンテキストです。以降のページの処理を中止するには `True` を返します。

### 例

プラグイン付属のテストメソッド（`PDF2TEXT_TEST_WITH_CB.4dm`、下記の [`PDF2TEXT_CB`](#pdf2text_cb) を呼び出します）より:

```4d
$path:=Get 4D folder:C485(Current resources folder:K5:16)+"test1.pdf"
DOCUMENT TO BLOB:C525($path; $PDF)

ARRAY TEXT:C222($pages; 0)

$startPage:=0
$endPage:=0
$password:=""
$callback:="PDF2TEXT_CB"

$error:=PDF Get text($PDF; $pages; $startPage; $endPage; $password; $callback)
```

最初の 3 ページだけをコールバックなしで抽出する例:

```4d
ARRAY TEXT:C222($pages;0)
$error:=PDF Get text($PDF;$pages;1;3)
If($error=0)
    ALERT:C41($pages{1})
End if
```

---

## 参照用ヘルパーメソッド

これらはプラグイン付属のテストプロジェクトのメソッドで、`PDF Convert` と `PDF Get text` が実際に呼び出すコールバックのシグネチャです。プラグインのコマンドではありませんが、`callback` 引数を使うには、いずれかの形に合ったメソッドが必要です。

### PDF2SVG_CB

**`PDF2SVG_CB ($pos : Integer; $total : Integer; $pageNumber : Integer; $page : Picture) -> $stop : Boolean`**

| 引数 | 型 | 説明 |
|---|---|---|
| `pos` | Integer | 現在の `PDF Convert` 呼び出しで処理済みのページ数（1 始まり）。 |
| `total` | Integer | この呼び出しで処理する総ページ数。 |
| `pageNumber` | Integer | レンダリングしたページの絶対ページ番号（1 始まり）。 |
| `page` | Picture | このページのレンダリング結果のピクチャ。 |
| 戻り値 | Boolean | `True` を返すと残りのページを中止します。 |

プラグインのソース（`PDF2SVG_CB.4dm`）より:

```4d
//%attributes = {"invisible":true}
#DECLARE($pos : Integer; $total : Integer; $pageNumber : Integer; $page : Picture)->$stop : Boolean
```

付属のスタブは何もしません（常に続行します）。実際の実装では、進捗を報告したり、届いたピクチャを順に保存したりできます。

```4d
#DECLARE($pos : Integer; $total : Integer; $pageNumber : Integer; $page : Picture)->$stop : Boolean
 // フォルダのコマンドはお使いの 4D のバージョンに合わせて選んでください。
 // WRITE PICTURE FILE のトークン（:C680）は上記のテストファイルで確認済みです
WRITE PICTURE FILE:C680($destinationFolder+"page"+String:C10($pageNumber)+".png";$page;".png")
$stop:=False
```

### PDF2TEXT_CB

**`PDF2TEXT_CB ($pos : Integer; $total : Integer; $pageNumber : Integer; $page : Text) -> $stop : Boolean`**

| 引数 | 型 | 説明 |
|---|---|---|
| `pos` | Integer | 現在の `PDF Get text` 呼び出しで処理済みのページ数（1 始まり）。 |
| `total` | Integer | この呼び出しで処理する総ページ数。 |
| `pageNumber` | Integer | 抽出したページの絶対ページ番号（1 始まり）。 |
| `page` | Text | このページから抽出したプレーンテキスト。 |
| 戻り値 | Boolean | `True` を返すと残りのページを中止します。 |

プラグインのソース（`PDF2TEXT_CB.4dm`）より:

```4d
//%attributes = {"invisible":true}
#DECLARE($pos : Integer; $total : Integer; $pageNumber : Integer; $page : Text)->$stop : Boolean
```

---

## エラー処理とトラブルシューティング

- **パスワードの誤りや破損した/PDF でない BLOB は 4D のエラーになりません。戻り値を確認してください。** 3 つのコマンドはすべて例外を発生させずに `-1`（`PDF2SVG_ERROR_InvalidSourceData`）を返します。`$error` を確認しないと、変更されない `Picture`/`Text` 配列や空のページ数は「何も起きなかった」ように見えます。
- **`pages` の型が誤っていると、`PDF Convert` は何も通知せずに `-2` を返します。** 渡した配列のサイズ変更やクリアは行いません。事前に `Array Picture` または `Array Text` 以外として宣言していた場合（無関係なコードで変数を再利用した場合など）、元の配列はそのままで `-2` が返されます。
- **`PDF Get text` では `pages` が `Array Text` として宣言済みである必要があります。** `PDF Convert` のような自動宣言はありません。呼び出す前に `ARRAY TEXT` で宣言してください。
- **コールバックが `True` を返すと、戻り値は `0` ではなく `-3` になります。** `$error=0` だけで「全ページ処理済み」と判断していると、ユーザーによる中止が別の種類の失敗に見えます。「途中で停止」と「PDF が無効」を区別したい場合は `-3` を個別に確認してください。
- **`PDF Get text` は全ページを 1 つの配列要素に追加します。** ページごとの要素ではないため、`pages{pageNumber}` にそのページだけのテキストが入っているとは考えないでください。ページを分けたい場合はコールバックの `$page` 引数を使用してください。
- **`options` が無効な場合（不明な `format`、0 以下の `dpi`、負の `width`/`height`）、`PDF Convert` は配列を変更せずに `-4` を返します。** 不明なプロパティは無視されます。
- **`PDF Get text` と `PDF Get page count` の末尾の `Text` 引数は、現在は効果がありません。** 付属のサンプルはすべて省略しています。何かに使えると考えないでください。
- **非常に大きな PDF**: 現在のプラグインのビルドでは、ページ/テキスト/ピクチャのデータサイズを内部で通常の `int` に読み込んでいます。これは数 GB をやや下回る理論上の上限で（通常は問題になりません）、一般的なドキュメントでは心配ありませんが、非常に大きなスキャン PDF を扱う場合は知っておいてください。

---

## クイックリファレンス

```4d
 // ピクチャにレンダリング
$path:=Get 4D folder:C485(Current resources folder:K5:16)+"doc.pdf"
DOCUMENT TO BLOB:C525($path;$PDF)
ARRAY PICTURE:C279($pages;0)
$error:=PDF Convert($PDF;$pages;1;0;"";"")

 // SVG テキストにレンダリング
ARRAY TEXT:C222($svgPages;0)
$error:=PDF Convert($PDF;$svgPages)

 // 300 DPI の PNG にレンダリング
ARRAY PICTURE:C279($pngPages;0)
$error:=PDF Convert($PDF;$pngPages;0;0;"";"";New object:C1471("format"; "png"; "dpi"; 300))

 // テキストを抽出
ARRAY TEXT:C222($textPages;0)
$error:=PDF Get text($PDF;$textPages;1;0;"";"PDF2TEXT_CB")

 // ページ数
$count:=PDF Get page count($PDF)
```
