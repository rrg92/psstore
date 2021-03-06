#Faz o backup do SQL, logando os erros que ocorrem.
#Criado por Rodrigo Ribeiro Gomes

param(

	#Specify the instance name to connect
		[Alias("Instancia")]
		$ServerInstance 
	
	,#Specify the backup type. Valid values: FULL, DIFF, LOG.
		$BackupType 	= "FULL"
	
	,#Specify the path to backup filename.
	 #YOu can use predetermined variables expressions to build dynamic paths.
	 #Variables expressions are values the cmdlet will replace in execution time.
	 #It takes the form "<VariableName>" where "VariableName" is the name of the variable.
	 #For example, the if you specify 'C:\SQLBackups\<BT>\<DN>_<TS>.<BE>' and taking a FULL backup of database "Test" at '2017-02-01 09:35:50' the path to the backup will be C:\SQLBackups\FULL\Test_20170201093550.bak
	 #The supported list of expressions variables is (multiple variables names that contains same value are separated by commad')
	 #
	 #	BackuppType,BT		= The same value of "BackupType" parameter
	 #	DatabaseName,DN 	= The database name.
	 #	BackupExt,BE		= The backup extension. 'bak' for FULL and DIFF and 'trn' for log backups.
	 #	Timestamp,TS		= The timestamp in format 'yyyyMMddHHmmss' of time the database backup will taken.
	 #					  	  Note that this timestamp is calculated by powershell and not by T-SQL. Then, some time difference can exists at time it is calculated at time the backup is taken.
	 #	ServerName,SN		= The server name (returned by @@SERVERNAME property).
	 #	MachineName,MN		= THe machine name (returned by SERVERPROPERTY('MachineName')
	 #	InstanceName,IN		= The instance name (returned by SERVERPROPERTY('InstanceName'). If null, means default instance, and the value is 'MSSQLSERVER')
	 #	PhysicalName,PN		= The physical name of the server (returned by SERVERPROPERTY('ComputerNamePhysicalNetBios')).
	 #	BasicInfo,BI		= It is a shortcut for '<MN>$<IN>_<DN>_<BT>_<TS>.<BE>'
	 #
	 #	Dynamic,DY			= Indicates the values comes from $DynamicValueScript parameter.
	 #							Check DynamicValueScript parameter for more information.							
	 #
	 #
	 #
	 #
	 #
	 # The cmdlet will replace the characteres that cannot be used in paths by the character specified in INvalidReplacer parameter.
		$Destination	= '<BI>'
		
		
	,#Its is a array containing database names that must be included on backup. If null, all databse is included.
	 #This is deprecated. Use 'FiltroEx' instead.
		$Filtro = $null
		
	,#The folder to put log file. THe cmdlet will generate a log file for track restore status.
	 #The log will contains all information about execution and possible errors.
	 #If you dont specify a folder, the cmdlet will uses a "logs" folders in same directory on this script is found.
	 #Inside of this folder, the script will create a subdirectoru with timestmap of start of execution and inside them, the SQLBackup.log file will be placed.
		$LogFolder = $null
		
	,#Log Level
		$LogLevel = "DETAILED"
	
	,#A custom Query to retrieve databases.
	 #This is useful when you wants use your own filters to choose the databases.
	 #The query must return following columns:
	 #
	 #	name = the dtaabase name
	 #  recovery_model_desc = The description of rexovery model 
	 #	is_read_only = 1 if database is read_only, or 0 otherwise.
	 #
		$CustomQuery = $null
		
	,#By default, cmdlet generates COPY_ONLY backups for security. If using this scripts to takeregular backups, uses this switch to disbale copy_only.
		[switch]$NoCopyOnly=$false
		
	,#Indicates that scripts must end returning a exit code. It is useful for using with SQLAgent, for example, or another script that checks exit code.
	 #The sucess exit code is 0.
		[switch]$ReturnExitCode
		
    ,#This is more sofisticaed way to filter. Uses them.
	 #You can specifuy a array of strings where each string is a databse name pattern.
	 #YOu can use the same wildcards of "LIKE" to filter.
	 #If a string starts with a "-", then it is a negation, indicates that database match the filter must be excluded.
	 #For example, consider the following filterex value: '%','-D%'
	 #This will return all databases, except that one that starts with 'D'.
	 #Negation filters have priority.
		[string[]]$FiltroEx = @()
		
    ,#NO execute anyu backup command. This is useful for validate filter.
		[switch]$ShowOnly = $false
		
	,#Character that will replace invalid characters for paths in expressions variables values.
	 #For example, if connecting to a named instance, the character '\' will be part of ServerName expressions variable.
	 #The cmdlet will replace this character '\' by a '$' because it cannot be part of filenames.
	 #If wants stops this behavios, just specify a empty string ''.
		$InvalidReplacer = '$'
		
	,#The destination directory of backup. You can use this to specify a fixed direcotry.
	 #The $Destination value (after the variables expressions are replaced) will be append to this, if it not null.
	 #This is for convenience only. You can specify full path on Destination parameter.
		$DestinationDir = $null
		
	,#By default, if instance supports, the COMPRESSION option is used to generate compressed backups.
	 #If you wants generate no compressed backups, specify this option and cmdlet will use 'NO_COMPRESS' option (if supported by instance)
		$NoCompress	= $false
		
	,#Forces scripts dont skip log backups when database is in readonly.
	 #By default, if backup type if LOG and database is read only, the cmdlet will skip the backup.
	 #With this, the backup will be taken.
	 #Note that at this situation, engine  generate copy_only backups indepently of COPY_ONLY option.
		[switch]$ForceReadOnlyLog = $false
		
	,#Script used to generate value for <Dynamic> variable (Check Destination paramter for more details about variables.)
	 #This script will be executed for each database.
	 #The special variable $_ will contains following properties:
		# variables: with same variables available (long names only).
		# store: a hashtable that user can persist values between databases executions (because )
		[scriptblock]$DynamicValueScript = $null
		
	,#Add this backup options to BACKUP DATABASE command. Check BACKUPT options in microsoft documentaiton.
		[string[]]$BackupOptions = @()
		
	,#Extended property backup prefix
	 #This control the extended property prefix that script will consider when querying extended properties.
	 #The script will check the value of some extended properties of databases to guide in execution.
	 #The combination of this prefix plus following values can be defined on database level.
	 #
	 #	EXCLUDE		= Specify the backup types to ingore (comma separated). POssible values: FULL,DIFF,LOG.
	 #
		$EPrefix = "SQLBACKUP_"
	 
	 ,#Disable extended properties check!
		[switch]
		$DisableEP = $false
)

