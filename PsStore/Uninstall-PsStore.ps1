[CmdLetBinding()]
param($EnvName = "PSSTORE")


$ErrorActionPreference ="Stop"

#Save current location
push-location
#Change current location
set-location (Split-Path -Parent $MyInvocation.MyCommand.Definition )

try {
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
	

	## Remove PsStore from path...
	write-host "--> Checking PSSTORE ~$PSSTOREFolder~ on PATH..."
	if( .\Get-EnvPath.ps1 | Where {$_ -and (Script:PutFolderSlash($_)) -eq (Script:PutFolderSlash($PSSTOREFolder)) } )
	{		
		write-host "Removing PSSTORE From Path"
		.\Unset-EnvPath -Folder  $PSSTOREFolder
	} else {
		write-host "	Nothing to remove!"
	}
	
	$ModuelPaths = & .\Get-PsModulePath.ps1;
	
	$PathsForRemove = $ModuelPaths | where {$_ -like $PSSTOREFolder+"\*"}
	
	write-host "--> Removing paths from module path"
	if(!(.\Unset-PsModulePath.ps1 $PathsForRemove)){
		write-host "	Nothing to change..."
	}
	
	write-host "--> Removing Env $EnvName"
	.\Unset-Env -Name $EnvName
	
} finally {
	pop-location
}

