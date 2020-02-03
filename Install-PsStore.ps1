[CmdLetBinding()]
param($CustomPSModules = $null, [Switch]$NoIncludeThis = $false,[Switch]$RegisterEnvVariable = $false, $EnvName = "PSSTORE")


$ErrorActionPreference ="Stop"

#Save current location
push-location
#Change current location
set-location (Split-Path -Parent $MyInvocation.MyCommand.Definition )

try {
	write-host "Loading scripts..."
	.\LoadScripts "PsStore";

	Function Script:Right($str,$qtd = 1){
		return $str.substring($str.length - $qtd, $qtd)
	}

	Function Script:PutFolderSlash($folder, [switch]$Slash = $false ){
		$slashToUse = '\'
		$slashToReplace = '/'
		if($Slash){
			$slashToUse = '/'
			$slashToReplace = '\'
		}
		
        write-verbose "Current folder: $folder"
		$folder = $folder.replace($slashToReplace,$slashToUse)

		if( (Script:Right($folder)) -ne $slashToUse ){
			$folder += $slashToUse
		}

		return $folder
	}

	$CurrentFolder = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition
	$NewModulePath = "$CurrentFolder\MODULES\"
	$PSSTOREFolder = $CurrentFolder
	

	##try register PSSTORE on PATH
	if( Get-EnvPath.ps1 | Where {$_ -and (Script:PutFolderSlash($_)) -eq (Script:PutFolderSlash($PSSTOREFolder)) } )
	{		write-host "$PSSTOREFolder already on PATH"
	} else {		
			write-host "Adding $PSSTOREFolder to PATH"
			Set-EnvPath.ps1 $PSSTOREFolder
	}
	
    $allModules = @()
    if($CustomPSModules){
	    $allModules += $CustomPSModules
    }
	
	if(!$NoIncludeThis){
		$allModules += $NewModulePath;
	}
	
	if($allModules)
	{
        write-verbose "All Modules: $allModules"
       
	    $allModules | %{
			$currentModulePath = $_
        

			write-verbose "Attempting register module path: $currentModulePath"

			if( Get-PsModulePath.ps1 | Where { $_ -and (Script:PutFolderSlash($_)) -eq (Script:PutFolderSlash($currentModulePath)) } )
			{		write-host "	$currentModulePath already on PsModulePath"
			} else {		
					write-host "	Adding $currentModulePath to PsModulePath"
					Set-PsModulePath.ps1 $currentModulePath
			}
		}
	}
	
	if($RegisterEnvVariable){
		Set-Env -Name $EnvName -Value $PSSTOREFolder
	}
	
} finally {
	pop-location
11
