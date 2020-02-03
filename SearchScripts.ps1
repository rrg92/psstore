<#
	Creaed by Rodrigo Ribeiro Gomes
	
	Search for a script!
#>
param(

	$search
	
	,$InfileRegex

)
$ErrorActionPreference = "Stop";


Function SearchFolder {
	param($f,$s)
	
	$Founds = @();
	
	$f | %{
	
		if($_.PsIsContainer){
		
			
			if($_.Name -eq '.git'){
				return @();
			}
			
			
			if($_.Name -like  $s ){
				
				#Get all files...
				$Founds += @(gci $_ | ?{!$_.PsIsContainer});
				
				#Check subdirectories...
				$Founds += SearchFolder @(gci $_ | ?{$_.PsIsContainer}) -s $s
			}
			
		} else {
			
			if($_.Name -like $s){
				$Founds += $_;
			}
			
		}
	}

	return $Founds;
}

$Found = @();
if($Search){

	$Found += SearchFolder -f (gci "$PsScriptRoot") -s $Search
}



$FileFound = @()
if($InfileRegex){
	write-host "content searching..."
	
	$FileFound = gci "$PsScriptRoot\*.ps1" -recurse |  ?{  $_ | sls $InfileRegex   }
}

$All = $Found + $FileFound;

if($All){
	$FoundNames = $All | %{$_.FullName.replace("$PsScriptRoot\","")}
	$FoundNames  | sort -unique | %{"`t$_"}
}
