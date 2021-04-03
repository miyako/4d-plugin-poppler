//%attributes = {"invisible":true}
C_LONGINT:C283($1;$pos)
C_LONGINT:C283($2;$total)
C_LONGINT:C283($3;$pageNumber)
C_PICTURE:C286($4;$page)
C_BOOLEAN:C305($0;$stop)

$pos:=$1
$total:=$2
$pageNumber:=$3
$page:=$4

<>PI->:=$page
APPEND TO ARRAY:C911(<>PP->;$page)
APPEND TO ARRAY:C911(<>PN->;String:C10($pageNumber))

<>PN->:=$pos

Progress SET PROGRESS (<>P;$pos/$total)
$0:=Progress Stopped (<>P)

POST OUTSIDE CALL:C329(-1)