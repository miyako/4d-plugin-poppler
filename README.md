![version](https://img.shields.io/badge/version-16%2B-8331AE)
![platform](https://img.shields.io/static/v1?label=platform&message=mac-intel%20|%20mac-arm%20|%20win-64&color=blue)
[![license](https://img.shields.io/github/license/miyako/4d-plugin-poppler)](LICENSE)
![downloads](https://img.shields.io/github/downloads/miyako/4d-plugin-poppler/total)
![language-top](https://img.shields.io/github/languages/top/miyako/4d-plugin-poppler)
![code-size](https://img.shields.io/github/languages/code-size/miyako/4d-plugin-poppler)

**Note**: for v17 and earlier, move `manifest.json` to `Contents`

# 4d-plugin-poppler
Extract text from PDF, convert PDF to SVG.

### Syntax


```
error:=PDF Convert (pdf;svg;from;to;password;method)
```

Parameter|Type|Description
------------|------|----
pdf|BLOB|The PDF document BLOB
svg|ARRAY PICTURE (or ARRAY TEXT or ARRAY BLOB)|Array to receive the pages (must be defined); See remarks below
from|LONGINT|Starting page (1 based) [optional]
to|LONGINT|Ending page (1 based) [optional]
password|TEXT|Password [optional]
method|TEXT|Callback method [optional]
error|LONGINT|Error code

```
count:=PDF Get page count (pdf;password)
```

Parameter|Type|Description
------------|------|----
pdf|BLOB|The PDF document BLOB
password|TEXT|Password [optional]
count|LONGINT|Page count

### Examples

```4d
$path:=Get 4D folder(Current resources folder)+"sample.pdf"
DOCUMENT TO BLOB($path;$PDF)

ARRAY PICTURE($pages;0)
$startPage:=0
$endPage:=0
$password:=""
$callback:="PDF2SVG_CB_PICTURE"

<>p:=Progress New 
Progress SET PROGRESS (<>P;0)
Progress SET BUTTON ENABLED (<>P;True)

$error:=PDF Convert ($PDF;$pages;$startPage;$endPage;$password;$callback)

Progress QUIT (<>P)
```

### Callback

The method is executed in the same process as the calling method.

Parameters:

```4d
C_LONGINT($1;$pos)//1-based
C_LONGINT($2;$total)
C_LONGINT($3;$pageNumber)//1-based
C_PICTURE($4;$page)
C_BOOLEAN($0;$stop)
```

To display a progress bar:

```4d
Progress SET PROGRESS (<>P;$pos/$total)
```

To abort:

```4d
$0:=Progress Stopped (<>P)
```

### Error codes

```c
#define PDF2SVG_ERROR_InvalidSourceData (-1)
#define PDF2SVG_ERROR_InvalidReturnType (-2)
#define PDF2SVG_ERROR_AbortedByUser (-3)
```

### Alternate syntax

Alternatively, you may pass ```ARRAY TEXT``` or ```ARRAY BLOB``` in $2. However, $4 in the callback function will not be used. The current page data will only be passed to the callback method when ```ARRAY PICTURE``` is used. It's main purpose is to  display a preview image. Note that the image is a ref-counted duplicate of the final array element. 

### Build notes

iconv by cmake may be missing the symbol `libiconv_set_relocation_prefix`

add a stub function

```c
extern LIBICONV_DLL_EXPORTED void libiconv_set_relocation_prefix (const char *orig_prefix,
                                                                  const char *curr_prefix){do {} while(0);}
```

zlib by cmake may be missing the symbol `_inflateValidate`

normal `make` instead

---

![](https://github.com/miyako/4d-plugin-PDF2SVG/blob/master/images/screenshot.png)

![](https://github.com/miyako/4d-plugin-PDF2SVG/blob/master/images/screenshot-w.png)
