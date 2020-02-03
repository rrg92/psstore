param(

	#Path to the  directory where setup.exe exists. Can be a path to a mounted is or some extracted directory for example!
	#You must donwload the ISO.
		$Setup = $Env:MSSQL_SETUP_FOLDER
	
	,#Execute the install!
		#By default, script just print parameters and other informations.
		#To ack the install and calls setup.exe, specify this parameter!
		[switch]$Execute = $false
		
	,#The sa user credentials. 
		#Use Get-Credential cmdlet to build a credential to pass in this parameter!
		#If no credential is provided, the scrit will ask some.
		#The script will cache credentials to dont ask every time!
		$SACredentials = $null
	

	,#Credentials containing the service account. 
		#If null, the default service account provided by installer will be used.
		#It will be cached.
		#Also, script will test if this is valid credential (a logon attempt will be done!).
		#You can disable this using -NoCheckServiceAccount parameter.
		$ServiceAccount  = $null
	
	,#Disable service account validation.
		#Check -ServiceAccount parameter for more details!
		[switch]$NoCheckServiceAccount = $false
		
	,#The instance name to use.
		#The default is special name "MSSQLSERVER" what means a "DEFAULT INSTANCE"
		$InstanceName = "MSSQLSERVER"
	
	,#Path where log setup!
		#Defaults to current directory, filename format: InstallSQLServer-<InstanceName>.log
		$LogFile = $null
	
	,#Specify the product key 
		$ProductKey = $null
	
	,#Tell to script attempt to load product key from ini file on installation directory 
		[switch]
		$LoadProductKey
	
	
	,#Specify the server collation!
		$ServerCollation  = "Latin1_General_CI_AI"
	
	,#Add current user as a adminsitrator!
		[switch]$AddCurrentAsAdmin = $false
	
	
	,#Instance directory.
		#If no specified, uses the default of the installer!
		$InstanceDir = $null
	
	,#Services startup type.
		#This will set all installed service startup type.
		[ValidateSet("Automatic","Manual","Disabled")]
		$StartupType = "Automatic"
		
	,#Disable use of credential cache.
		#The credential cache preveents user to have type account every time you run script.
		#This is useful where many erros are happening on install, and you must stop to validate and fix.
		#Without credential cache you must provide credentials every time you run script.
		#With credential cache, script will cache credentials on sessions and reuse it next time.
		[switch]
		$NoCacheCredentials = $false
			
	,#Reset data in credential cache!
		[switch]
		$ResetCachedCredentials = $false
	
	,#Exclude some parameters from install
		#This script is intend to be generic for every SQL Server installation!
		#Some parameters built by script cannot be available in some installer version.
		#You can use this to specify a list of parameter to be remove.
		#The common case to use this is with older versions to install!
		[string[]]
		$ExcludeParams = @()
		
	,#Specify rule to skip on installer
		#Installer can allow you skip some rules.
		#This is useful if you are testing something.
		#Avoid skip rules for production installs!
		[string[]]
		$SkipRules = @()
		
	
		
	,#Action to do!
		#Defaults to Install!
		#Valid actions must be found on documentation.
		#This script can not support all available actions!
		[ValidateSet("Install","RebuildDatabase")]
		$Action = "Install"
)

#Source reference: https://msdn.microsoft.com/en-us/library/ms144259.aspx?f=255&MSPPError=-2147217396

