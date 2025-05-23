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
			

	.EXAMPLE
		
		.\Install-SQLServer -AddCurrentAsAdmin  -Setup E:\ -DeveloperEdition -Execute
		
			Installs the developer edition.
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
		
		
	,#Installer map file.
     #This is powershell returning hashtable containing location of setup files!
	 #When Setup is a version number, it uses this file to check if have a path to specific version of installer!
		$SetupMap = $Env:MSSQL_SETUP_MAP
	
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
		[Alias("PID","PK")]
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
		#The difference between Patch and Upgrade is that Patch expects $Setup be a donwloaded package (.exe donwload from update)
		#	Paramrters comes from here: https://docs.microsoft.com/en-us/sql/database-engine/install-windows/installing-updates-from-the-command-prompt?view=sql-server-ver15#supported-parameters
		#	Upgrade value expects be setup.exe extracted from upgrade patch.
		[ValidateSet("Install","Uninstall","RebuildDatabase","Upgrade","Patch","Sysprep")]
		$Action = "Install"
		
	,#Force installation of developer edition (useful when using a media containing other editions, like evaluation)
	 #In order to this works, $ProductKey parameter must be empty
		[switch]$DeveloperEdition
		
	,#Ignore version check in upgrade/patch actions... 
		[switch]$IgnoreUpgradeVersionCheck
)

#Source reference: https://msdn.microsoft.com/en-us/library/ms144259.aspx?f=255&MSPPError=-2147217396

