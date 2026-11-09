//%attributes = {"invisible":true}
#DECLARE($pos : Integer; $total : Integer; $pageNumber : Integer; $page : Text)->$stop : Boolean
ASSERT($pos>0)
ASSERT($pos<=$total)
ASSERT($pageNumber=$pos)
ASSERT(Position("<svg"; $page)>0)
ASSERT(Position("</svg>"; $page)>0)
$stop:=False