$ErrorActionPreference = "Stop";

#Auxiliary
Function FormatSQLErrors {
	param([System.Exception]$Exception, $SQLErrorPrefix = "MSSQL_ERROR:")
	
	if(!$Exception){
		throw "INVALID_EXCEPTION_FOR_FORMATTING"
	}
	
	$ALLErrors = @();
	$bex = $Exception.GetBaseException();
	
	if($bex.Errors)
	{
		$Exception.GetBaseException().Errors | %{
			$ALLErrors += "$SQLErrorPrefix "+$_.Message
		}
	} else {
		$ALLErrors = $bex.Message;
	}
	
	
	return ($ALLErrors -join "`r`n`r`n")
	
	<#
		Returns a object containing formated sql errors messages
	#>
}


#Determining the current directory!
$CurrentFile = $MyInvocation.MyCommand.Definition
$CurrentDir  = [System.Io.Path]::GetDirectoryName($CurrentFile)
$BaseDir	 = $CurrentDir 
push-location;
set-location $BaseDir;


try {
	#Getting CustomMSSQL module!
	

	#Getting start of script!
	$SessionStartTime = (Get-Date)
	
	#Checking parameters!
		if(!$DestinoBackup){
			$DestinoBackup	= '';
		}
		
		if( "DIFF","FULL","LOG" -NotContains $BackupType ){
			throw "INVALIDBACKUP_TYPE: $BackupType";
		}
		
		#If servername like *\MSSQLSERVER, then remove \MSSQLSERVER part...
		if($ServerInstance -like '*\MSSQLSERVER'){
			$ServerInstance = $ServerInstance.replace('\MSSQLSERVER','');
		}

	#Logging from CustomMSSQL facilities!
	$L = (New-LogObject)
	$L.LogTo = @("#");  #By default, log to host...
	$L.LogLevel = $LogLevel; 
	$L.ignoreLogFail = $false

	$StartMsg = "Starting script! SessionStartTime: $SessionStartTime. User: $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name) Computer: $($Env:ComputerName)";
	$L | Invoke-Log 'Logging start!' 'PROGRESS'

		#Logging directory
		if($LogFolder){
			
			if($LogFolder -match '^\.[\\/](.+)'){
				$LogFolder = "$CurrentDir\$($matches[1])"
			}
			
		} else {
			$LogFolder = $CurrentDir+'\logs';
		}
		$LogDir			= $SessionStartTime.toString("yyyyMMdd-HHmmss")
		$FullLogdir 	= "$LogFolder\$LogDir"
		$LogFile		= "$FullLogdir\SQLBackup.log";
		

		$L | Invoke-Log "Logging file: $LogFile" 'PROGRESS'


		#Attempts validate log directory!
		if(-not(Test-Path $FullLogdir)){
			try{
				$dir = mkdir $FullLogdir -force
			} catch {
				$L | Invoke-Log "LOGDIR_CREATION_FAILED: $_" 'PROGRESS'
			}
		}

		#Adds log file to the log...
		$L.LogTo += $LogFile;
		$L | Invoke-Log "Starting logging to file now. $StartMsg" 'PROGRESS'
		
		$L | Invoke-Log "Checking instance $ServerInstance..." "PROGRESS"
		
		try {
			$InstanceInfoSQL = @(
				"SELECT"
				"	 ServerName = @@SERVERNAME"
				"	,MachineName = SERVERPROPERTY('MachineName')"
				"	,InstanceName = ISNULL(SERVERPROPERTY('InstanceName'),'MSSQLSERVER')"
				"	,PhysicalName = ISNULL(SERVERPROPERTY('ComputerNamePhysicalNetBios'),SERVERPROPERTY('MachineName'))"
				"	,SupportsCompression  = (select count(*) from msdb.sys.columns where object_id = object_id('msdb..backupset') and name = 'compressed_backup_size' )"
				"	,SupportsCopyOnly  = (select count(*) from msdb.sys.columns where object_id = object_id('msdb..backupset') and name = 'is_copy_only' )"
			) -Join "`r`n"
			
			$InstanceInfo = Invoke-NewQuery -ServerInstance $ServerInstance -Query $InstanceInfoSQL
		} catch {
			throw "INSTANCE_CHECK_FAIL: $_";
		}
		
		$L | Invoke-Log "Getting databases..." 'PROGRESS'
		try {

            if($FiltroEx){
				#The FiltroEx controls advanced filtering
				#Check -FiltroEx parameter for more info.

				#Initial commands to be executed ...
                $SQLFilterEx = @(
                    "IF OBJECT_ID('tempdb..#FilterEx') IS NOT NULL DROP TABLE #FilterEx;"
                    "CREATE TABLE #FilterEx (Filter nvarchar(max))";
                     "IF OBJECT_ID('tempdb..#FilterExNot') IS NOT NULL DROP TABLE #FilterExNot;"
                      "CREATE TABLE #FilterExNot (Filter nvarchar(max))";
                )

				#The extended filter allows specify negation.
				#We will use two tables. ONe for 'include' filters (these that no start with a -) and another for exclude filter.
				#THe values will be inserted according in your tables for correc filtering after.
                $SQLFilterEx += $FiltroEx | %{  
                    
                   #If filter starts with a '-', then, insert into Not Filter table...
                    if($_ -like "-*"){
                       $FilterExpr = $_ -replace "^-","";
                       "INSERT INTO #FilterExNot VALUES('$FilterExpr')" ;
                    } else {
                        "INSERT INTO #FilterEx VALUES('$_')";
                    }

                    
                };

                
				#Now, this is query where magic works.
				#First part of query will get all databases in 'inlucde'.
				#Second part get all databases in 'exlcude'
				#THe SQL EXCEPT operator will remove all database names dat are returned by second query (that query returns excluded databases...)
                $QueryListaBases = $SQLFilterEx + @(
                    "SELECT DISTINCT D.name,D.recovery_model_desc,D.is_read_only"
                    "FROM sys.databases D"
                    "JOIN #FilterEx FEX ON D.name like FEX.Filter COLLATE Latin1_General_CI_AI"

                    "EXCEPT"

                    "SELECT DISTINCT D.name,D.recovery_model_desc,D.is_read_only"
                    "FROM sys.databases D"
                    "JOIN #FilterExNot FEXN ON D.name like FEXN.Filter COLLATE Latin1_General_CI_AI"
                    "WHERE d.name NOT IN ('tempdb')"
                ) -Join "`r`n";


            } elseif($Filtro){
				#The Filtro parameter is more simple  filtering mechanism...
				$ListaBasesFiltro = @($Filtro | %{"'$_'"}) -join ","
				$QueryListaBases = "SELECT name,recovery_model_desc,D.is_read_only FROM sys.databases D WHERE d.name NOT IN ('tempdb') AND D.name in ($ListaBasesFiltro)"
			} else {
				#If not filtering parameter was passed, then just return all databases!
				$QueryListaBases = "SELECT name,recovery_model_desc,D.is_read_only FROM sys.databases D WHERE d.name NOT IN ('tempdb')"
			}
			
			if($CustomQuery){
				#If a CustomQuery was specified, uses it to return.
				#The required columns names must be returned to script works corrctly.
				$QueryListaBases = $CustomQuery;
			}

			#Log the query used to retrieve databaase...
			$L | Invoke-Log "	Executing SQL to get dataabaes: $QueryListaBases" 'PROGRESS'
			$Bases = @(Invoke-NewQuery -ServerInstance  $ServerInstance -Query $QueryListaBases)
		} catch {
			$SQLError = FormatSQLErrors -Exception $_.Exception;
			throw "DATABASES_GET_FAIL: $SQLError";
		}
		
		
		#Extended properties checking!
		$EPIndex = @{};
		if(!$DisableEP){
			$L | Invoke-Log "	Getting extended properties with prefix $EPrefix..." 'PROGRESS'
			
			$QueryEP = @(
				"IF OBJECT_ID('tempdb..#Props') IS NOT NULL DROP TABLE #Props;"
				'CREATE TABLE #Props (DatabaseName sysname,PropName varchar(150), PropValue varchar(1000));'
				"EXEC sp_MSforeachdb '"
				'	USE [?];'
				'	INSERT INTO' 
				'		#Props(DatabaseName,PropName,PropValue)'
				'	SELECT '
				'		 DB_NAME()  COLLATE Latin1_General_CI_AI'
				'		,EP.name	COLLATE Latin1_General_CI_AI'
				'		,CONVERT(varchar(1000),EP.value)	COLLATE Latin1_General_CI_AI'
				'	FROM'
				'		sys.extended_properties EP'
				'	WHERE'
				"		EP.class_desc = ''DATABASE''"
				'		AND'
				"		EP.name LIKE ''$EPrefix%'' COLLATE Latin1_General_CI_AI"
				"'"
				'SELECT * FROM #Props;'
			) -Join "`r`n"
			
			$L | Invoke-Log "	Query: `r`n$QueryEP" 'DEBUG';
			
			$ExtProps = @(Invoke-NewQuery -ServerInstance  $ServerInstance -Query $QueryEP)
			
			#Indexes into EPIndex!
			if($ExtProps){
				$L | Invoke-Log "	Builing extended property index..." 'PROGRESS'
				$ExtProps | %{
					$PropName = $_.PropName -replace "^$EPrefix",''
					$DBSlot = @{};
				
					if($EPIndex.Contains($_.DatabaseName)){
						$DBSlot = $EPIndex[$_.DatabaseName];
					} else {
						$DBSlot = @{};
						$EPIndex[$_.DatabaseName] = $DBSlot;
					}
					
					$L | Invoke-Log "	Adding prop $PropName to db $($_.DatabaseName). Value: $($_.PropValue)" 'DEBUG'
					
					$DBSlot[$PropName] = @($_.PropValue -split "," | %{$_.trim()});
				}
			}
		}
		
		#Contains all test must be taken to check if a backup type can be executed on a database.
		#Each test is a key on hashtable bellow. The values are scriptblocks with logic to test.
		#Scripts must return $true if test no pass, or $false, if test pass (yes, the logic is inverted because this scripts represents invalid situations)
		#The script will be executed inside loop of databases... same scope... Thus, some local variables will available...
		$TESTES = @{
		
			#Diff backup on master database?
			MASTER_DIFF = {
							return $base.Name -eq 'master' -and $BackupType -eq "DIFF";
						}
						
			#is tempdb?
			TEMPDB = {
						return $base.Name -eq 'tempdb';
					}
			
			#Log backup on database with simple recovery?
			LOG_ON_SIMPLE = {
						return $base.recovery_model_desc -eq "SIMPLE" -and $BackupType -eq "LOG"
					}
					
			#LOG backups on READONLY Database (This generate copy only backups)
			LOG_ON_READONLY = {
			
						$IsLogReadOnly = $BackupType -eq "LOG" -and $base.is_read_only;
						
						
						if($IsLogReadOnly -and $ForceReadOnlyLog){
							$L | Invoke-Log "	Log backup under read_only will be taken due to ForceReadOnly" 'PROGRESS'
							return $false;
						} else {
							return $IsLogReadOnly;
						}

				}
				
			
			#EXCLUDED
			EXCLUDED_EXTENDED_PROPERTY = {
					if($EPIndex.Contains($base.Name)){
						return $EPIndex[$base.Name].EXCLUDE -Contains $BackupType
					}
					
					return $false;
				}
			
		}
		
			
		#This var constrols if ocurred some fail in database backup.
		$HouveFalhasBackup = $false;
		if($Bases){
			#This will hold some summary about progress!
			$DatabaseSummary = @();

			
			$L | Invoke-Log "Starting iteration on database list. Total databases: $($Bases.count)" 'PROGRESS'
			
			#Regular expression to match variables in destination path!
			$ExprRegex = [regex]'(?i)<([a-z0-9]+)>';
			$ExprVars = @{
				BackupType 		= $BackupType
				BT 				= $BackupType
				DatabaseName	= $null
				DN				= $null
				BackupExt		= $null
				BE				= $null
				Timestamp		= $null
				TS				= $null
				ServerName		= $InstanceInfo.ServerName
				SN				= $InstanceInfo.ServerName
				MachineName		= $InstanceInfo.MachineName
				MN				= $InstanceInfo.MachineName
				InstanceName	= $InstanceInfo.InstanceName
				'IN'			= $InstanceInfo.InstanceName
				PhysicalName	= $InstanceInfo.PhysicalName
				PN				= $InstanceInfo.PhysicalName
				BasicInfo		= $null
				BI				= $null
				Dynamic			= $null
				DYN				= $null
			}
			
			
			#Replaces invalid paths characters from variables...
			$InvalidChars = [System.IO.Path]::GetInvalidPathChars() + [System.IO.Path]::GetInvalidFileNameChars()
			@($ExprVars.keys) | %{
				$KeyValue = $ExprVars[$_];
				
				if($KeyValue){
					$InvalidChars | %{
						$KeyValue = $KeyValue.replace($_.toString(),$InvalidReplacer);
					}
				
					$ExprVars[$_] = $KeyValue;
				}
				
			}
			
			#Reg exp replacer to be used when searching for variables inside parameters...
			$ExprRegexEval = {
				param($M)
				$VarName 		= $M.Groups[1].Value;
				
				if(!$ExprVars){
					$ExprVars = @{};
				}
				
				
				if($ExprVars.Contains($VarName)){
					$VarValue = $ExprVars[$VarName];
					return [string]$VarValue;
				}
			}
			
			#Dynamic script store.
			$dynstore = @{};
			
			
			
			#Database loop!
			:LoopBases foreach($base in $Bases){
				$L | Invoke-Log "	Database $($base.Name)" 'PROGRESS'
				
				#Summary object!
				$Summary = New-Object PsObject;
				$Summary | Add-Member -Type Noteproperty -Name "DatabaseName" -Value $base.Name
				$Summary | Add-Member -Type Noteproperty -Name "Status" -Value $null
				$Summary | Add-Member -Type Noteproperty -Name "Error" -Value $null
				$DatabaseSummary += $Summary;
				
				
				$Suportado = $true;
				$FailedTests = @();
				
				
				#Executing test against curent db...
				$L | Invoke-Log "		Checking if backup is supported" 'PROGRESS'
				:LoopTestes foreach($Teste in $TESTES.GetEnumerator()) {
					$NomeTeste 	= $Teste.Key;
					$Script		= $Teste.Value;
					
					$ResultadoTeste = . $Script;
					if($ResultadoTeste){
						$FailedTests += $NomeTeste;
						$L | Invoke-Log "			Backup check failed: $NomeTeste" 'PROGRESS';
						$Suportado = $false;
					}
					
				}

				#Handle result of test...
				if($suportado){
					$L | Invoke-Log "			SUCESSO!" 'PROGRESS'
				} else {
					$L | Invoke-Log "			Skipping backup $BackupType of database $($base.Name). Check previos messages for reason" 'PROGRESS'
					$Summary.Status = "Ignored"
					$Summary.Error = $FailedTests -Join ","
					continue :LoopBases;
				}
				

				#Setup copy_only option
				$CopyOnlyFlag = $true;
				if($NoCopyOnly){
					$CopyOnlyFlag = $false;
				}

				#Determining backup type!
				$TSQLBackupType = "DATABASE";
				$ExprVars.BackupExt = 'bak'
				if( $BackupType -eq "LOG" ){
					$TSQLBackupType = "LOG";
					$ExprVars.BackupExt = 'trn'
				}
				
				
				#Expanding and calculating variable of expressions.
				$ExprVars.BE = $ExprVars.BackupExt
				$ExprVars.DatabaseName 	= $base.Name;
				$ExprVars.DN 			= $base.Name;
				$ExprVars.Timestamp = (Get-Date).toString("yyyyMMddHHmmss");
				$ExprVars.TS 		= $ExprVars.Timestamp
				
				
				$ExprVars.BasicInfo	= (@(
					$ExprVars.MachineName+"$"+$ExprVars.InstanceName
					$ExprVars.DatabaseName
					$ExprVars.BackupType
					$ExprVars.Timestamp
				) -Join "_")+"."+$ExprVars.BackupExt
				$ExprVars.BI = $ExprVars.BasicInfo;
				
				#THe dynamic script variable!
				#Resets the content of the dynamic value!
				$ExprVars.Dynamic = $null;
				$ExprVars.DYN = $null;
				if( $DynamicValueScript ){
					$DynamicValue = ( New-Object PSObject -Prop @{variables=$ExprVars;store=$dynstore} )  | %{ . $DynamicValueScript }
				} else {
					$DynamicValue = $null
				}
				$ExprVars.Dynamic = $DynamicValue;
				$ExprVars.DYN = $DynamicValue;
				
				
				#Building the target filepath (to be used in TO DISK =)
				$TSQLDestinationFile = $ExprRegex.Replace($Destination, $ExprRegexEval );
				if($DestinationDir){
					$TSQLDestinationFile = "$DestinationDir\$TSQLDestinationFile";
				}

				#If length of path in more thant maxpath
				$TSQLDestFileLength = $TSQLDestinationFile.Length;
				if( $TSQLDestFileLength -gt 260){
					$HouveFalhasBackup = $true;
					$Summary.Error  = "Skipping backup $BackupType of database $($base.Name). Path length is $TSQLDestFileLength. Path: $TSQLDestinationFile";
					$L | Invoke-Log "			BACKUP_FAIL: Skipping backup $BackupType of database $($base.Name) due to maximum path" 'PROGRESS'
					$Summary.Status = "Fail";
					continue :LoopBases;
				}
				
				#Creates parent directory, if not exists!
				$Parents = [IO.Path]::GetDirectoryName($TSQLDestinationFile);
				if($Parents){
					if(![IO.Directory]::Exists($Parents)){
						
						if($ShowOnly){
							$L | Invoke-Log "		Parent directory ~$Parents~ do not exists. Re-run without Showonly, that script will attempts creates them." 'PROGRESS';
						} else {
							try {
								$NewDir = New-Item -ItemType Directory -Path $Parents -Force;
							} catch {
								$HouveFalhasBackup = $true;
								$L | Invoke-Log "		BACKUP_FAIL: Cannot create the parent directory $Parents. Error: $_" 'PROGRESS';
								$Summary.Status = "Fail"
								$Summary.Error  = "ParentDirectoryCreationFailed: $_";
								continue :LoopBases;
							}
						}
						

					}
				}

				#Building WITH OPTIONS of backup...
				$WithOptions = @()
				if($CopyOnlyFlag -and $InstanceInfo.SupportsCopyOnly){
					$WithOptions += 'COPY_ONLY'
				}
				
				if($BackupType -eq "DIFF"){
					$WithOptions += 'DIFFERENTIAL'
				}
				
				if($InstanceInfo.SupportsCompression){
					if($NoCompress){
						$WithOptions += 'NO_COMPRESSION'
					} else {
						$WithOptions += 'COMPRESSION'
					}
				}
				
				if($BackupOptions){
					$WithOptions += $BackupOptions
				}
			
				#Remove duplicates, if any...
				$WithOptions =  $WithOptions | Select-Object -unique
			
				#Building the "BACKUP DATABASE" command!
				$TSQLBackupBuild = @(
					"BACKUP $TSQLBackupType"
					"	[$($base.name)]"
					"TO DISK = '$TSQLDestinationFile'"
				)
				
				if($WithOptions){
					$TSQLBackupBuild += "WITH"
					$TSQLBackupBuild += ($WithOptions -Join "," )
				}
				
				
				$TSQLBackup = $TSQLBackupBuild -join "`r`n";
				$L | Invoke-Log "		SQL Backup command: $($TSQLBackupBuild -join ' ')" 'PROGRESS';
				
                if($ShowOnly) {
                     $L | Invoke-Log "		ShowOnly enabled. No SQL will be executed!" 'PROGRESS';
                } else {
				    try {
					    $L | Invoke-Log "		Executing backup..." 'PROGRESS';
					    $BackupStarTime = (Get-Date)
					    $BackupResult = Invoke-NewQuery -ServerInstance  $ServerInstance -Query $TSQLBackup 
					    $BackupEndTime = (Get-Date);
					    $TempoTotal = $BackupEndTime-$BackupStarTime
					    $L | Invoke-Log "		SUCCESS! Total time: $TempoTotal. File: $TSQLDestinationFile" 'PROGRESS';
						$Summary.Status = "Sucess"
						$Summary.Error = "TotalTime: $TempoTotal"
				    } catch {
					    $SQLError = FormatSQLErrors -Exception $_.Exception;
					    $L | Invoke-Log "		BACKUP_FAIL: $SQLError" 'PROGRESS';
					    $HouveFalhasBackup = $true;
						$Summary.Status = "Fail"
						$Summary.Error  = "TSQLError: $SQLError";
					    continue :LoopBases;
				    }
                }
				
			}

		} else {
			$L | Invoke-Log "No databases elegible to backup" 'PROGRESS'
			return;
		}
		
	#Logs the summary!
	
	$SummaryOutput = @();
	
	$DatabaseSummary | %{
		$SummaryOutput += "Database: $($_.DatabaseName)`r`nStatus:$($_.Status)`r`nError:$($_.Error)"
	}
	
	$SummaryOutput = $SummaryOutput -join "`r`n`r`n";
	$L | Invoke-Log "Database Summary: " 'PROGRESS'
	$L | Invoke-Log "`r`n$SummaryOutput" 'PROGRESS'
	
	if($HouveFalhasBackup){
		$ExitCode = 1000 #High thant 1000, will contains backup fails!
		throw "BACKUP_FAILS: There are fails. Check previous messages in the log."
	}

	$ExitCode = 0;
	$L | Invoke-Log "Script finished successfully" 'PROGRESS'
} catch {
	$ExitCode = 1; #Generic error.
	if($ReturnExitCode){
		$L | Invoke-Log "UNHANDLED_EXCEPTION: $_" 'PROGRESS'
	} else {
		throw; #Re-execute a exception!
	}
} finally {
	if($ReturnExitCode){
		exit($ExitCode)
	}
	
	pop-location;
}