$ErrorActionPreference="Stop"
$SCRIPT_VERSION = "1.1.0"
$DEFAULT_SERVER_COLLATION = "Latin1_General_CI_AI";

	function ResolvePath {
		param($path)
		$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($path)
	}
	
	function ActionInstall {
		param($SetupParams)
	
		$Params = @{
			ACTION 							= "Install"
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
		
		if($ProductVersion -ge 10.5){
			$Params['IACCEPTSQLSERVERLICENSETERMS'] 	= $null
		}
		
		
		#Validate collation!
		if(!$ServerCollation){
			if($UseDefaultCollation){
				$Params.SQLCOLLATION = $DEFAULT_SERVER_COLLATION
			} else {
				throw "Must specify -ServerCollation. If you want use $DEFAULT_SERVER_COLLATION specify -UseDefaultCollation"
			}
		}
		
		if($ServerCollation -eq 'auto'){
			$Params.remove('SQLCOLLATION')
		}

		#Validate product key and edition!
		if($DeveloperEdition -and !$ProductKey){
			$ProductKey = "Developer";
			$DeveloperEdition = $null;
		}
		
		switch($ProductKey){
			# Como encontrei as producs keys?
			# Na pasta de log do instalador tem um rquivo settings.xml que contém!
			# PRocurar por FREEEDITIONS
			# Com base no fato que uso isso desde versoes antigas, entendo que nao muda!
			# Mas, se mudar, teria que fazer um if ou criar uma tabelinha pra cada versao!
						
			{$_-in "Dev","Developer"} {
				$ProductKey = '22222-00000-00000-00000-00000';
			}
			
			{$_ -in "StdDev","StandardDeveloper","Std","Standard"} {
				$ProductKey = '33333-00000-00000-00000-00000';
			}
			
			# novo no 2025
			{$_ -in "StdDev","StandardDeveloper","Std","Standard"} {
				$ProductKey = '11111-00000-00000-00000-00000';
			}
			
			{$_ -in "Eval","Evaluation"} {
				$ProductKey = $null
			}
		}
		
		if($DeveloperEdition -and $ProductKey){
			throw "INVALID_EDITION_OR_PID: Specify -DeveloperEdition or -ProductKey, never both"
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

	#Updagrades the sql server from setup.exe...
	function ActionUpgrade {
		param($SetupParams)
		
		$Params = @{
			ACTION 							= "Upgrade"
			IACCEPTSQLSERVERLICENSETERMS 	= $null
			INSTANCENAME					= $InstanceName
			INSTANCEID						= $null
		}
		
		#Get instance id...
		$InstanceInfo = @(GetInstancesInfo -InstanceName $InstanceName);
		
		if(!$InstanceInfo){
			throw "INSTANCE_NOT_FOUND: $InstanceInfo";
		}
		
		$InstanceId = $InstanceInfo[0].InstanceId;
		
		if(!$InstanceId){
			throw "INSTANCE_ID_PRESENT"
		}
		
		$Params.INSTANCEID = $InstanceId;
		
		CheckUpgradeVersion $InstanceInfo
		
		
		return $Params;
	}

	#Upgrades from a msi package...
	function ActionPatch {
		param($SetupParams)
		
		$Params = @{
			action 							= "Patch"
			IAcceptSQLServerLicenseTerms 	= $null
			instancename					= $InstanceName
			InstanceID						= $null
			quiet							= $true
		}
		
		if($SkipRules){
			$Params["SkipRules"] = $SkipRules -Join " ";
		}
		
		#Get instance id...
		$InstanceInfo = @(GetInstancesInfo -InstanceName $InstanceName);
		
		if(!$InstanceInfo){
			throw "INSTANCE_NOT_FOUND: $InstanceInfo";
		}
		
		$InstanceId = $InstanceInfo[0].InstanceId;
		
		if(!$InstanceId){
			throw "INSTANCE_ID_PRESENT"
		}
		
		$Params.InstanceID = $InstanceName;
		
		CheckUpgradeVersion $InstanceInfo
		
		return $Params;	
	}

	#Sysprep installation...
	function ActionSysPrep {
		param($SetupParams)
	
		$Params = @{
			ACTION 							= "PrepareImage"
			IACCEPTSQLSERVERLICENSETERMS 	= $null
			FEATURES 						= $Features
			INDICATEPROGRESS 				= $null
			INSTANCEID						= $InstanceName
		}	

		if($ProductVersion -ge 11){
			$Params.UpdateEnabled = $false;
		}

		if($SkipRules){
			$Params["SkipRules"] = $SkipRules -Join " ";
		}


		if($InstanceDir){
			$Params.add("INSTANCEDIR", $InstanceDir)
		}
		
		return $Params;
	}


	function CheckUpgradeVersion {
		param($InstanceInfo)
		
		if($IgnoreUpgradeVersionCheck){
			write-warning "Ignoring updrade version check... Just for info: CurrentVersion:$($InstanceInfo.Version) SetupVersion:$ProductVersionText"
			return;
		}
		
		$CurrentNumericVersion = $InstanceInfo.VersionNumeric
		$SetupNumericVersion	 = $ProductVersion
		
		if($CurrentNumericVersion -ge $SetupNumericVersion){
			throw "UPGRADE_SETUP_OLD: CurrentVersion:$($InstanceInfo.Version) (Numeric:$CurrentNumericVersion) | SetupVersion:$ProductVersionText (Numeric = $SetupNumericVersion)"
		}
		 return;
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

	#get installed instances info...
	Function GetInstancesInfo {
		[CmdletBinding()]
		param([string[]]$InstanceName = @())

		$defaultProperties = "PSPath","PSPArentPath","PSChildName","PSDrive","PSProvider"
		$Path = "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL"
		$SqlBaseRegKey = 'HKLM:\SOFTWARE\Microsoft\Microsoft Sql Server'
		 
		if(!$InstanceName){
			if(Test-Path $SqlBaseRegKey){
				$InstanceName = @((Get-ItemProperty $SqlBaseRegKey).InstalledInstances)
			} else {
				return $null;
			}
		}
		 
		$AllInstanceRegKey = Get-ItemProperty -Path $Path;
		$AllInstances = @()
		$VersionPathKey = 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\{0}\MSSQLServer\CurrentVersion'

		foreach($InstName in $InstanceName){
			$InstanceId = $AllInstanceRegKey.$InstName;
			$InstanceInfo = New-Object PsObject -Prop @{
									InstanceName 	= $InstName
									InstanceId		= $InstanceId
									Version			= $null
									VersionNumeric	= $null
									VersionMajor	= $null
									VersionMinor	= $null
								}
								
			$AllInstances += $InstanceInfo;
								
			#Try get version...
			try {
				$InstanceVersionKey = $VersionPathKey -f $InstanceInfo.InstanceId
				$InstanceInfo.Version = (Get-ItemProperty -Path $InstanceVersionKey -Name "CurrentVersion").CurrentVersion
				
				$ProductVersion		= GetProductVersionNumeric $InstanceInfo.Version
				$MajorVersion		= GetProductVersionPart $InstanceInfo.Version 1 
				$MinorVersion		= GetProductVersionPart $InstanceInfo.Version 2 
				
				$InstanceInfo.VersionNumeric = $ProductVersion
				$InstanceInfo.VersionMajor = $MajorVersion
				$InstanceInfo.VersionMinor = $MinorVersion
			} catch {
				write-host "Failed get version of instance: $InstanceName(Id: $($InstanceInfo.InstanceId))";
			}
		}

		return $AllInstances
	}
	
	#CHeck if current users is administrator.
	function IsAdmin {
		#thanks to https://serverfault.com/questions/95431/in-a-powershell-script-how-can-i-check-if-im-running-with-administrator-privil
		$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
		$currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
	}

#Validate log file!
if(!$SetupLogFile){
	$SetupLogFile = ".\InstallSQLServer-$InstanceName.log"
}

#Validate admin
if(-not(IsAdmin)){
	throw "Must run as Administrator";
}

$TargetSetupVersion  = $null;

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
		
		
		if($Setup -match '^\d+\.'){
			$SetupVersion = $SetupVersion;
			
			if(!$SetupMap -and (Test-Path ".\SetupMap.ps1")){
				write-warning "Using setup map of current folder";
				$SetupMap = Resolve-Path ".\SetupMap.ps1"
			}
			
			if(-not(Test-path $SetupMap)){
				throw "MSSQL_SETUP_NOMAPFILE: Setup map not found $SetupMap"
			}
			
			
			#Is Verson setup!
			write-host "Loading setup map $SetupMap";
			$MapContent = & $SetupMap
			
			#Find the version!
			$TargetSetupVersion = $Setup.trim();
			
			$Setup = $MapContent.$Setup;
			
			write-warning "Setup got from SetupMap: $Setup";
			
			if(!$Setup -or -not(Test-Path $Setup)){
				throw "NO_SETUP_MAP: Version $TargetSetupVersion not found in map $SetupMap";
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
	
	if($TargetSetupVersion -and $TargetSetupVersion -ne $ProductVersionText){
		throw "INVALID_SETUP_VERSION: Setup is $ProductVersionText and target is $TargetSetupVersion"
	}
	
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
		$ActivityAction= "Installing";
		$Params = ActionInstall $Params;
	}
	
	"RebuildDatabase" {
		$ActivityAction = "Rebuilding database"
		$Params = ActionRebuildDatabase $Params;
	}
	
	"Uninstall" {
		$ActivityAction = "Uninstalling"
		$Params = ActionUninstall $Params;
	}
	
	"Upgrade" {
		$ActivityAction = "Upgrading";
		$FileName = Split-Path -Leaf $Setup
		
		if($FileName -ne 'setup.exe'){
			throw "Upgrade must use setup.exe. Setup seems a patch? Use Patch -Action value instead."
		}
		
		$Params = ActionUpgrade $Params
	}
	
	"Patch" {
		$ActivityAction = "Patching"
		$Params = ActionPatch $Params
	}
	
	"Sysprep" {
		$ActivityAction = "Sysprep(ing)"
		$Params = ActionSysPrep $Params
	}
	
	
	
	default {
		throw "ACTION_NOTSUPPORTED: $Action";
	}	
}

$ActivityText = "$ActivityAction SQL Server $InstanceName ($ProductVersionText)"

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
	write-progress -Activity $ActivityText -Status 'Waiting creation of setup log folder...';
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
	
	#Details...
	$IsDetailedLog = $false;
	$PoolInstanceLog = $false;
	if($Action -in ('Install','Patch','Upgrade')){
		$AlternateSetupLog = $DetailedSetupLogFolder+'\Detail.txt';
		
		if(Test-Path $AlternateSetupLog){
			$SetupLogFile = $AlternateSetupLog;
			$IsDetailedLog = $true;
			write-warning "SetupLog file changed to $SetupLogFile";
			$PoolInstanceLog = $true;
		}
		
	}
	
	$InstanceSetupLog = $DetailedSetupLogFolder+'\'+$InstanceName+'\Detail.txt';
	
	write-host "Waiting setup finish... Detailed log folder is: $DetailedSetupLogFolder"
	$SetupRuning = $true;
	$UsingInstanceSetupLog = $false;
	while($SetupRuning){
		try {
			 $SetupProcess | Wait-Process -Timeout 2
			 $SetupRuning = $false;
		} catch [System.TimeoutException] {
			
			#Get detail of specific instance...
			if($PoolInstanceLog -and !$UsingInstanceSetupLog){
				
				#Path exist?
				if(Test-Path $InstanceSetupLog){
					$UsingInstanceSetupLog = $true;
					write-warning "Instance setup log detected. SetupLogFile changed to $InstanceSetupLog"
					$SetupLogFile = $InstanceSetupLog;
				}
			}
			
			
			#Do some useful thing
			$Actions = Get-Content $SetupLogFile | ?{ $_ -match 'Running Action:(.+)' } | %{ $matches[1] };
			if($Actions){
				write-progress -Activity $ActivityText -Status $Actions[-1];
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
		$Actions = @(Get-Content $SetupLogFile | ?{ $_ -match 'Running Action:(.+)' } | %{ $matches[1] });
		
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
		$InsideError = $false;
		$AllErrorLog = Get-Content $SetupLogFile;
		$l = $AllErrorLog.count;
		while($l--){
			$Line = $AllErrorLog[$l];
			
			#If is within error...
			if($InsideError){
				$FullErrorMsg += $Line -replace '^\([^\(]+\) \d\d\d\d\-\d\d\-\d\d \d\d\:\d\d\:\d\d \w+\:','';
								
				if($Line -match $EndOfSearchMark){
					break;
				}
				
				continue;
			}
			
			
			if($Line -match 'Result error code: .+' ){
				$InsideError = $true;
				$EndOfSearchMark = 'Exception type: .+';
				continue;
			}
		}
		
		$null = [array]::reverse($FullErrorMsg);
		
		if(!$AllErrorLog){
			$FullErrorMsg += "Setup log $SetupLogFile not generated output..."
		} elseif(!$FullErrorMsg){
			$FullErrorMsg += "Maybe, process was killed!"
		}
		
		if($Actions){
			$FullErrorMsg += "LastAction:"+$Actions[-1]
		}
		
		$FullErrorMsg += "INSTALL FAIL: $ExitCode. Check errorlog!";
		$FinalError = $FullErrorMsg -Join "`r`n";
		

		write-error $FinalError;
	}
	
	if($OriginalSetup){
		write-warning "Unmounting iso...";
		$dismounted = Dismount-DiskImage -ImagePath $OriginalSetup;
	}
	
} else {
	write-host $SetupArguments;
	
	$Params;
}


