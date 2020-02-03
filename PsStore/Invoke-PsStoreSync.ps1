[CmdLetBinding()]
param(
    $LocalFolder = $null
	,$RemoteFolders = $null
	,[switch]$NoSubDirectories = $false
	,[switch]$NoPropagateExistents = $false
	,$ExistentWriteTime = $null
	,$LogTo = $null
	,$FilesFilter = "*.*"
	,$ControlFile = "InvokePsStoreSync.control"
	,[switch]$IngoreDirectory = $false
)
	
	
$ErrorActionPreference = "Stop"

try {
	$pushed = $false;
	$FSFILTERS  = "LastWrite","FileName","DirectoryName"
	$FSEVENTS = "Changed", "Renamed", "Deleted", "Created"
	$StartDate = Get-Date
	#Get current script
	$CurrentLocation  = Split-Path -Parent $MyInvocation.MyCommand.Definition ;


	Function Script:Right($str,$qtd = 1){
		return $str.substring($str.length - $qtd, $qtd)
	}

	Function Script:PutFolderSlash($folder, [switch]$Slash = $false ){
		$slashToUse = '\'
		$slashToReplace = '/'
		if($Slash){
			$slashToUse = '/'
			$slashToReplace = '\'
		}
		
        write-verbose "Current folder: $folder"
		$folder = $folder.replace($slashToReplace,$slashToUse)

		if( (Script:Right($folder)) -ne $slashToUse ){
			$folder += $slashToUse
		}

		return $folder
	}
	
	#Transform $LogTo in hashtable in order to allow modification values...
	$LogTo2 = @()
	$LogTo | %{	
		$item = @{VALUE=$_}
		$LogTo2 += $item;
	}
	
	Function Script:Log {
		# OutputPacket: message, ts, level
		[CmdLetBinding()]
		param(
			$message
		)

		$Logto = $Script:LogTo;
		$StartTS = $Script:StartDate;
		
		if($LogPacket.ts){$ts = $LogPacket.ts} else {$ts = Get-Date}
		$tsString = $ts.toString("yyyy-MM-dd HH:mm:ss")
		$fullLogMessage = "$tsString $message"
		
		write-verbose $fullLogMessage
		write-verbose "Sending messages to destinations"
		foreach($dest in $LogTo2) {
			write-verbose "User destination choosed is: $dest"
			$finalDest = $dest.VALUE;
			$clean = $false;
			
			if($finalDest.StartsWith("CLEAN:")){
				$dest.VALUE =  $finalDest.replace("CLEAN:","")
				$finalDest = $dest.VALUE
				$clean = $true;
			}
			
			if($finalDest -eq "SCREEN"){
				write-host $fullLogMessage
				break;
			}
			
			if(!(Test-Path $finalDest)){
				New-Item -Type File $finalDest | Out-Null
			}
			
			if( (gi $finalDest).PSIsContainer ){
				if($StartTs){
					$fileTS = $StartTs.toString("yyyyMMdd-HH\Hmm\m\i\nss\s")
				}
				$finalDest = $finalDest+"\InvokePsSync_$fileTS.log"
			}
			
			write-verbose "	Final destination is: $finalDest"
			
			if($clean){
				New-Item -Type file $finalDest -Force | Out-Null
				$clean = $false;
			}
			
			$fullLogMessage >> $finalDest
		}
	}
	
	Function Script:HandleErrors {
		param($ex)
		$errorLine = $ex.InvocationInfo.ScriptLineNumber
		$errorColumn = $ex.InvocationInfo.OffsetInLine
		$errorLine = $ex.InvocationInfo.ScriptLineNumber
		$message = "SCRIPT ERROR (L $errorLine C $errorColumn): `r`n:"+$_
		Log $message
	}

	#This functions is responsible by generating control points for script sync.
	$ControlLastTime = $null;
	Function RegisterControl {
		param($string = "PSSTORESYNC_CHECKPOINT")
		
		if(!$Script:ControlFile){
			return;
		}
		
		if(!$Script:ControlLastTime){
			if(Test-Path $Script:ControlFile){
				Script:Log " Control exists!!!!"
				$FileInfo = gi $Script:ControlFile
				$Script:ControlLastTime = $FileInfo.LastWriteTime; 
			} else {
				Script:Log " Control file dont found. Control Last Time will be 0."
				$Script:ControlLastTime = [datetime]0;
			}
		}
	
		$string > $Script:ControlFile
	}
	
	Function GetBaseExistentTime {
	
		if($Script:ExistentWriteTime){
			Script:Log " Base time comes from user parameter!"
			return $Script:ExistentWriteTime;
		} else {
			Script:Log " Base time comes from control last time!"
			return $Script:ControlLastTime
		}
	}
	
	. {
		Script:Log "--------- EXECUTION_INIT_MARK ---------"
		Script:Log " Control file is: $ControlFile"
		Script:RegisterControl "SCRIPT_INIT"
		
		$Cleanup = {
			Script:Log "Removing extra events..."
			$removedCount = 0;
			Get-Event | %{
				$removedCount++;
				Remove-Event -EventIdentifier $_.EventIdentifier
			}
			Script:Log "	Removed: $removedCount"
			
			Get-EventSubscriber | %{
				Script:Log "Unregistering event $($_.EventName)"
				UnRegister-Event -SubscriptionId $_.SubscriptionId -Force | Out-Null
			}
		}

		try {

			Script:Log "Executing pre-cleanup"
			. $Cleanup
			
			#Performing initial validations...
				if($LocalFolder -eq $null){
					$LocalFolder = $CurrentLocation
				}
				$LocalFolder = (Script:PutFolderSlash $LocalFolder)
				
				Script:Log "Local Folder is: $LocalFolder"
				
				
				if( ![System.IO.Directory]::Exists($LocalFolder) ){
					Script:Log "Local directory not exists. creating it."
					mkdir $LocalFolder | Out-Null
				}
				
				
				$RemoteWithError = @();
				Script:Log "Remote Folders: "
				$RemoteFolders  | %{
					$CurrentRemote = $_;
					try {
						if( ![System.IO.Directory]::Exists($CurrentRemote) ){
							Script:Log "Remote folder $CurrentRemote dont exist. creating it."
							mkdir $CurrentRemote | Out-Null
						}
						
						Script:Log "	$CurrentRemote"
					} catch {
						$RemoteWithError += $CurrentRemote;
						Script:Log "	Error: $($_.Exception.GetBaseException().Message)"
					}
				}
				
				$RemoteFolders = $RemoteFolders | where { -not($RemoteWithError  -Contains ($_)) }
			
				if(@($RemoteFolders).qtd -eq 0){
					throw "NO_REMOTE_FOLDER_VALID"
				}

			#Configuring File Watcher
				$LocalWatcher = New-Object "System.IO.FileSystemWatcher"
				$LocalWatcher.path = $LocalFolder
				$LocalWatcher.filter = $FilesFilter
				
				$Filters = 0;
				$FSFILTERS | %{$Filters = $Filters -bor ([System.IO.NotifyFilters]$_)};
				
				$LocalWatcher.NotifyFilter = $Filters
				
				if($NoSubDirectories){
					$LocalWatcher.IncludeSubdirectories = $false
				} else {
					$LocalWatcher.IncludeSubdirectories = $true
				}
				
				Script:Log "Registering events handlers..."
				$FSEVENTS | %{
					Script:Log "Registering event $_"
					Register-ObjectEvent $LocalWatcher -EventName $_
				}
				
				Script:Log "Enabling raising..."
				$LocalWatcher.EnableRaisingEvents = $true;
			
			
			#Forcing existents...
				if(!$NoPropagateExistents){
						Script:Log "Propagating existent files"
						$BaseExistent = GetBaseExistentTime;
						
						Script:Log "	Base Time is: $BaseExistent"
						
						$scriptFilter = {$_.LastWriteTime -ge $BaseExistent}
						
						#Include files is better than Path * filter because \* filter on path include subdirectories. The include stay filtering based on our filtering wildcards...
						#normal ways will exclude sub-dirs...
						$ElegibleFiles = gci -recurse "$LocalFolder\*" -Include $FilesFilter | where $scriptFilter | %{
							Script:Log "	Adding event for file: $($_.FullName)"
							
							$fsArgs = New-Object "System.IO.FileSystemEventArgs"("Created",(Split-Path -Parent $_.FullName),$_.Name)
							New-Event -SourceIdentifier "EXISTENT_PROPAGATING" -Sender $LocalWatcher -EventArguments $fsArgs | Out-null
						}
				}
			
			#Beging processing events...
				Script:Log "Starting handling events on: $($LocalWatcher.path)"
				while($ev = Wait-Event){
					Script:RegisterControl "EVENTS_HAPPENS"
					
					try {
						$eventArgs= $ev.SourceEventArgs;
						$argClass = $eventArgs.GetType().Name;

						$targo	= New-Object PSObject -prop @{path=$null;action=$null;oldPath=$null}
						$targo.path = $eventArgs.FullPath;
						
						
						if($argClass -eq "FileSystemEventArgs"){
							$targo.action = $eventArgs.ChangeType;
						}
						
						if($argClass -eq "RenamedEventArgs"){
							$targo.action = "Renamed"
							$targo.oldPath = $eventArgs.oldFullPath;
						}
						
						Script:Log "Event! [$($targo.action)] $($targo.path) ($($targo.oldPath)) "
						
						#Remove local folder from path thus we can understand necessary remote structure.
						$relativePath = $targo.path.replace($LocalFolder,"");
						Script:Log "Relative path is: $relativePath"
						
						if($targo.oldPath){
							$oldRelativePath = $targo.oldPath.replace($LocalFolder,"");
							Script:Log "Old Relative path is: $oldRelativePath"
						}
						
							
						#Determining mirror action...
						$mirrorCommand = {
							Script:log "NO ACTION!"
						}
						
						if( $targo.action -eq "Changed" -or $targo.action -eq "Created" ){
							$mirrorCommand = {
								param($d,$dFolder = $null)  
								Script:log "	Copying: $($Script:targo.path) $d"
								copy -force -recurse $Script:targo.path $d 
							};
						}
						
						if( $targo.action -eq "Deleted"){
							$mirrorCommand = {
								param($d,$dFolder = $null)  
								Script:log "Deleting: $d"
								del -force -recurse  $d
							};
						}
						
						if( $targo.action -eq "Renamed"){
							$mirrorCommand = {
								param($d,$dFolder)  
								$remoteOldPath = $dFolder+$script:oldRelativePath
								try {
									Script:log "Deleting old path: $remoteOldPath..."
									del -force -recurse  $remoteOldPath
								} finally {
									Script:log "Copy new file: $($Script:targo.path) -> $d"
									copy -force -recurse $Script:targo.path $d 
								}
							};
						}
						
						$CheckAtDestination  = $false; #TODO...
						$isDir = $false;
						if(Test-Path $targo.path) {
							$attrs = [System.IO.File]::GetAttributes($targo.path);
							$dirattr = [System.IO.FileAttributes]::Directory
							$isDir = (($attrs -band $dirattr) -eq $dirattr) -as [bool]
							$CheckAtDestination = $false;
						} else {
							$CheckAtDestination = $true;
						}

						if($isDir -and $IngoreDirectory){
							Script:Log "Affected file is a directory. Skipping..."
							continue;
						}

						Script:Log "Mirroring file"
						$RemoteFolders | %{
							$destinationFolder = (Script:PutFolderSlash $_)
							Script:Log "Destination is $destinationFolder"
							
							try {
								$destinationPath = ("$destinationFolder"+"$relativePath")
								Script:Log "Destination path is: $destinationPath"
								
								$DestinationParentDir = [System.IO.Path]::GetDirectoryName($destinationPath);
								Script:Log "	Forcing destination DIRECTORY STRUCTURE: $DestinationParentDir"

								New-Item -ItemType Directory -Path ( $DestinationParentDir ) -Force | Out-null
								
								if($CheckAtDestination){
									Script:Log "	----> Checking if file is directory at destination..."
									$attrs = [System.IO.File]::GetAttributes($destinationPath);
									$dirattr = [System.IO.FileAttributes]::Directory
									$isDir = (($attrs -band $dirattr) -eq $dirattr) -as [bool]
									$CheckAtDestination = $true;
									if($isDir -and $IngoreDirectory){
										Script:Log "Affected file AT DESTINATION is a directory. Skipping..."
										continue;
									}
								}
								
								if($isDir -and $targo.action -eq "Changed"){
									Script:Log "Ignoring the Changed action in a Dir..."
									continue;
								}
								
								& $mirrorCommand $destinationPath $destinationFolder
							} catch {
								Script:Log "	Error: $($_.Exception.GetBaseException().Message)"
							}
						}
						
					} catch{
						Script:HandleErrors $_
					}finally {
					
						Script:Log "	Dequeing"
						Remove-Event -EventIdentifier $ev.EventIdentifier
					}
					
				}		
			

		} finally {
			. $Cleanup

			if($LocalWatcher){
				$LocalWatcher.EnableRaisingEvents = $false;
				$LocalWatcher = $null;
			}

			if($pushed){pop-location}
		}
		

	} 2>&1 | %{ #This part redirect all errors to std input to redirect all to custom log script. This log will send to correct output
		Log $_
	}
} catch {
	Script:HandleErrors $_
	throw
}

#FromPSStore
#FromPSStore
#FromPSStore