$ErrorActionPreference="Stop"


	function ResolvePath {
		param($path)
		$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($path)
	}
	
	function ActionInstall {
		param($SetupParams)
		
		#Get the cached credentials...
		if($Cached_SAPassword_Install){
			$SACredentials  = $Cached_SAPassword_Install
		}

		if($Cached_SQLServiceAccount_Install){
			
			#If same user passed and exists cached... get the cached...
			if($ServiceAccount -is [string]){
				$CachedServiceUser 	= $Cached_SQLServiceAccount_Install.GetNetworkCredential().UserName;
				
				if($ServiceAccount -eq $CachedServiceUser){
					$ServiceAccount  = $Cached_SQLServiceAccount_Install
				}
			}
		}

		if(!$SACredentials){
			write-host "Provide sa password!"
			$SACredentials = Get-Credential "sa"
			
			if(!$NoCacheCredentials){
				Set-Variable -Scope 2 -Name Cached_SAPassword_Install -Value $SACredentials
			}
			
		}

		$ServiceAccountParams = @();
		if($ServiceAccount){

			if($ServiceAccount -is [string]){
				write-host "provide password for Service Account $ServiceAccount";
				$ServiceAccount = Get-Credential $ServiceAccount;
			}

			#Testing account credentials....
			if(!$NoCheckServiceAccount){
				$AccountName = $ServiceAccount.GetNetworkCredential().UserName
				write-host "Checking service account $AccountName..."
				try {
					Start-Process -Wait 'cmd.exe' -ArgumentList '/c','whoami'  -Credential $ServiceAccount
				} catch {
					throw "There are some problem with service account $AccountName : $_";
				}
			}

			$ServiceAccountParams = @{
				SQLSVCACCOUNT	= $ServiceAccount.GetNetworkCredential().UserName
				SQLSVCPASSWORD	= $ServiceAccount.GetNetworkCredential().Password
				AGTSVCACCOUNT	= $ServiceAccount.GetNetworkCredential().UserName
				AGTSVCPASSWORD	= $ServiceAccount.GetNetworkCredential().Password
			}
			
			if(!$NoCacheCredentials){
				Set-Variable -Scope 2 -Name Cached_SQLServiceAccount_Install -Value $ServiceAccount
			}

		} else {
			$ServiceAccountParams = @{
				SQLSVCACCOUNT	= "NT AUTHORITY\SYSTEM"
				AGTSVCACCOUNT 	= "NT AUTHORITY\SYSTEM"

			}
		}

		$Params = @{
			ACTION 							= "Install"
			IACCEPTSQLSERVERLICENSETERMS 	= $null
			UpdateEnabled 					= $false
			ERRORREPORTING 					= $false
			FEATURES 						= "SQLEngine","Replication","FullText"
			INDICATEPROGRESS 				= $null
			BROWSERSVCSTARTUPTYPE			= "Automatic"
			AGTSVCSTARTUPTYPE				= "Automatic"
			SAPWD							= $SACredentials.GetNetworkCredential().Password
			SECURITYMODE					= "SQL"
			SQLCOLLATION					= $ServerCollation
			INSTANCENAME					= $InstanceName
		} + $ServiceAccountParams 

		if($SkipRules){
			$Params["SkipRules"] = $SkipRules -Join " ";
		}


		if($LoadProductKey){
			$DefaultSetup = $SetupRoot +"\x64\DefaultSetup.ini";	
			write-host "Try load product key from $DefaultSetup"
			
			if(-not(Test-Path $DefaultSetup)){
				throw "DEFAULT_SETUP_INI_NOTOFUND: Not found DefaultSetup.ini. Remove parameter -LoadProductKey or manually specify a Product Key using -ProductKey parameter."
			}
			
			$ProductKey = Get-Content $DefaultSetup | ? {  $_ -match '^PID="([^"]+)"'  } | %{  $matches[1] };
			
			if(!$ProductKey){
				throw "PRODUCTKEY_NOTFOUND_DEFAULTSETUP: Product key was not found on file $DefaultSetup. Remove parameter -LoadProductKey or use -ProductKey parameter"
			}
		}

		if($ProductKey){
			$Params.add("PID", $ProductKey);
		}

		if($AddCurrentAsAdmin){
			$Params.add("SQLSYSADMINACCOUNTS", [System.Security.Principal.WindowsIdentity]::GetCurrent().Name)
		}

		if($InstanceDir){
			$Params.add("INSTANCEDIR", $InstanceDir)
		}

		if($StartupType){
			$Params["SQLSVCSTARTUPTYPE"] = $StartupType
			$Params["AGTSVCSTARTUPTYPE"] = $StartupType
			$Params["BROWSERSVCSTARTUPTYPE"] = $StartupType
		}
		
		return $Params;
	}

	function ActionRebuildDatabase {
		param($SetupParams)
		
		#Get the cached credentials...
		if($Cached_SAPassword_Install){
			$SACredentials  = $Cached_SAPassword_Install
		}

		if(!$SACredentials){
			write-host "Provide sa password!"
			$SACredentials = Get-Credential "sa"
			
			if(!$NoCacheCredentials){
				Set-Variable -Scope 2 -Name Cached_SAPassword_Install -Value $SACredentials
			}
			
		}


		$Params = @{
			ACTION 							= "REBUILDDATABASE"
			INSTANCENAME					= $InstanceName
			SQLCOLLATION					= $ServerCollation
			SAPWD							= $SACredentials.GetNetworkCredential().Password
		}

		if($AddCurrentAsAdmin){
			$Params.add("SQLSYSADMINACCOUNTS", [System.Security.Principal.WindowsIdentity]::GetCurrent().Name)
		}

		return $Params;
	}


#Validate log file!
if(!$LogFile){
	$LogFile = ".\InstallSQLServer-$InstanceName.log"
}

