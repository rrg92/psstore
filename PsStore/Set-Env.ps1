param($name,$Value,[switch]$Force = $false,$Scope = "Machine")


write-host "Getting variable $name"
$currentVariable = [Environment]::GetEnvironmentVariable($name,$Scope)

if($Force -and $currentVariable){
	throw "ALREADY_EXISTS"
}

write-host "Setting variable $name to $Value"
[Environment]::SetEnvironmentVariable($name, $Value, $Scope)


