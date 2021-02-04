<#
	.SYNOPSIS
		Setup a SQL Server instance
	
	.DESCRIPTION
		This script builds necessary parameters to call some setup.exe of a SQL Server installer.
		Also, it add some extra help functionality in order to turn setup actions more flexible and fast!
		
		Use Get-Help Install-SqlServer.ps1 -Parameter * to get more detailed help about each parameter.
		
	.EXAMPLE
		
		.\Install-SQLServer -AddCurrentAsAdmin -LoadProductKey -Setup E:\ -Execute -UseDefaultCollation
		
			Installs a default instance, add user running script as sysadmin.
			Uses the default script collation that is Latin1_General_CI_AI
			
	.EXAMPLE
		
		.\Install-SQLServer -AddCurrentAsAdmin  -Setup E:\  -ServerCollation  Latin1_General_BIN -Execute	
		
		You can use -ServerCollation parameter to specify a non default collation!
		If you dont specify -UseDefaultCollation scripts throws a error to remeber you to use the correct and desired collation.
			
		
	.EXAMPLE
		
		.\Install-SQLServer -AddCurrentAsAdmin  -Setup T:\SqlIso.iso -UseDefaultCollation -Execute
		
		In this example we specifu a .iso file for -Setup parameter.
		The script will try mount the iso and dismount after insllation completes.
		If any errors on mounting it will report to you and you can tru mount manully and pass the path.
		Check help of -Setup parameter to see ways to use it.
		
		
	.EXAMPLE
	
		.\Install-SQLServer -AddCurrentAsAdmin -ProductKey "0000-1111-2222-33333-44444" -Setup E:\  -Execute
		
			You can use -ProductKey parameter to specify a alternate product key.
			
	.EXAMPLE
		
		.\Install-SQLServer -AddCurrentAsAdmin  -Setup E:\  -ServiceAccount "Domain\UserName"  -Execute
		
			You can use -ServiceAccount parameter to specify a service account.
			Script will ask service account password in first execution time and caches it.
			if run script again, it will use from this cache and not ask password again).
			To specify a local accouunt, use MachineName\AccountName
			

		
#>
[CmdletBinding()]
param(

	#Path to the  directory where setup.exe exists. 
	#you can specify a path to a setup.exe in some directory or you can specfy just directory that contains setup.exe
	#Or, you can specify a path to a .iso file. If specify this, then script will try mount the iso and use setup inside it.
	#	It thens caches this paths. Subsequent executions dont need specify -Setup because it will use the cache.
	#
	#In every case, you must donwload the ISO
	#The default is use from the environment variable MSSQL_SETUP_FOLDER
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
		$SetupLogFile = $null
	
	,#Specify the product key 
		$ProductKey = $null
	
	,#Tell to script attempt to load product key from ini file on installation directory 
		[switch]
		$LoadProductKey
	
	
	,#Specify the server collation!
		#Specify "auto" to ack that you want know use default collation!
		$ServerCollation
		
	,#Force script use default script collation	
		[switch]$UseDefaultCollation
	
	,#Add current user as a adminsitrator!
		[switch]$AddCurrentAsAdmin = $false
		
	,#Sysadmin accounts names!
		[string[]]$SysAdmins = @()
	
	
	,#Instance directory.
		#If no specified, uses the default of the installer!
		$InstanceDir = $null
		
	,#Data directory.
		#If no specified, uses the default of the installer!
		$DataDir = $null
		
	,#Data directory.
		#If no specified, uses the default of the installer!
		$LogDir = $null
		
	,#Default tempdb directory to data and log!
		#If no specified, uses the default of the installer!
		$TempdbDir = $null
		
	,#Default tempdb directory to data (overwrites -TempdbDir)
		#If no specified, uses the default of the installer!
		$TempdbDataDir = $null
		
	,#Default tempdb directory to log (overwrites -TempdbDir)
		#If no specified, uses the default of the installer!
		$TempdbLogDir = $null
		
	,#Total number of files to create on tempdb!
		#If no specified, uses the default of the installer!
		$TempdbFileCount = $null
	
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
		
	,#Features to install/uninstalll
		[ValidateSet("SQLEngine","Replication","FullText","Conn","BC","IS")]
		[string[]]
		$Features = @("SQLEngine","Replication","FullText","Conn")
		
	,#Additional Features, in addition to -Features 
	 #This is useful to add more features in additoon the defaults
		[ValidateSet("SQLEngine","Replication","FullText","Conn","BC","IS")]
		[string[]]
		$AddFeatures = @()
		
	,#Exclude features (takes precedence)
		[ValidateSet("SQLEngine","Replication","FullText","Conn","BC","IS")]
		[string[]]
		$ExcludeFeatures = @()
		
	,#Action to do!
		#Defaults to Install!
		#Valid actions must be found on documentation.
		#This script can not support all available actions!
		[ValidateSet("Install","Uninstall","RebuildDatabase")]
		$Action = "Install"
		
	,#Force installation of developer edition (useful when using a media containing other editions, like evaluation)
	 #In order to this works, $ProductKey parameter must be empty
		[switch]$DeveloperEdition
)

