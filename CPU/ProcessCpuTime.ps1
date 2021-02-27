param(
	$speed = 1000
	,$filtercol = 'cpu'
	,$historycol = 'cpu'
)

$ErrorActionPreference = "Stop";
[int]$TotalCpu = 0;

Get-WmiObject Win32_Processor | %{
	$TotalCpu += [int]$_.NumberOfLogicalProcessors
}

$Totals = New-Object PsObject -Prop @{
					cpu 	= 0
					cpuk	= 0
					icpu	= 0
					icpuk	= 0
					et 		= 0
				}
				
function StringRight($string, $num){
	$string.substring($string.length - $num, $num);
}			

function Plot($set,$MaxY = 10,$MaxValue = 100,$PreFixScale = 10){
	

	[int]$YZeroSlot 	= $MaxY;
	$ArraySize = $MaxY + 1;
	$LineArray 	= @('') * $ArraySize;

	$MaxPositive = $MaxValue;
	$MaxNegative = 0;
	
	#$set = $set | %{  if($_ -gt $MaxValue){$MaxValue}else{$_} };
		
	#$positives = $set | ? { $_ -gt 0;  if($_ -gt $MaxPositive){$MaxPositive = $_ };  };
	#$negatives = $set | ? { $_ -lt 0 } | %{ $n = -1 * $_; $n; if($n -gt $MaxNegative){$MaxNegative = $_ }; };
	

	$MaxDigits = ($LineArray.length*$PreFixScale).toString().length;
	
	0..($LineArray.length-1) | %{
		$ArrayPosition = $_;
		
		$Prefix = StringRight ((' '*$MaxDigits) + ($ArrayPosition*$PreFixScale)) $MaxDigits;
		
		$LineArray[$ArrayPosition] = $Prefix+'- ';
	}
	
	$set | %{
		$y = [int]$_;
		
		if($y -gt $MaxValue){
			$y = $MaxValue;
			$PointChar = '+'
		} else {
			$PointChar = '.'
		}
		
		[int]$slot  = ($y * $MaxY)/$MaxPositive
		
		0..($LineArray.length-1) | %{
			$ArrayPosition = $_;
			
			if($slot -eq $ArrayPosition){
				$c = $PointChar
			}
			elseif( $ArrayPosition -eq 0 ){
				$c = '_'
			}
			else {
				$c = ' '
			}
			
			
			$LineArray[$ArrayPosition] += $c;
		}
	}	
	

	
	[array]::reverse($LineArray);
	return ($LineArray|out-string);
	
}


$History = @();


do {
	$Atual = Get-Process;
	$DataColeta = Get-Date;	
	$Report = @();

	$Totals.cpu 	= 0;
	$Totals.cpuk 	= 0;
	$Totals.icpu 	= 0;
	$Totals.icpuk 	= 0;
	$Totals.et 		= 0
	

	if($Anterior){
		$Decorrido = (Get-Date) - $UltimaColeta
		$TempoDecorrido = $Decorrido.TotalMilliseconds;
		$Totals.et = $TempoDecorrido;


		$Atual | %{
			$PidAtual = $_.ID;
			$CPUAtual = $_.TotalProcessorTime.TotalMilliseconds
			$KernelAtual = $_.PrivilegedProcessorTime.TotalMilliseconds

			$CPUAnterior = $Anterior[$PidAtual].TotalTime.TotalMilliseconds
			$KernelAnterior = $Anterior[$PidAtual].KernelTime.TotalMilliseconds
			
			if($CPUAnterior){
				$CpuDiff		= $CpuAtual - $CPUAnterior;
				$KernelDiff		= $KernelAtual - $KernelAnterior;
				
				$GastoCPU 		= ($CpuAtual-$CPUAnterior)/$TempoDecorrido
				$GastoKernel 	= ($KernelAtual-$KernelAnterior)/$TempoDecorrido
				
				$o = New-Object PsObject -Prop @{
						name 	= $_.name
						
						#percentuais de todas
						cpu		= 0			#gasto total de cpu (baseado no total da maquina)
						cpuk	= 0			#igual cpu, pra kernel
						
						#percentuais do intervalo
						icpu	= 0			#percentual gasto de cpu no intervalo.
						icpuk	= 0			#mesmo mscpuk , porém pra kernel
						
						#diferenca simples
						dcpu	= 0			#diff simples de tempo (anterior - anterior)
						dcpuk	= 0	
						kt		= 0
					}
					
				
					
				$Report += $o;
				
				if($CpuDiff -gt 0){
					$o.cpu 	= [math]::round( ($GastoCPU*100)/$TotalCpu, 2);
					$o.icpu 	= [math]::round($GastoCPU,2) * 100
					$o.dcpu 	= [math]::round($CpuDiff,2)
					$Totals.cpu 	+= $o.cpu;
					$Totals.icpu 	+= $o.icpu;
				}
				
				if($KernelDiff -gt 0){
					$o.cpuk 	= [math]::round( ($GastoKernel*100)/$TotalCpu, 2);
					$o.icpuk 	= [math]::round($GastoKernel,2) * 100
					$o.kt 		= $KernelAtual
					$o.dcpuk 	= [math]::round($KernelDiff,2)
					$Totals.cpuk += $o.cpuk;
					$Totals.icpuk += $o.icpuk;
				}
				
				
			
			}
		}
	
	}	

	$Anterior = @{}
	$Atual | %{
		$Anterior[$_.ID] = @{
				TotalTime 	= $_.TotalProcessorTime
				KernelTime	= $_.PrivilegedProcessorTime
			}
	}
	
	$LastHistory = 50;
	$history += @([int]$Totals.$historycol)
	$history = @($history | select -last $LastHistory | %{$_});
	
	clear-host;
	write-host ($Report | select name,cpu,cpuk,icpu,icpuk,dcpu,dcpuk,kt | ? { $_.$filtercol -gt 0 } | sort $filtercol -desc| ft |out-string)
	
	write-host "Totals:"
	write-host ($Totals | select cpu,cpuk,icpu,icpuk,et | ft | out-string)
	

	write-host "history:"
	write-host $history
	write-host (Plot $history);
	
	
	$UltimaColeta	= $DataColeta;	
	Start-Sleep -m $speed;
} while($true)