//%attributes = {"invisible":true}
C_LONGINT:C283($1;$pos)  //1-based
C_LONGINT:C283($2;$total)
C_LONGINT:C283($3;$pageNumber)  //1-based
C_TEXT:C284($4;$page)
C_BOOLEAN:C305($0;$stop)

$pos:=$1
$total:=$2
$pageNumber:=$3
$page:=$4

Progress SET PROGRESS (<>P;$pos/$total)

ERASE WINDOW:C160(<>W)

MESSAGE:C88($page)

DELAY PROCESS:C323(Current process:C322;60)

$0:=Progress Stopped (<>P)