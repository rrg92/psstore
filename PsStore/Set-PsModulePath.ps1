param($Folder = ".")

if($Folder -eq $null -or $Folder -eq ".")
{
    write-host "Getting current path"
    $Folder = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition
}


$NovoPath = $Folder;

write-host "Getting current module path"
$CurrentPath = [Environment]::GetEnvironmentVariable("PsModulePath","Machine")

write-host "Setting current module path to $Folder"
[Environment]::SetEnvironmentVariable("PSModulePath", "$CurrentPath;$NovoPath", "Machine")

#FromPSStore
#FromPSStore
#FromPSStore
#FromPSStore
#FromPSStore
