$thisScriptFile = Split-Path -leaf $MyInvocation.MyCommand.Definition;


get-childitem *.ps1 -Exclude "$thisScriptFile" | % {
 
 "Loading script $($_.Name) "
 try {
 	 . (".\"+$_.name);
 	"	SUCESS!"
 } catch {
	throw;	
 }


}#FromPSStore
#FromPSStore
#FromPSStore
#FromPSStore
#FromPSStore
