![version](https://img.shields.io/badge/version-17%2B-3E8B93)
![platform](https://img.shields.io/static/v1?label=platform&message=mac-intel%20|%20mac-arm%20|%20win-64&color=blue)
[![license](https://img.shields.io/github/license/miyako/4d-plugin-poppler)](LICENSE)
![downloads](https://img.shields.io/github/downloads/miyako/4d-plugin-poppler/total)

**English** | [日本語](README.ja.md)

### Dependencies and Licensing

* the source code of this plugin developed using the [4D Plug-in SDK](https://github.com/4d/4D-Plugin-SDK) is licensed under the MIT license
* see [Poppler](https://poppler.freedesktop.org) for the licensing of **Poppler** (shared library).
* the licensing of the binary product of this plugin is subject to the licensing of all its dependencies.
* on Windows, Poppler (GPL-2.0-or-later) and its dependencies — GLib, Cairo, pixman, FreeType, libiconv, gettext-libintl (LGPL/MPL), libpng, zlib, brotli, etc. — are **statically linked** into `Poppler.4DX`. The distributed binary is therefore a combined work under the GPL; statically linking the LGPL components also means recipients must be able to relink them (corresponding source is available via [`vcpkg.json`](vcpkg.json), which pins every dependency version).

#### Building on Windows

`Poppler.vcxproj` links the static libraries produced by vcpkg (`x64-windows-static-release`, static CRT):

```
vcpkg install --triplet x64-windows-static-release --host-triplet x64-windows-static-release --overlay-triplets=vcpkg-triplets --x-install-root=vcpkg_installed
msbuild Poppler.sln /p:Configuration=Release /p:Platform=x64
```

Pass `/p:PopplerLinkage=dynamic` to link the legacy import libraries in `lib/windows64` instead; the DLLs in `test/Plugins/Poppler.bundle/Contents/Windows64` (plus the VC++ runtime) must then ship next to `Poppler.4DX`.

The release workflow uses the project's v145 toolset, matching vcpkg's compiler on the Windows runner; do not override it with an older toolset when linking these static libraries. It bootstraps the manifest-pinned vcpkg with up to four attempts (10, 20, and 40 seconds between attempts) to tolerate transient download failures. A failed bootstrap or missing `vcpkg.exe` stops the job before dependency installation. The baseline, triplet, and binary-cache keys are unchanged.

# 4d-plugin-poppler

The Poppler plugin wraps the [Poppler](https://poppler.freedesktop.org/) PDF-rendering library (via Cairo for SVG/PNG output) to give 4D three commands: rendering PDF pages to `Picture` (SVG or PNG) or SVG-as-`Text`, extracting a PDF's plain text, and getting a PDF's page count. Source PDFs are passed in as a `Blob` (e.g. from `DOCUMENT TO BLOB`), never as a file path — the plugin never touches the filesystem itself.

| Command | Returns | Purpose |
|---|---|---|
| [`PDF Convert`](#pdf-convert) | `Longint` | Renders a PDF's pages to an array of `Picture` (SVG or PNG, at any resolution) or an array of `Text` (SVG markup), page by page, with an optional per-page callback and an options object |
| [`PDF Get page count`](#pdf-get-page-count) | `Longint` | Returns the number of pages in a PDF |
| [`PDF Get text`](#pdf-get-text) | `Longint` | Extracts each page's plain text into an array of `Text`, with an optional per-page callback |

**Platforms:** Windows and macOS.

---

## Requirements & platform notes

- All three commands are declared **thread-safe** in the plugin's manifest.
- The source PDF is always a `Blob` (parameter 1) — build it with `DOCUMENT TO BLOB` or by reading raw bytes into a blob variable; the plugin has no path/file parameter.
- **Page numbers are 1-based** in every parameter and callback — page 1 is the first page, matching the array indices `PDF Convert`/`PDF Get text` write into.
- **Start/end page and password are effectively optional.** 4D lets you omit trailing parameters; when omitted (or passed as `0`/`""`), the plugin substitutes sensible defaults (see each command's Description). The plugin's own test methods rely on this — [`PDF2SVG_TEST_EASY.4dm`](#example) calls `PDF Convert` with only 2 of its 7 declared parameters.
- **A trailing `Text` parameter (the last one in `PDF Get text`'s signature, and the last one in `PDF Get page count`'s) is read into an internal variable but never used anywhere in the current source.** Passing it has no observed effect. Every provided sample method omits it. Treat it as reserved for now, not documented behavior.
- **Invalid or wrong-password-protected PDF data does not raise a 4D error** — the commands return an error code (see each command's table) and leave the output array/variable at whatever it was (typically empty), so always check the return value.
- **A callback method that returns `True` aborts the remaining pages early** and the command's return value becomes the "aborted by user" error code — this is the only way to stop a `PDF Convert`/`PDF Get text` call partway through; there's no cancel/timeout parameter.

---

## PDF Convert

### Syntax

```4d
$error:=PDF Convert($pdf; $pages; $startPage; $endPage; $password; $callback; $options) -> Longint
```

| Parameter | Type | Description |
|---|---|---|
| `pdf` | Blob | The PDF file's raw bytes. |
| `pages` | Array Picture, Array Text | The output array. Pass an already-declared `ARRAY PICTURE` or `ARRAY TEXT`, or an undeclared variable (the plugin declares it as `ARRAY PICTURE` for you). See Description for what happens with any other type. |
| `startPage` | Longint | 1-based first page to render. Omit or pass `0`/negative for "start at page 1." |
| `endPage` | Longint | 1-based last page to render. Omit or pass `0`, a value ≤ `startPage`, or a value past the document, for "render through the last page." |
| `password` | Text | PDF owner/user password. Omit or pass `""` for an unencrypted document. |
| `callback` | Text | Name of a project method invoked after each page is rendered (see Description). Omit or pass `""` to disable. |
| `options` | Object | Output format, resolution and rendering options — see [Options](#options). Omit or pass `Null`/`{}` for the defaults (SVG at 72 DPI, as in earlier versions). |
| Result | Longint | `0` on success. `-1` if the PDF data is invalid or the password is wrong. `-2` if `pages` isn't `Array Picture`/`Array Text` (or any other unsupported type), or is `Array Text` with `format` `"png"`. `-3` if a callback returned `True` and aborted the run. `-4` if `options` contains an invalid value (unknown `format`, non-positive `dpi`, negative `width`/`height`); the array is left untouched. |

### Description

`pages`'s declared type at the time you call `PDF Convert` decides the output format:
- **Undeclared/`Null`** variable → the plugin declares it as `Array Picture` for you (equivalent to `ARRAY PICTURE`).
- **Already `Array Picture`** → each element becomes a `Picture` whose bytes are an **SVG** rendering of that page by default — the same SVG markup the `Array Text` variant returns. Set `format` to `"png"` in `options` to get a **PNG** bitmap instead, rendered directly by Poppler at the requested resolution.
- **Already `Array Text`** → (SVG only; `format` `"png"` returns `-2`) each element becomes the page rendered as **SVG markup** (a full `<svg>...</svg>` document per page), not plain text — despite the array being of type `Text`, the content is SVG source. This is how the plugin returns per-page SVGs; see [`PDF2SVG_TEST_WITH_CB.4dm`](#example) for how it's written to `.svg` files afterward.
- **Any other type** (including `Array Blob`, unless the build you have was compiled with Blob-array support) → the command does nothing and returns `-2` immediately, without resizing or touching your array.

The array is always resized to the PDF's total page count, indexed 1-based by absolute page number (element `pageInd` holds page `pageInd`, regardless of `startPage`) — pages outside your `startPage`/`endPage` range are left at whatever default the array element type has (an empty `Picture`, an empty string), not removed from the array.

### Options

| Property | Type | Default | Description |
|---|---|---|---|
| `format` | Text | `"svg"` | `"svg"` (vector) or `"png"` (bitmap). Case-insensitive. |
| `dpi` | Real | `72` | Output resolution. At 72 a page is sized in PDF points (A4 = 595 × 842); at 300 an A4 page is 2479 × 3508 px (PNG) or an SVG of that size. |
| `width` | Real | — | Target width in pixels (SVG: user units). Overrides `dpi`; the page's aspect ratio is kept. |
| `height` | Real | — | Target height in pixels. Overrides `dpi`. When both `width` and `height` are given, the page is fitted **inside** that box (typical for thumbnails). |
| `transparent` | Boolean | `False` | PNG only. `False` paints a white background (as a PDF viewer does); `True` keeps the page background transparent. |
| `antialias` | Boolean | `True` | `False` disables anti-aliasing of shapes and text — useful for crisp 1-bit-style output such as barcodes or fax/OCR pipelines. |
| `printing` | Boolean | `True` | `True` renders as for printing (Poppler's print path, which hides annotations and form fields flagged as not printable). `False` renders as a PDF viewer shows the page on screen. |

**Output size.** By default each page is sized to the PDF page itself, in PDF points (1/72 inch) — e.g. A4 is 595 × 842 and US Letter is 612 × 792 — so 4D displays it at the equivalent of 72 DPI. Use `dpi`, `width` or `height` to change that. Pages are rendered with their `/Rotate` applied.

PNG specifics:
- The PNG carries its resolution (a `pHYs` chunk), so a 300 DPI page is tagged as 300 DPI. Applications that honour that metadata (4D included, for high-resolution display and printing) may display it at its physical size — i.e. the same on-screen size as the 72 DPI version, but sharper. `PICTURE PROPERTIES` / the pixel count reflects the real resolution.
- Each side is capped at 32767 pixels (Cairo's limit); larger requests are scaled down proportionally. Mind memory: a bitmap needs 4 bytes per pixel while rendering (an A4 page at 600 DPI is ~140 MB).
- Embedded images are resampled to the output resolution; vector content and text are rasterized sharply at any resolution.

If `callback` names a valid project method, it's called once per rendered page, **after** that page's array element is set, with the signature:

```4d
#DECLARE($pos : Integer; $total : Integer; $pageNumber : Integer; $page : Picture)->$stop : Boolean
```

(`$page` is typed `Text` instead of `Picture` when `pages` is `Array Text` — see [`PDF2TEXT_CB.4dm`](#example) for the text-flavored signature, used identically here.) `$pos` is a 1-based running count of pages processed so far in this call (not the absolute page number), `$total` is the total number of pages the call will process (`endPage - startPage + 1`), `$pageNumber` is the 1-based absolute page number, and `$page` is that page's rendered content — a fresh copy, independent of the array element. Return `True` from the callback to stop processing further pages.

Password handling: an empty/omitted `password` is passed to Poppler as `NULL`, not `""` — matching how Poppler distinguishes "no password supplied" from "empty-string password."

### Example

From the plugin's own test method, no callback (`PDF2SVG_TEST_EASY.4dm`):

```4d
$path:=Get 4D folder:C485(Current resources folder:K5:16)+"doc.pdf"

DOCUMENT TO BLOB:C525($path;$PDF)

ARRAY PICTURE:C279($pages;0)

$error:=PDF Convert ($PDF;$pages)

PICTURE PROPERTIES:C457($pages{1};$w;$h)

WRITE PICTURE FILE:C680(System folder:C487(Desktop:K41:16)+"doc-1.svg";$pages{1};".svg")
```

With a callback, explicit page range and password (`PDF2SVG_TEST_WITH_CB.4dm` calling [`PDF2SVG_CB`](#pdf2svg_cb) below):

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

Requesting `Array Text` instead, to get per-page SVG markup rather than pictures:

```4d
ARRAY TEXT:C222($svgPages;0)
$error:=PDF Convert($PDF;$svgPages)
 // $svgPages{1} now holds page 1's SVG markup as text — write it out
 // with whichever of 4D's own text/document-writing commands fits your
 // version (e.g. TEXT TO DOCUMENT); exact syntax not verified here.
```

High-resolution PNG (300 DPI), with a white background:

```4d
ARRAY PICTURE:C279($pages; 0)
$error:=PDF Convert($PDF; $pages; 0; 0; ""; ""; New object:C1471("format"; "png"; "dpi"; 300))
WRITE PICTURE FILE:C680(System folder:C487(Desktop:K41:16)+"doc-1.png"; $pages{1}; ".png")
```

Thumbnails that fit inside 200 × 200 pixels, transparent background, rendered as on screen:

```4d
ARRAY PICTURE:C279($thumbnails; 0)
$error:=PDF Convert($PDF; $thumbnails; 0; 0; ""; ""; New object:C1471("format"; "png"; "width"; 200; "height"; 200; "transparent"; True:C214; "printing"; False:C215))
```

SVG enlarged to 2× (144 DPI):

```4d
ARRAY PICTURE:C279($pages; 0)
$error:=PDF Convert($PDF; $pages; 0; 0; ""; ""; New object:C1471("dpi"; 144))
```

The plugin transfers ownership of each SVG string to the output array. Earlier
builds freed that string immediately after assignment, leaving a dangling array
element that could crash 4D on Windows when read or cleared. The callback receives
a separately allocated string; disposing that copy does not invalidate the array.

To exercise this regression in the 4D test project on Windows or macOS, run
`PDF2SVG_TEXT_TEST`. It uses `Resources/doc.pdf`, checks SVG output with and
without a callback, churns text allocations before reading the array, and repeats
conversion with both array reuse and explicit clearing.

Bailing out early from a callback once a target page is found:

```4d
 // in the callback method
#DECLARE($pos : Integer; $total : Integer; $pageNumber : Integer; $page : Picture)->$stop : Boolean
$stop:=($pageNumber=$targetPage)
```

---

## PDF Get page count

### Syntax

```4d
$error:=PDF Get page count($pdf; $password) -> Longint
```

| Parameter | Type | Description |
|---|---|---|
| `pdf` | Blob | The PDF file's raw bytes. |
| `password` | Text | PDF owner/user password. Omit or pass `""` for an unencrypted document. |
| *(unused)* | Text | Declared in the command's syntax but not read by the current plugin build at all — can be omitted. |
| Result | Longint | The page count on success. `-1` if the PDF data is invalid or the password is wrong. |

### Description

The simplest of the three commands: opens the PDF just to read its page count, then releases it immediately. No array or callback involved.

### Example

No test method for this specific command was included with the plugin, so this example is built from the same blob-loading pattern verified in the other test files above:

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

With a password:

```4d
$count:=PDF Get page count($PDF;"correct horse battery staple")
```

---

## PDF Get text

### Syntax

```4d
$error:=PDF Get text($pdf; $pages; $startPage; $endPage; $password; $callback) -> Longint
```

| Parameter | Type | Description |
|---|---|---|
| `pdf` | Blob | The PDF file's raw bytes. |
| `pages` | Array Text | The output array. **Must already be `Array Text`** — unlike `PDF Convert`, this command does not inspect or auto-declare the array's type. |
| `startPage` | Longint | 1-based first page to extract. Omit or pass `0`/negative for "start at page 1." |
| `endPage` | Longint | 1-based last page to extract. Omit or pass `0`, a value ≤ `startPage`, or a value past the document, for "extract through the last page." |
| `password` | Text | PDF owner/user password. Omit or pass `""` for an unencrypted document. |
| `callback` | Text | Name of a project method invoked after each page's text is extracted (see Description). Omit or pass `""` to disable. |
| *(unused)* | Text | Accepted but has no effect in the current plugin build — can be omitted. |
| Result | Longint | `0` on success. `-1` if the PDF data is invalid or the password is wrong. `-3` if a callback returned `True` and aborted the run. |

### Description

Unlike `PDF Convert`'s output array, `pages` here is a single running string, not one array element per page: every extracted page's text is **appended** to the same, single array element (`pages{1}`) rather than written to `pages{pageNumber}`. If you need per-page text separated out, split on your own delimiter or use the callback's `$page` parameter (below), which does give you one page's text at a time.

If `callback` names a valid project method, it's called once per page, with the signature:

```4d
#DECLARE($pos : Integer; $total : Integer; $pageNumber : Integer; $page : Text)->$stop : Boolean
```

`$pos`, `$total`, and `$pageNumber` behave exactly as in [`PDF Convert`](#pdf-convert); `$page` is that single page's extracted plain text. Return `True` to stop processing further pages.

### Example

From the plugin's own test method (`PDF2TEXT_TEST_WITH_CB.4dm`, calling [`PDF2TEXT_CB`](#pdf2text_cb) below):

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

Extracting just the first 3 pages, no callback:

```4d
ARRAY TEXT:C222($pages;0)
$error:=PDF Get text($PDF;$pages;1;3)
If($error=0)
    ALERT:C41($pages{1})
End if
```

---

## Reference helper methods

These are the plugin's own test project methods — the callback signatures `PDF Convert` and `PDF Get text` actually invoke. They aren't plugin commands themselves, but you need a method matching one of these shapes to use the `callback` parameter.

### PDF2SVG_CB

**`PDF2SVG_CB ($pos : Integer; $total : Integer; $pageNumber : Integer; $page : Picture) -> $stop : Boolean`**

| Parameter | Type | Description |
|---|---|---|
| `pos` | Integer | 1-based count of pages processed so far in the current `PDF Convert` call. |
| `total` | Integer | Total number of pages this call will process. |
| `pageNumber` | Integer | 1-based absolute page number just rendered. |
| `page` | Picture | The rendered picture for this page. |
| Result | Boolean | Return `True` to abort remaining pages. |

From the plugin's own source (`PDF2SVG_CB.4dm`):

```4d
//%attributes = {"invisible":true}
#DECLARE($pos : Integer; $total : Integer; $pageNumber : Integer; $page : Picture)->$stop : Boolean
```

The shipped stub does nothing (always continues); a real implementation might report progress or save each picture as it arrives:

```4d
#DECLARE($pos : Integer; $total : Integer; $pageNumber : Integer; $page : Picture)->$stop : Boolean
 // pick any folder command for your 4D version; WRITE PICTURE FILE's
 // tag (:C680) is verified from the plugin's own test file above
WRITE PICTURE FILE:C680($destinationFolder+"page"+String:C10($pageNumber)+".png";$page;".png")
$stop:=False
```

### PDF2TEXT_CB

**`PDF2TEXT_CB ($pos : Integer; $total : Integer; $pageNumber : Integer; $page : Text) -> $stop : Boolean`**

| Parameter | Type | Description |
|---|---|---|
| `pos` | Integer | 1-based count of pages processed so far in the current `PDF Get text` call. |
| `total` | Integer | Total number of pages this call will process. |
| `pageNumber` | Integer | 1-based absolute page number just extracted. |
| `page` | Text | The extracted plain text for this page. |
| Result | Boolean | Return `True` to abort remaining pages. |

From the plugin's own source (`PDF2TEXT_CB.4dm`):

```4d
//%attributes = {"invisible":true}
#DECLARE($pos : Integer; $total : Integer; $pageNumber : Integer; $page : Text)->$stop : Boolean
```

---

## Error handling & troubleshooting

- **A bad password or corrupt/non-PDF blob is not a 4D error — check the return value.** All three commands return `-1` (`PDF2SVG_ERROR_InvalidSourceData`) rather than throwing; a `Picture`/`Text` array left untouched or an empty page count both look like "nothing happened" if you don't check `$error`.
- **`PDF Convert` returns `-2` silently if `pages` is the wrong type**, without resizing or clearing the array you passed — if you declared it as anything other than `Array Picture` or `Array Text` beforehand (e.g. left over from unrelated code reusing the variable), you'll get `-2` back with your original array untouched.
- **`PDF Get text` requires `pages` to already be `Array Text`** — there's no auto-declare fallback here the way there is in `PDF Convert`. Declare it with `ARRAY TEXT` before calling.
- **A callback returning `True` produces `-3`, not `0`** — if you're checking only for `$error=0` to mean "all pages processed," a user-initiated stop will look like a different kind of failure; check for `-3` specifically if you want to distinguish "stopped early" from "PDF was invalid."
- **`PDF Get text` appends every page into a single array element**, not one element per page — don't expect `pages{pageNumber}` to hold that page's isolated text; use the callback's `$page` parameter instead if you need pages kept separate.
- **`PDF Convert` returns `-4` for invalid `options`** (unknown `format`, non-positive `dpi`, negative `width`/`height`) without touching the array. Unknown properties are ignored.
- **The trailing, always-last `Text` parameter on `PDF Get text` and `PDF Get page count` currently has no effect** — every shipped sample omits it; don't rely on passing it for anything.
- **Very large PDFs**: page/text/picture data size is read into a plain `int` internally in the current plugin build, which is a theoretical (not commonly hit) limit somewhat below the multi-gigabyte range — not a concern for ordinary documents, but worth knowing if you're feeding in unusually large scanned PDFs.

---

## Quick reference

```4d
 // Render to pictures
$path:=Get 4D folder:C485(Current resources folder:K5:16)+"doc.pdf"
DOCUMENT TO BLOB:C525($path;$PDF)
ARRAY PICTURE:C279($pages;0)
$error:=PDF Convert($PDF;$pages;1;0;"";"")

 // Render to SVG text
ARRAY TEXT:C222($svgPages;0)
$error:=PDF Convert($PDF;$svgPages)

 // Render to 300 DPI PNG
ARRAY PICTURE:C279($pngPages;0)
$error:=PDF Convert($PDF;$pngPages;0;0;"";"";New object:C1471("format"; "png"; "dpi"; 300))

 // Extract text
ARRAY TEXT:C222($textPages;0)
$error:=PDF Get text($PDF;$textPages;1;0;"";"PDF2TEXT_CB")

 // Page count
$count:=PDF Get page count($PDF)
```