#Valiate setup executable!
	if(!$Setup){
		$SetupRoot = "."
		$Setup = ".\setup.exe"
	} elseif( (Get-Item $Setup -EA "SilentlyContinue").PSIsContainer ){
		$SetupRoot = $Setup;
		$Setup = $Setup +"\setup.exe";
	}


	if(-not(Test-Path $Setup)){
		throw "INVALID_SETUP: Use -Setup Parameter or MSSQL_SETUP_FOLDER environemnt variable to specify a location of setup!. Current setup: $Setup"
	}


#Credentials cache...
	if($ResetCachedCredentials){
		Set-Variable -Scope 1 -Name Cached_SAPassword_Install -Value $null
		Set-Variable -Scope 1 -Name Cached_SQLServiceAccount_Install -Value $null
	}



#Switch action based on parameters!
switch($Action){
	"Install" {
		$Params = ActionInstall $Params;
	}
	
	"RebuildDatabase" {
		$Params = ActionRebuildDatabase $Params;
	}
	
	
	else {
		throw "ACTION_NOTSUPPORTED: $Action";
	}	
}

#Set mandatory parameters action-indepenent
	$Params += @{
		Q	= $null
	};


if($ExcludeParams){
	$ExcludeParams | %{
		write-host "Removing parameter $_";
		$Params.remove($_);
	}	
}

#Build the options to call on command line!
$SetupArguments = @();

$Params.GetEnumerator() | %{
	$ParamName = $_.Key;
	$ParamValue = $_.Value;
	
	if(  $ParamValue -eq $null -or $ParamValue.Length -eq 0  ) {
		$SetupArguments  += "/$ParamName"
		#$CLIParams += "/$ParamName"
		return;
	}
	
	elseif( $ParamValue -is [boolean] -or $ParamValue -is [int] ){
		$SetupArguments  += "/$ParamName=" + [int]$ParamValue
		#$CLIParams += "/$ParamName=" + [int]$ParamValue
	}
	
	else{
		$SetupArguments += "/$ParamName=" + (@($ParamValue|%{'"'+$_.toString()+'"'}) -join ",")
	}

}



$ParamsString = $CLIParams -Join " "

$SetupCall = [scriptblock]::create("$Setup $ParamsString");


if($Execute){


	write-host "Starting setup..."
	#& $SetupCall > $LogFile 
	#Start Setup...
	
	$LogFile 	 	= ResolvePath $LogFile;
	
	$StartProcessParams = @{
		FilePath 				= $Setup
		ArgumentList 			= $SetupArguments
		RedirectStandardOutput  = $LogFile
	}
	
	$SetupProcess = Start-Process @StartProcessParams -PassThru -NoNewWindow
	$SetupPid = $SetupProcess.Id;
	
	write-host "Setup initiated... Pid:$SetupPid LogFile: $LogFile";
	write-host "Waiting finish..."
	
	$SetupRuning = $true;
	while($SetupRuning){
		try {
			 $SetupProcess | Wait-Process -Timeout 1
			 $SetupRuning = $false;
		} catch [System.TimeoutException] {
			#Do some useful thing
			$Actions = Get-Content $LogFile | ?{ $_ -match '^Running Action:(.+)' } | %{ $matches[1] };
			if($Actions){
				write-progress -Activity "Installing SQL Server" -Status $Actions[-1];
			}
			
		}
	}
	
	$ExitCode = $SetupProcess.ExitCode;
	if($ExitCode -eq 0){
		write-host -ForegroundColor Green -BackgroundColor White "INSTALLATION SUCCESSFULLY";
	} else {
		write-host -ForegroundColor Red "Install FAIL!... Reading error from errorlog...";

		$FullErrorMsg = @();
		$ErrorPartFound = $false;
		$AllErrorLog = Get-Content $LogFile;
		$l = -1;
		while($true -and $l -le $AllErrorLog.count){
			$l++;
			$Line = $AllErrorLog[$l];
			
			if($ErrorPartFound){
				$FullErrorMsg += $Line;
								 
				if($Line -eq 'Please review the summary.txt log for further details'){
					break;
				}
				
				continue;
			}
			
			if($Line -eq 'The following error occurred:'){
				$ErrorPartFound = $true;
				continue;
			}
			
		}
		
		if(!$FullErrorMsg){
			$FullErrorMsg += "Maybe, process was killed!"
		}
		
		if($Actions){
			$FullErrorMsg += "LastAction:"+$Actions[-1]
		}
		
		$FullErrorMsg += "INSTALL FAIL: $ExitCode. Check errorlog!";
		$FinalError = $FullErrorMsg -Join "`r`n";
		
		throw $FinalError;
	}
	
} else {
	write-host $SetupArguments;
	
	$Params;
}
