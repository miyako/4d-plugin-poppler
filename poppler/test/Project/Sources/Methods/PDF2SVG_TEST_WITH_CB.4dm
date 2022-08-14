//%attributes = {"invisible":true}
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