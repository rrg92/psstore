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
)

$ErrorActionPreference = "Stop";

#função auxilia
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
	#importando o modulo CustomMSSQL!
	#If there are a local folder with customMSSQL, imports from it!
	
	$CustomMSSQLPath = "CustomMSSQL"
	if( Test-Path ".\CustomMSSQL" ){
		$CustomMSSQLPath = ".\CustomMSSQL"
	}
	
	try {
		import-module $CustomMSSQLPath -force;
	} catch {
		write-host "Import CustomMSSQL failed: $_";
		throw;
	}
	

	#Obtendo a data atual. Esta vai ser a data desta sessão de backup!
	$SessionStartTime = (Get-Date)
	
	#Validando parâmetros!
		if(!$DestinoBackup){
			$DestinoBackup	= '';
		}
		
		if( "DIFF","FULL","LOG" -NotContains $BackupType ){
			throw "TIPO_BACKUP_INVALIDO: $BackupType";
		}
		
		#If servername like *\MSSQLSERVER, then remove \MSSQLSERVER part...
		if($ServerInstance -like '*\MSSQLSERVER'){
			$ServerInstance = $ServerInstance.replace('\MSSQLSERVER','');
		}

	#Construindo o mecanismo de log, usando as facilidades de log fornecidas pelo módulo CustomMSSQL
	$L = (New-LogObject)
	$L.LogTo = @("#"); #Por padrão, log na tela (# - significa usar write-host)
	$L.LogLevel = "DETAILED"; 
	$L.ignoreLogFail = $false

	$StartMsg = "Iniciando script! SessionStartTime: $SessionStartTime. Usuário: $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name) Computador: $($Env:ComputerName)";
	$L | Invoke-Log 'Inicializando log!' 'PROGRESS'

		#Montando o diretório de log!
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
		
		$L | Invoke-Log "Arquivo de Log será: $LogFile" 'PROGRESS'


		if(-not(Test-Path $FullLogdir)){
			try{
				$dir = mkdir $FullLogdir -force
			} catch {
				$L | Invoke-Log "FALHA_CRIACAO_DIRETORIOLOG: $_" 'PROGRESS'
			}
		}

		$L.LogTo += $LogFile;
		$L | Invoke-Log "Inicializando arquivo de log. $StartMsg" 'PROGRESS'
		
		$L | Invoke-Log "Checando instância $ServerInstance..." "PROGRESS"
		
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
		
		$L | Invoke-Log "Obtendo as bases..." 'PROGRESS'
		try {

            if($FiltroEx){
                $SQLFilterEx = @(
                    "IF OBJECT_ID('tempdb..#FilterEx') IS NOT NULL DROP TABLE #FilterEx;"
                    "CREATE TABLE #FilterEx (Filter nvarchar(max))";
                     "IF OBJECT_ID('tempdb..#FilterExNot') IS NOT NULL DROP TABLE #FilterExNot;"
                      "CREATE TABLE #FilterExNot (Filter nvarchar(max))";
                )

                $SQLFilterEx += $FiltroEx | %{  
                    
                    #Se o filtro começar com ! (negação). Marca como not....

                    if($_ -like "-*"){
                       $FilterExpr = $_ -replace "^-","";
                       "INSERT INTO #FilterExNot VALUES('$FilterExpr')" ;
                    } else {
                        "INSERT INTO #FilterEx VALUES('$_')";
                    }

                    
                };

                

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
				$ListaBasesFiltro = @($Filtro | %{"'$_'"}) -join ","
				$QueryListaBases = "SELECT name,recovery_model_desc,D.is_read_only FROM sys.databases D WHERE d.name NOT IN ('tempdb') AND D.name in ($ListaBasesFiltro)"
			} else {
				$QueryListaBases = "SELECT name,recovery_model_desc,D.is_read_only FROM sys.databases D WHERE d.name NOT IN ('tempdb')"
			}
			
			if($CustomQuery){
				$QueryListaBases = $CustomQuery;
			}

			$L | Invoke-Log "	Query com lista de bases: $QueryListaBases" 'PROGRESS'
			$Bases = @(Invoke-NewQuery -ServerInstance  $ServerInstance -Query $QueryListaBases)
		} catch {
			$SQLError = FormatSQLErrors -Exception $_.Exception;
			throw "FALHA_OBTER_BASES: $SQLError";
		}
		
		#Contém todos os testes que deverão ser feitos para verificar se o backup é suportado ou não!
		#Cada teste é uma entrada na hashtable abaixo. Cada valor é um script que será executado e deve retornar falso.
		#Se o script retorna verdadeiro, então o backup não poderá ser feito.
		#O script será executado no escopo do loop de bases, portanto as variáveis podem ser usadas!
		$TESTES = @{
		
			#Verifica se o backup é diferencial e a base é a master
			MASTER_DIFF = {
							return $base.Name -eq 'master' -and $BackupType -eq "DIFF";
						}
						
			#Verifica se a base é a tempdb
			TEMPDB = {
						return $base.Name -eq 'tempdb';
					}
			
			#Verifica se está tentando fazer backup de log de uma base SIMPLE!
			LOG_ON_SIMPLE = {
						return $base.recovery_model_desc -eq "SIMPLE" -and $BackupType -eq "LOG"
					}
					
			#READONLY Database on LOG backups (This generate copy only backups)
			LOG_ON_READONLY = {
			
						$IsLogReadOnly = $BackupType -eq "LOG" -and $base.is_read_only;
						
						
						if($IsLogReadOnly -and $ForceReadOnlyLog){
							$L | Invoke-Log "	Log backup under read_only will be taken due to ForceReadOnly" 'PROGRESS'
							return $false;
						} else {
							return $IsLogReadOnly;
						}

				}
			
		}
					
		
		$HouveFalhasBackup = $false;
		if($Bases){
			
			$DatabaseSummary = @();

			
			$L | Invoke-Log "Iterando sobre a lista de bases: $($Bases.count)" 'PROGRESS'
			
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
			
			
			:LoopBases foreach($base in $Bases){
				$L | Invoke-Log "	Base $($base.Name)" 'PROGRESS'
				
				$Summary = New-Object PsObject;
				$Summary | Add-Member -Type Noteproperty -Name "DatabaseName" -Value $base.Name
				$Summary | Add-Member -Type Noteproperty -Name "Status" -Value $null
				$Summary | Add-Member -Type Noteproperty -Name "Error" -Value $null
				$DatabaseSummary += $Summary;
				
				
				$Suportado = $true;
				$FailedTests = @();
				
				
				#Realiza os testes na base para saber se é o backup é suportado!
				$L | Invoke-Log "		Verificando se o backup é suportado!" 'PROGRESS'
				:LoopTestes foreach($Teste in $TESTES.GetEnumerator()) {
					$NomeTeste 	= $Teste.Key;
					$Script		= $Teste.Value;
					
					$ResultadoTeste = . $Script;
					if($ResultadoTeste){
						$FailedTests += $NomeTeste;
						$L | Invoke-Log "			Não passou no teste $NomeTeste" 'PROGRESS';
						$Suportado = $false;
					}
					
				}

				if(!$suportado){
					$L | Invoke-Log "			Ignorando backup $BackupType da base $($base.Name). Verifique os testes anteriores para entender o motivo." 'PROGRESS'
					$Summary.Status = "Ignored"
					$Summary.Error = $FailedTests -Join ","
					continue :LoopBases;
				} else {
					$L | Invoke-Log "			SUCESSO!" 'PROGRESS'
				}
				
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
				
				
				#Building the target filepath.
				$TSQLDestinationFile = $ExprRegex.Replace($Destination, $ExprRegexEval );
				if($DestinationDir){
					$TSQLDestinationFile = "$DestinationDir\$TSQLDestinationFile";
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
								$L | Invoke-Log "		FALHA AO EXECUTAR BACKUP: Cannot create the parent directory $Parents. Error: $_" 'PROGRESS';
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
				$WithOptions =  $WithOptions | select -unique
			
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
				$L | Invoke-Log "		Comando de backup: $($TSQLBackupBuild -join ' ')" 'PROGRESS';
				
                if($ShowOnly) {
                     $L | Invoke-Log "		ShowOnly ativado... Nada será executado!" 'PROGRESS';
                } else {
				    try {
                    
					    $L | Invoke-Log "		Executando backup..." 'PROGRESS';
					    $BackupStarTime = (Get-Date)
					    $BackupResult = Invoke-NewQuery -ServerInstance  $ServerInstance -Query $TSQLBackup 
					    $BackupEndTime = (Get-Date);
					    $TempoTotal = $BackupEndTime-$BackupStarTime
					    $L | Invoke-Log "		SUCESSO! Tempo Total: $TempoTotal. Arquivo: $TSQLDestinationFile" 'PROGRESS';
						$Summary.Status = "Sucess"
						$Summary.Error = "TotalTime: $TempoTotal"
				    } catch {
					    $SQLError = FormatSQLErrors -Exception $_.Exception;
					    $L | Invoke-Log "		FALHA AO EXECUTAR BACKUP: $SQLError" 'PROGRESS';
					    $HouveFalhasBackup = $true;
						$Summary.Status = "Fail"
						$Summary.Error  = "TSQLError: $SQLError";
					    continue :LoopBases;
				    }
                }
				
			}

		} else {
			$L | Invoke-Log "Nenhuma base para backup!" 'PROGRESS'
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
		$ExitCode = 1000 #Codigo 1000 pra cima contém falhas do comando do backup!
		throw "FALHAS_BACKUP: Houveram falhas no backup. Verifique por erros anteriores!"
	}

	$ExitCode = 0;
	$L | Invoke-Log "Script executado com sucesso!" 'PROGRESS'
} catch {
	$ExitCode = 1; #Erro genérico!
	if($ReturnExitCode){
		$L | Invoke-Log "ERRO NO SCRIPT: $_" 'PROGRESS'
	} else {
		throw; #Re-execute a exception!
	}
} finally {
	if($ReturnExitCode){
		exit($ExitCode)
	}
	
	pop-location;
}