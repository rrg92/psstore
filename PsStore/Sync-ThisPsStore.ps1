param($ControlFile,[switch]$Debug = $false,$LogFile = $null,$RemoteFolder = $null)


$LogDestinations = @($LogFile)

if($Debug){
	$LogDestinations += "SCREEN"
}

if(!$ControlFile){
	throw "INVALID_CONTROL_FILE"
	return;
}



#Calling PsStoreSync core engine...
Invoke-PsStoreSync -RemoteFolder $RemoteFolder -LogTo $LogDestinations -ControlFile $ControlFile
