//%attributes = {}
$path:=Get 4D folder:C485(Current resources folder:K5:16)+"sample.pdf"

DOCUMENT TO BLOB:C525($path;$PDF)

C_PICTURE:C286($page)
ARRAY PICTURE:C279($pages;0)
ARRAY TEXT:C222($names;0)

$startPage:=0
$endPage:=0
$password:=""
$callback:="PDF2SVG_CB"

<>PI:=->$page
<>PP:=->$pages
<>PN:=->$names

<>p:=Progress New 
Progress SET PROGRESS (<>P;0)
Progress SET BUTTON ENABLED (<>P;True:C214)

$error:=PDF Convert ($PDF;$pages;$startPage;$endPage;$password;$callback)

Progress QUIT (<>P)