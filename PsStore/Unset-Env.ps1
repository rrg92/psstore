param($name,[switch]$Force = $true,$Scope = "Machine")


write-host "Getting variable $name for delete..."
$currentVariable = [Environment]::GetEnvironmentVariable($name,$Scope)

if($currentVariable){
	write-host "	Deleting variable $name to $Value"
	$Value = "";
	[Environment]::SetEnvironmentVariable($name, $Value, $Scope)

} else {
	write-host "	Variable $name. Nothing to delete"
}



