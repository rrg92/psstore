$ErrorActionPreference ="Stop"


$pushed = $false;
try {
	#Save current location
	push-location
	$pushed = $true;
	#Change current location
	set-location (Split-Path -Parent $MyInvocation.MyCommand.Definition )

	gci "*.ps1" | %{ $_.BaseName }
} finally {
	if($pushed){
		pop-location
	}
}#FromPSStore
#FromPSStore
#FromPSStore
#FromPSStore
#FromPSStore
