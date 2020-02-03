param($Folder = ".")

if($Folder -eq $null -or $Folder -eq ".")
{
    write-host "Getting current path"
    $Folder = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition
}


$NovoPath = $Folder;

write-host "Getting module path"
$CurrentPath = [Environment]::GetEnvironmentVariable("PsModulePath","Machine")

$NewPath = "";

$SomeFound = $false;
$CurrentPath  -Split ";" | %{
		if($_ -like $Folder){
			write-host "Folder ~$Folder~ found on path. It will be removed!"
			$SomeFound  = $false;
		} else {
			$NewPath += $_  + ";";
		}
}

if($SomeFound){
	write-host "Setting current module path to:"
	$NewPath -split ";" | %{
		write-host "	$_"
	}
	[Environment]::SetEnvironmentVariable("PsModulePath", "$NewPath" , "Machine")

	return $true;
} else {
	return $false;
}