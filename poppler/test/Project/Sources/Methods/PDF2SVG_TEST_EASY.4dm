//%attributes = {"invisible":true}
$path:=Get 4D folder:C485(Current resources folder:K5:16)+"doc.pdf"

DOCUMENT TO BLOB:C525($path;$PDF)

ARRAY PICTURE:C279($pages;0)

$error:=PDF Convert ($PDF;$pages)

PICTURE PROPERTIES:C457($pages{1};$w;$h)

WRITE PICTURE FILE:C680(System folder:C487(Desktop:K41:16)+"doc-1.svg";$pages{1};".svg")