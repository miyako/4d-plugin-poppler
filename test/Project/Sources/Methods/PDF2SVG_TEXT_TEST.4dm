//%attributes = {"invisible":true}
var $path; $callback; $savedPage : Text
var $PDF : Blob
var $count; $error; $pass; $page : Integer

$path:=Get 4D folder:C485(Current resources folder:K5:16)+"doc.pdf"
DOCUMENT TO BLOB:C525($path; $PDF)
$count:=PDF Get page count($PDF; "")
ASSERT($count>0)

ARRAY TEXT:C222($pages; 0)
ARRAY TEXT:C222($heapChurn; 0)

For ($pass; 1; 10)
	$callback:=""
	If (Mod($pass; 2)=0)
		$callback:="PDF2SVG_TEXT_CB"
	End if
	$error:=PDF Convert($PDF; $pages; 1; 0; ""; $callback)
	ASSERT($error=0)
	ASSERT(Size of array($pages)=$count)

	// Reuse string allocations before reading the returned array.
	ARRAY TEXT:C222($heapChurn; 100)
	For ($page; 1; 100)
		$heapChurn{$page}:=Repeat string("allocation churn"; 1000)
	End for

	For ($page; 1; $count)
		ASSERT(Position("<svg"; $pages{$page})>0)
		ASSERT(Position("</svg>"; $pages{$page})>0)
	End for

	$savedPage:=$pages{1}
	ARRAY TEXT:C222($heapChurn; 0)
	// Alternate between reusing the output array and explicitly clearing it.
	If (Mod($pass; 2)=0)
		ARRAY TEXT:C222($pages; 0)
	End if
	ASSERT(Position("</svg>"; $savedPage)>0)
End for
