param($Folder = ".")

if($Folder -eq $null -or $Folder -eq ".")
{
    write-host "Getting current path"
    $Folder = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition
}


$NovoPath = $Folder;

write-host "Getting path"
$CurrentPath = [Environment]::GetEnvironmentVariable("PATH","Machine")

$NewPath = "";

$CurrentPath  -Split ";" | %{
		if($_ -like $Folder){
			write-host "Folder ~$Folder~ found on path. It will be removed!"
		} else {
			$NewPath += $_  + ";";
		}
}


write-host "Setting current path to:"
$NewPath -split ";" | %{
	write-host "	$_"
}
[Environment]::SetEnvironmentVariable("PATH", "$NewPath" , "Machine")

