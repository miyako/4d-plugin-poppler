//%attributes = {"invisible":true}
$path:=Get 4D folder:C485(Current resources folder:K5:16)+"test1.pdf"
DOCUMENT TO BLOB:C525($path;$PDF)

ARRAY TEXT:C222($pages;0)

$startPage:=0
$endPage:=0
$password:=""
$callback:="PDF2TEXT_CB"

<>p:=Progress New 
Progress SET PROGRESS (<>P;0)
Progress SET BUTTON ENABLED (<>P;True:C214)

<>W:=Open window:C153(0;100;600;800;Movable dialog box:K34:7)

$error:=PDF Get text ($PDF;$pages;$startPage;$endPage;$password;$callback)

Progress QUIT (<>P)

CLOSE WINDOW:C154(<>W)