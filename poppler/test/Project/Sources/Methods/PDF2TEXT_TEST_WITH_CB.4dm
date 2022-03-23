//%attributes = {"invisible":true}
$path:=Get 4D folder:C485(Current resources folder:K5:16)+"test1.pdf"
DOCUMENT TO BLOB:C525($path; $PDF)

ARRAY TEXT:C222($pages; 0)

$startPage:=0
$endPage:=0
$password:=""
$callback:="PDF2TEXT_CB"

$error:=PDF Get text($PDF; $pages; $startPage; $endPage; $password; $callback)