#Source reference: https://msdn.microsoft.com/en-us/library/ms144259.aspx?f=255&MSPPError=-2147217396

$ErrorActionPreference="Stop"


	function ResolvePath {
		param($path)
		$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($path)
	}
	
	function ActionInstall {
		param($SetupParams)
	
		$Params = @{
			ACTION 							= "Install"
			IACCEPTSQLSERVERLICENSETERMS 	= $null
			ERRORREPORTING 					= $false
			FEATURES 						= $Features
			INDICATEPROGRESS 				= $null
			BROWSERSVCSTARTUPTYPE			= "Automatic"
			AGTSVCSTARTUPTYPE				= "Automatic"
			SQLCOLLATION					= $ServerCollation
			INSTANCENAME					= $InstanceName
		}	

		if($ProductVersion -ge 11){
			$Params.UpdateEnabled = $false;
		}
		
		
		#Validate collation!
		if(!$ServerCollation -and !$UseDefaultCollation){
			throw "Must specify -ServerCollation. If you want use Latin1_General_CI_AI specify -UseDefaultCollation"
		}
		
		
		#Validate product key and edition!
		if($DeveloperEdition -and $ProductKey){
			
			if($ProductKey){
				throw "INVALID_EDITION_OR_PID: Specify -DeveloperEdition or -ProductKey, never both"
			}
			
			#thanks to https://blog.aelterman.com/2017/08/12/silent-installation-of-sql-server-2016-or-2017-developer-edition-from-evaluation-installation-media/
			$ProductKey = '22222-00000-00000-00000-00000';
		}
		

		#Get the cached credentials...
		if($Cached_SAPassword_Install){
			$SACredentials  = $Cached_SAPassword_Install
		}

		if($Cached_SQLServiceAccount_Install){
			
			#If same user passed and exists cached... get the cached...
			if($ServiceAccount -is [string]){
				$CachedServiceUser 	= $Cached_SQLServiceAccount_Install.UserName;
				
				if($ServiceAccount -eq $CachedServiceUser){
					$ServiceAccount  = $Cached_SQLServiceAccount_Install
				}
			}
		}

		if($SACredentials -eq "auto"){
			write-host "Provide sa password!"
			$SACredentials = Get-Credential "sa"
			
			if(!$NoCacheCredentials){
				Set-Variable -Scope 2 -Name Cached_SAPassword_Install -Value $SACredentials
			}
			
			$Params['SAPWD'] 		= $SACredentials.GetNetworkCredential().Password
			$Params['SECURITYMODE'] = "SQL"
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

			$Params += @{
				SQLSVCACCOUNT	= $ServiceAccount.GetNetworkCredential().UserName
				SQLSVCPASSWORD	= $ServiceAccount.GetNetworkCredential().Password
				AGTSVCACCOUNT	= $ServiceAccount.GetNetworkCredential().UserName
				AGTSVCPASSWORD	= $ServiceAccount.GetNetworkCredential().Password
			}
			
			if(!$NoCacheCredentials){
				Set-Variable -Scope 2 -Name Cached_SQLServiceAccount_Install -Value $ServiceAccount
			}

		} else {
			#If 2008r2 or less, then add a default less privileged account...
			#Other versons uses virtual server accoutns by default...
			if($ProductVersion -lt 11){
				$Params += @{
					SQLSVCACCOUNT	= 'NT AUTHORITY\Network Service'
					AGTSVCACCOUNT	= 'NT AUTHORITY\Network Service'
				}
			}
		}



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
			
			write-host "	Loaded ProductKey is:$ProductKey"
		}

		if($ProductKey){
			$Params.add("PID", $ProductKey);
		}

		$SysAdminAccounts = @()
		
		if($AddCurrentAsAdmin){
			$SysAdminAccounts += [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
		}
		
		if($SysAdmins){
			$SysAdminAccounts += $SysAdmins
		}
		
		if($SysAdminAccounts){
			$Params.add("SQLSYSADMINACCOUNTS", $SysAdminAccounts)
		}

		if($InstanceDir){
			$Params.add("INSTANCEDIR", $InstanceDir)
		}

		if($StartupType){
			$Params["SQLSVCSTARTUPTYPE"] = $StartupType
			$Params["AGTSVCSTARTUPTYPE"] = $StartupType
			$Params["BROWSERSVCSTARTUPTYPE"] = $StartupType
		}
		
		#user db directories...
		if($DataDir){
			$Params['SQLUSERDBDIR'] = $DataDir
		}
		
		if($LogDir){
			$Params['SQLUSERDBLOGDIR'] = $LogDir
		}
		
		#tempdb configuration
		if(!$TempdbDataDir -and $TempdbDir){
			$TempdbDataDir = $TempdbDir
		}
		
		if(!$TempdbLogDir -and $TempdbDir){
			$TempdbLogDir = $TempdbDir
		}
		
		
		if($TempdbDataDir){
			$Params['SQLTEMPDBDIR'] = $TempdbDataDir
		}
		
		if($TempdbLogDir){
			$Params['SQLTEMPDBLOGDIR'] = $TempdbLogDir
		}
		
		if($TempdbFileCount){
			$Params['SQLTEMPDBFILECOUNT'] = $TempdbFileCount
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

	function ActionUninstall {
		param($SetupParams)
		

		$Params = @{
			ACTION 							= "Uninstall"
			INSTANCENAME					= $InstanceName
			FEATURES 						= $Features
		}

		return $Params;
	}

	#Get specific version number from a Product version string from SQL Server. This can be obtained with SERVERPROPERTY('ProductVersion')
	Function GetProductVersionPart {
		param($VersionText,$Position = 1)
		
		
		$FirstMatchCount = $Position - 1;
		
		#The logic is simple: Match the string NNN.NNN.NNN.NNN 
		#The first parentheses, matchs first pairs "NNNN." The amount of matches depends of $FirstMatchCount
		#Next parenthesis matchs our deserided part, because previous expressions already matchs that parts that we not want.
			#This is because we can decrement position. If we want first part, then the first expression must match 0 for next catch correct part. 
		$m = [regex]::Match($VersionText,"^(\d+\.){$FirstMatchCount}(\d+).*$");

		#The match results will contains thee groups: The first is entire string, the second is last match of {count}. The next have our data. It is os offset 2 of array.
		$part = $m.Groups[2].Value;
		
		if($part){
			return ($part -as [int])
		} else {
			return $null;
		}
		
		
	}

	#https://msdn.microsoft.com/en-us/library/ms143694.aspx
	Function GetProductVersionNumeric {
		param($Version1,$Parts = 3)

		$Major1 = GetProductVersionPart $Version1 1
		$Minor1 = GetProductVersionPart $Version1 2
		$Build1 = GetProductVersionPart $Version1 3
		$Revision1 = GetProductVersionPart $Version1 4
		
		
		return $Major1 + ($Minor1*0.01) + ($Build1*0.000001) + ($Revision1*0.00000001);
	}



#Validate log file!
if(!$SetupLogFile){
	$SetupLogFile = ".\InstallSQLServer-$InstanceName.log"
}

#Validate setup executable!
	if(!$Setup){
		$SetupRoot = "."
		$Setup = ".\setup.exe"
	} elseif( (Get-Item $Setup -EA "SilentlyContinue").PSIsContainer ){
		$SetupRoot 	= $Setup;		
		$Setup = $Setup +"\setup.exe";
	} else {
		$IsoSetup  			= Get-Variable Cached_IsoSetup -ValueOnly -EA "SilentlyContinue" -Scope 1;
		$OriginalSetup  	= Get-Variable Cached_OriginalIsoSetup -ValueOnly -EA "SilentlyContinue" -Scope 1;
		
		if($Setup -and $Setup -ne $OriginalSetup){
			write-warning "New setup was specified: $Setup (Currently Cached: $OriginalSetup)"
		}elseif($IsoSetup -and (Test-Path $IsoSetup)){
			write-warning "Using previous mounted ISO: $IsoSetup (ISO: $OriginalSetup)";
			$Setup = $IsoSetup
		}
		
		if($Setup -like '*.iso'){
			#Check if already mounted this path!
			$MountedImages = Get-Volume | Get-DiskImage;
			$CurrentMount = $MountedImages | ? { $_.ImagePath -eq $Setup } | select -first 1; 
			
			
			if($CurrentMount){
				$Mounted = $CurrentMount
			} else {
				write-warning "Mounting setup from ISO $Setup...";
				$Mounted = Mount-DiskImage $Setup -Passthru;
			}
			
		
			if($Mounted){
				$MountLetter = ($Mounted | Get-Volume).DriveLetter;
				write-warning "	Mounted to letter $MountLetter...";
				
				if(!$MountLetter){
					throw "INVALID_MOUNT_LETTER: ISO was mounted but not letter was found! Mount manually and use -Setup"
				}
				
				Set-Variable -Scope 1 -Name Cached_OriginalIsoSetup -Value $Setup
				$Setup = "$MountLetter" + ":\setup.exe";
				Set-Variable -Scope 1 -Name Cached_IsoSetup -Value $Setup
				
			} else {
				throw "INVALID_MOUNTED: Iso cannot be mounted $Setup"
			}
			
		}
	}


	if(-not(Test-Path $Setup)){
		throw "INVALID_SETUP: Use -Setup Parameter or MSSQL_SETUP_FOLDER environemnt variable to specify a location of setup!. Current setup: $Setup"
	}

	
	#Getting setup version.
	#We use this to infere sql server versiion!
	$ProductVersionText = (get-item $Setup).VersionInfo.ProductVersion;
	$ProductVersion		= GetProductVersionNumeric $ProductVersionText
	$MajorVersion		= GetProductVersionPart $ProductVersionText 1 
	$MinorVersion		= GetProductVersionPart $ProductVersionText 2 
	$ProductVersionTag	= ('' + $MajorVersion + $MinorVersion).substring(0,3);
	
	write-host "Setup Product Version is $ProductVersionText. NumericVersion: $ProductVersion";
	
#Credentials cache...
	if($ResetCachedCredentials){
		Set-Variable -Scope 1 -Name Cached_SAPassword_Install -Value $null
		Set-Variable -Scope 1 -Name Cached_SQLServiceAccount_Install -Value $null
	}


#Validate features...

$Features = $Features + $AddFeatures |  ? {  $ExcludeFeatures -NotContains $_   } | select -unique


#Switch action based on parameters!
switch($Action){
	"Install" {
		$Params = ActionInstall $Params;
	}
	
	"RebuildDatabase" {
		$Params = ActionRebuildDatabase $Params;
	}
	
	"Uninstall" {
		$Params = ActionUninstall $Params;
	}
	
	
	default {
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

write-host "Using setup file from $Setup";
$SetupCall = [scriptblock]::create("$Setup $ParamsString");


if($Execute){


	write-host "Starting setup..."
	#& $SetupCall > $LogFile 
	#Start Setup...
	
	$SetupLogFile 	 	= ResolvePath $SetupLogFile;
	
	$StartProcessParams = @{
		FilePath 				= $Setup
		ArgumentList 			= $SetupArguments
		RedirectStandardOutput  = $SetupLogFile
	}
	
	$StartTime = Get-Date;
	$SetupProcess = Start-Process @StartProcessParams -PassThru -NoNewWindow
	$SetupPid = $SetupProcess.Id;
	
	write-host "Setup initiated... StartTime:$StartTime Pid:$SetupPid LogFile: $SetupLogFile";
	
	
	if($ProductVersionTag -eq '105'){
		$SetupLogDir = '100'
	} else {
		$SetupLogDir = $ProductVersionTag
	}
	
	
	$SetupLogs 	= $Env:ProgramFiles+"\Microsoft SQL Server\$SetupLogDir\Setup Bootstrap\Log"
	
	#Waiting setup lo folder be created...
	write-progress -Activity "Installing SQL Server $InstanceName ($ProductVersionText)" -Status 'Waiting creation of setup log folder...';
	$WaitLogFolderStart = Get-date;
	while($true){
		$SetupLogFolders = gci $SetupLogs -EA "SilentlyContinue" | ? { $_.CreationTime -ge $StartTime };
	
		if($SetupLogFolders){
			write-host "	Setup log folders after start of setup (started at $StartTime)"
			$SetupLogFolders  | %{
				write-host ("	"+$_.FullName)
				write-host 	("		Created at: "+$_.CreationTime)
			}
			
			if($SetupLogFolders.count -gt 1){
				write-warning 'More than one setup log folder after setup initiated... There are somee other install running parallel?'
			} else {
				$DetailedSetupLogFolder = @($SetupLogFolders)[0].FullName;
			}
			
			break;
		}
	
	
		$ElapsedWaitTime = (get-date) - $WaitLogFolderStart;
		
		if($ElapsedWaitTime.TotalSeconds -gt 60){
			write-warning 'Timeout expired waiting setup log folder at $SetupLogs. Check if all right is ok. We will stop waiting setup log folder...'
			break;
		}
	
		Start-Sleep -s 2;
	}
	
	
	write-host "Waiting setup finish... Detailed log folder is: $DetailedSetupLogFolder"
	$SetupRuning = $true;
	while($SetupRuning){
		try {
			 $SetupProcess | Wait-Process -Timeout 2
			 $SetupRuning = $false;
		} catch [System.TimeoutException] {
			#Do some useful thing
			$Actions = Get-Content $SetupLogFile | ?{ $_ -match '^Running Action:(.+)' } | %{ $matches[1] };
			if($Actions){
				write-progress -Activity "Installing SQL Server $InstanceName ($ProductVersionText)" -Status $Actions[-1];
			}
			
		}
	}
	
	#Setup exit codes (msi exit codes)
	#https://docs.microsoft.com/en-us/windows/win32/msi/error-codes
	$ERROR_SUCCESS 					= 0
	$ERROR_SUCCESS_REBOOT_INITIATED = 1641
	$ERROR_SUCCESS_REBOOT_REQUIRED 	= 3010
	$SUCCESS_EXITS				= @(
				$ERROR_SUCCESS
				$ERROR_SUCCESS_REBOOT_INITIATED
				$ERROR_SUCCESS_REBOOT_REQUIRED
			)
	
	
	$ExitCode = $SetupProcess.ExitCode;
	if($SUCCESS_EXITS -Contains $ExitCode){
		write-host -ForegroundColor Green -BackgroundColor White "INSTALLATION SUCCESSFULLY";
		
		if($ExitCode -eq $ERROR_SUCCESS_REBOOT_INITIATED){
			write-warning "A reboot was initiated!";
		}
		
		if($ExitCode -eq $ERROR_SUCCESS_REBOOT_REQUIRED){
			write-warning "A reboot was required!";
		}
		
	} else {
		write-host "Trying get updated last action...";
		$Actions = @(Get-Content $SetupLogFile | ?{ $_ -match '^Running Action:(.+)' } | %{ $matches[1] });
		
		if($Actions){
			$LastAction = $Actions[-1];
		}
		
		write-host -ForegroundColor Red "Install FAIL!... Reading error from errorlog... LastAction: $LastAction";
		
		if($DetailedSetupLogFolder){
			write-host "You also can check setup log folder at $DetailedSetupLogFolder";
			
			if($LastAction){
				write-host "Check this possible errorlog to determine causes"
				$Filter = $LastAction.replace('install_','');
				gci $DetailedSetupLogFolder | ?{ $_.name -like "*$Filter*" -or $_.name -eq 'Detail.txt' -or $_.name -like 'Summary*' }  | %{
					write-host ("	"+$_.FullName)
				}
			}
		}
		

		$FullErrorMsg = @();
		$ErrorPartFound = $false;
		$AllErrorLog = Get-Content $SetupLogFile;
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
	
	if($OriginalSetup){
		write-warning "Unmounting iso...";
		$dismounted = Dismount-DiskImage -ImagePath $OriginalSetup;
	}
	
} else {
	write-host $SetupArguments;
	
	$Params;
}


