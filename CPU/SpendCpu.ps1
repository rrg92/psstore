param($time, $interval = 1000, [switch]$continuous = $false, $Cpu = $null, $delaycontinous = 0)

$ErrorActionPreference = "Stop";

$Kernel32Def = @"
[DllImport("kernel32.dll", SetLastError=true)]
public static extern bool GetThreadTimes(IntPtr hThread, out long lpCreationTime,out long lpExitTime, out long lpKernelTime, out long lpUserTime);

[DllImport("kernel32.dll")]
public static extern IntPtr GetCurrentThread();

[DllImport("kernel32.dll")]
public static extern UIntPtr SetThreadAffinityMask(IntPtr hThread,UIntPtr dwThreadAffinityMask);

[DllImport("kernel32.dll")]
public static extern bool SetThreadPriority(IntPtr hThread, int Priority);

[DllImport("kernel32.dll", CharSet=CharSet.Auto, SetLastError=true)]
public static extern bool SetPriorityClass(IntPtr handle, uint priorityClass);

[DllImport("kernel32.dll", SetLastError = true)]
public static extern IntPtr GetCurrentProcess();
"@


$TH_PRIORI = @{
    THREAD_MODE_BACKGROUND_BEGIN = 0x00010000
    THREAD_MODE_BACKGROUND_END = 0x00020000
    THREAD_PRIORITY_ABOVE_NORMAL = 1
    THREAD_PRIORITY_BELOW_NORMAL = -1
    THREAD_PRIORITY_HIGHEST = 2
    THREAD_PRIORITY_IDLE = -15
    THREAD_PRIORITY_LOWEST = -2
    THREAD_PRIORITY_NORMAL = 0
    THREAD_PRIORITY_TIME_CRITICAL = 15
}

$PR_CLASS = @{
   ABOVE_NORMAL_PRIORITY_CLASS = 0x8000
   BELOW_NORMAL_PRIORITY_CLASS = 0x4000
   HIGH_PRIORITY_CLASS = 0x80
   IDLE_PRIORITY_CLASS = 0x40
   NORMAL_PRIORITY_CLASS = 0x20
   PROCESS_MODE_BACKGROUND_BEGIN = 0x100000
   PROCESS_MODE_BACKGROUND_END = 0x200000
   REALTIME_PRIORITY_CLASS = 0x100
}


$Kernel32 			= Add-Type -MemberDefinition $Kernel32Def -Name 'Kernel32' -Namespace 'Win32' -PassThru 

write-host "booting priority of process"
$ThisProc = [long]$Kernel32::GetCurrentProcess()
$Kernel32::SetPriorityClass( $ThisProc , $PR_CLASS.HIGH_PRIORITY_CLASS );

write-host "booting priority of thread"
$ThisTh = [long]$Kernel32::GetCurrentThread()
$Kernel32::SetThreadPriority( $ThisTh , $TH_PRIORI.THREAD_PRIORITY_HIGHEST);

function GetMyCpuTime(
		[switch]$ms
	){
	$c = [long]$Kernel32::GetCurrentThread()
	[long]$ct = $null; 
	[long]$kt = $null; 
	[long]$ut = $null;
	$t = $Kernel32::GetThreadTimes($c, [ref]$ct, [ref]$ct, [ref] $kt, [ref] $ut);
	$v=  $kt + $ut
	
	if($ms){
		$v *= 0.0001
	}
	
	return $v;
}


function SetCpuMask {

	if($Cpu -eq $null){
		return;
	}
	
	[uint32]$IntMask = [uint32]0;
	
	
	if($Cpu -is [int] -or $Cpu -is [object[]]){
		
		$Cpu | %{
			$IntNum = [int]$_;
		
			$IntMask  = $IntMask  -bor (1 -shl $IntNum)
		}
	}	
	
	elseif ($FinalMask -match '^[01]$') {
		$IntMask = [convert]::ToInt32($FinalMask,2);;
	} else {
		throw "invalid cpu specification. Valid:  Cpu number array (ex.: 1,2,3 for cpu 1,2 and 3 or cpu mask BIT (ex.: 0000111)";
	}
	
	

	$ct = [long]$Kernel32::GetCurrentThread()
	$MaskString = [convert]::ToString($IntMask, 2);
	write-host "Setting affinty to $MaskString ($IntMask)";
	
	$r = $Kernel32::SetThreadAffinityMask( $ct, $IntMask);
	write-host '... OK!'
}



if(!$time){
	throw "INVALID_TIME"
}

if($time -gt $interval){
	throw "TIME_LE_INTERVAL: $time < $interval"
}


SetCpuMask;

$SleepTime = $interval - $time;

do {
	$i = 0;
	$StartCPU = GetMyCpuTime -ms
	do {	
		$TotalCpu 	= GetMyCpuTime -ms
		$Diff		= $TotalCpu - $StartCPU;
	}while($Diff -lt $time)
	Start-Sleep -m $SleepTime
	
	if($delaycontinous){
		write-host "Delaying next spend by $delaycontinous ms";
		start-sleep -m $delaycontinous;
	}
	
} while($continuous);




