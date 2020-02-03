param($Folder = ".")

if($Folder -eq $null -or $Folder -eq ".")
{
    write-host "Getting current path"
    $Folder = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition
}


$NovoPath = $Folder;

write-host "Getting path"
$CurrentPath = [Environment]::GetEnvironmentVariable("PATH","Machine")

write-host "Setting current path to $Folder"
[Environment]::SetEnvironmentVariable("PATH", "$CurrentPath;$NovoPath", "Machine")

