#Sets some environments variables
param (
	  $EnvName
	  ,$EnvVarsPrefix = "MYENV"
	  ,[switch]$List
	  ,[switch]$Edit
	  ,$DefaultEditor = $Env:MYENV_DEFAULT_EDITOR
)
$ErrorActionPreference="Stop";

if(!$DefaultEditor){
	$DefaultEditor  = 'notepad'
}

$EnvFile	= (Get-Item "Env:$($EnvVarsPrefix)_FILE" -EA "SilentlyContinue");

if(!$EnvFile){
	throw "NO_ENV_FILE"
}

$EnvFile = $EnvFile.Value;

if($Edit){
	 write-host "Waiting editor $DefaultEditor to edit $Envfile..."
	 Start-Process $DefaultEditor -ArgumentList $EnvFile -Wait 
}

if(![IO.File]::exists($EnvFile)){
	throw "NO_FILE:$EnvFile"
}


$EnvData = . $EnvFile;

if($List){
	$EnvData;
	return;
}

if(!$EnvName){
	throw "EMPTY_ENV_NAME";
}


if(!$EnvData.contains($EnvName)){
	throw "NO_ENV:$EnvName"
}

$NameSlot = $EnvData[$EnvName];

if(!$NameSlot -is [hashtable]){
	throw "INVALID_SLOT: $EnvName $NameSlot"
}


$NameSlot.GetEnumerator() | %{
	$VarName = $_.key;
	$VarValue = $_.Value;
	
	write-host "Setting var $VarName to $VarValue";
	Set-Item -Path "Env:$VarName" -Value $VarValue;
}



