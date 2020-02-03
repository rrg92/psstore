<#
	Creaed by Rodrigo Ribeiro Gomes
	
	Load scripts all a specific subfolder of this!
#>
$ErrorActionPreference = "Stop";

$NewPath = $Env:PATH -Split ';'
$NewModulePath = $Env:PsModulePath -Split ';'

$Args | %{
	
	$Path = $_;
	$Uri = [uri]$Path
	
	
	if(!$Uri.IsAbsoluteUri){
		$Path = "$PsScriptRoot\$Uri"
	}
	
	
	
	write-host "Checking $Path";
	
	if(Test-Path $Path){
		#Check if exists!
		if( $NewPath -NotContains $Path){
			$NewPath += $Path;
		}
		
		$ModulePath = "$Path\MODULES"; 
		
		if(Test-Path $ModulePath){
			#Check if exists
			if( $NewModulePath -NotContains $ModulePath ){
				$NewModulePath += $ModulePath;
			}
		}
	} else {
		write-host "Path $Path not exists";
	}
	
}

$Env:PATH = $NewPath -Join ';';
$Env:PsModulePath = $NewModulePath -Join ';';
