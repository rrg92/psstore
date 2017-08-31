<#
		.SYNOPSIS 
			Collects informations in windows event log! (beta!)
			
		.DESCRIPTION
			Runs the cmdlet Get-WinEvent and collect information about specific events.
			You can specify filters and format output.
			
			The -Verbose parameter can be used to see more information like filterexpression!
			
		.EXAMPLE
			.\Get-EventLogStats.ps1 -LogName System -ProviderName 'disk'
			
			Collects all events, severity 1 to 3, of "disk" provider in system log and groups by eventid!
			
		.EXAMPLE	
			.\Get-EventLogStats.ps1 -Force -StartTime '2017-03-08' -Endtime '2017-04-08'
			
			Collects 1 month of events, starting at March, 8 2017, of event levels 1 to 3.
			
		.EXAMPLE	
			.\Get-EventLogStats.ps1 -L System -Provider 'disk' -Grep
			
			Collects all events of providers matching "disk"  in the name, of severity 1 to 3.
		
		.NOTES
			Created by Rodrigo Ribeiro Gomes
			github.com/rrg92
			www.thesqltimes.com
#>

[CmdLetBinding(SupportsShouldProcess=$True)]
param(
	#Specify a array of providers names to filter.
	#If -SearchProviders and -SearchProvidersRegExp modify the behavior. Check help of them.
		[Alias('P','Providers','')]
		[string[]]$ProviderName = @()
	
	,#Maximum event to filter (passed to Get-WinEvent -MaxEvents paraemter!)
		[int]$MaxEvents = $null
		
	,#The logname passed to Get-WinEvent -LogName parameter.
		[Alias('L')]
		$LogName = 'Application'
		
	,#Array of levels must you want filter (Will be filtered on EventData/System/Level.
		$EventLevels = @(1,2,3)
		
	,#Datetime object with start time of filter.
	 #You can pass local time. The cmdlet will convert to UTC
	 #This value will be filtered in EventData/System/TimeCreated/@SystemTime (using >= operator),
		$StartTime  = $null
	,#Same as -StartTime, but will be used with <= operator 
		$EndTime	  = $null
		
	,#Dont groups results. Intead, return raw events (the result of Get-WinEvent).
		[switch]$RawEvents = $false
		
	,#When grouped, dont get first message of each group and add to each group object
		[switch]$NoMessage = $false
		
	,#Forces the cmdlet execute in situations where can exists many events.
	 #For example, filtering without specify a providername!
		[switch]$Force = $false
		
	,#Takes each value passed in -ProviderName parameter and make a search in provider list.
	 #The values will be passed to -like operator.
	 #Matched values are used as provider name.
	 #Verbose output will contains matched results.
		[Alias("S")]
		[switch]$SearchProviders = $false
	
	,#Same as -SearchProviders, but each value will be passed to -match operator, instead -like.
		[Alias("Grep")]
		[switch]$SearchProvidersRegExp = $false
		
	,#Force case sensitive operators
		[Alias("cs")]
		[switch]$CaseSensitive = $false
		
	,#Specify computers where to collect!
	 #Will be passed to -ComputerName of Get-WinEvent!
		[Alias("C")]
		$Computers = @()
)

$ErrorActionPreference = "Stop";

#Check if a given address is current computer!
Function IsLocalComputer {
	param($Address)
	
	$LocalAddresses = @(
		'.'
		'127.0.0.1'
		'localhost'
		(Get-WMIObject Win32_NetworkAdapterConfiguration | %{$_.IpAddress})
		$Env:ComputerName
	)
	
	$ComputerSystemInfo = Get-WmiObject Win32_ComputerSystem;
	
	if($ComputerSystemInfo.partofdomain){
		$FullComputerName = $ComputerSystemInfo.Name+'.'+$ComputerSystemInfo.Domain;
		$LocalAddresses += $ComputerSystemInfo.Name,$FullComputerName
	}
	
	return $LocalAddresses -Contains $Address;
}



$AllFilters = @()

$TimeFilter = @();
if($StartTime){
	$StartTimeFilter = ([datetime]$StartTime).ToUniversalTime().toString('o');
	$TimeFilter += "@SystemTime >= '$StartTimeFilter'"
}

if($EndTime){
	$EndTimeFilter = ([datetime]$EndTime).ToUniversalTime().toString('o');
	$TimeFilter += "@SystemTime <= '$EndTimeFilter'"
}

if($ProviderName){
	
	$Op = $null;
	if($SearchProvidersRegExp){
		$Op = 'match'
	} elseif($SearchProviders) {
		$Op = 'like'
	}
	
	if($Op){
		if($CaseSensitive){
			$op = "c$op";
		}
		
	
		write-verbose "Searching for provider names using $op";
		$ProviderFilterScript = [scriptblock]::create("`$CurrentProvider -$Op `$Filter");
		
		$EvtLogGlobal = [System.Diagnostics.Eventing.Reader.EventLogsession]::GlobalSession;
		$ProviderFilters = $ProviderName;
		$ProviderName = $EvtLogGlobal.GetProviderNames() | ? {
			$CurrentProvider = $_;
			$ProviderFilters | ? {
				$Filter = $_;
				. $ProviderFilterScript
			}
		}
		
		write-verbose "Providers filtered: $ProviderName";
		
		if(!$ProviderName){
			throw "NO_PROVIDER: Filter dont match any provider"
		}
	}


	$FilterProviders = @($ProviderName | %{"@Name = '$_'"}) -Join " or ";
	$AllFilters += "System[Provider[$FilterProviders]]"
} else {
	if(!$Force){
		write-error "NO_PROVIDER: USe -Force to query without a provider filer!"
	}
}

if($EventLevels){
	$FilterLevels = @($EventLevels | %{"Level = $_"}) -Join " or ";
	$AllFilters += "System[$FilterLevels]"
}

if($TimeFilter){
	$AllFilters += 'System[TimeCreated['+($TimeFilter -Join ' and ')+']]'
}

$FilterXPath = "*[ "+($AllFilters -Join " and ")+" ]";
write-verbose $FilterXPath

$WinEventParams = @{
	LogName 		= $LogName
	FilterXPath		= $FilterXPath
}

if($MaxEvents -gt 0){
	$WinEventParams.add("MaxEvents", $MaxEvents);
}

write-verbose "Get-WinEvent params:"
$WinEventParams.GetEnumerator() | %{
	write-verbose "$($_.Key): $($_.Value)"
}

if(!$Computers){
	$Computers = '.';
}

$LocalQueried = $false
$e = @();
$Computers | %{

	if(IsLocalComputer $_){
		if($LocalQueried){
			write-verbose "Local computer already queried!";
			return;
		} else {
			$LocalQueried = $true;
		}
		
		if($WinEventParams.Contains("ComputerName")){
			$WinEventParams.remove("ComputerName");
		}
		
		write-verbose "Querying local computer..."
	} else {
		write-verbose "Querying remote computer $_..."
		$WinEventParams["ComputerName"] = $_;
	}

	$e += @(Get-WinEvent @WinEventParams -EA "SilentlyContinue");
}


if($RawEvents){
	return $e;
} else {
	if($events){
		$events = $e;
	}

	$Groups = $e | Group-Object MachineName,ProviderName,Id
	
	if(!$NoMessage -and $Groups){
		$Groups | %{
			$FirstMessage = $_.Group[0].Message;
			$_  | Add-Member -Type Noteproperty -Name Msg -Value $FirstMessage -force;
		}
	}
	
	return $Groups | sort Count -Desc | select Count,Name,Msg | ft -AutoSize;
}


