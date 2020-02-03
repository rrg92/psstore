param($O,[switch]$b = $false,$PsStore = ".")

#Save current location
push-location
#Change current location
set-location (Split-Path -Parent $MyInvocation.MyCommand.Definition )

$d = $PsStore

try {
	Copy-Item $o $d -verbose
} finally {
	pop-location
}

if($b){
	read-host
}

#FromPSStore
#FromPSStore
#FromPSStore
#FromPSStore
#FromPSStore
