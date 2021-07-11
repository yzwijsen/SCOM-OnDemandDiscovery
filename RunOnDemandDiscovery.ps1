#import scom module
Import-Module OperationsManager

# Load SCOM powershell module
$checksnap = Get-Module | Where-Object {$_.name -eq "OperationsManager"}
if ($checksnap.name -ne "OperationsManager")
    {
        Import-Module -name "C:\Program Files\Microsoft System Center 2016\Operations Manager\Powershell\OperationsManager"
    }
	
function Exit-WithMessage($message)
{
	Write-Host $message -BackgroundColor Black -ForegroundColor Red
	Read-Host -Prompt "Exiting, press enter to close window!"
	Exit
}
	
#Get Task Reference
Write-Host "Getting TriggerOndDemandDiscovery Task Reference..." -ForegroundColor Yellow
$task = get-scomtask -name Microsoft.SystemCenter.TriggerOnDemandDiscovery

#Exit if task is not found
if ($task -eq $null)
{
	Exit-WithMessage "Task Not Found!"
}
#Load SCOM Discoveries and allow user to select one
Write-Host "Loading SCOM Discoveries..." -ForegroundColor Yellow
$discovery = Get-SCOMDiscovery | Select-Object -Property DisplayName,Description,Id | Out-GridView -PassThru -Title "Select Discovery" | Select-Object -First 1 | ForEach-Object {Get-SCOMDiscovery -Id $_.Id}

#Check if discovery is selected
if ($discovery -ne $null)
{
	Write-Host "Selected: $($discovery.DisplayName)"
}
else
{
	Exit-WithMessage "No Discovery Selected!"
}

#Load HealthService instances and let user select which ones to target
Write-Host "Loading Agents..." -ForegroundColor Yellow
$instanceAgents = get-scomclass -name Microsoft.SystemCenter.HealthService | get-scomclassinstance | Out-GridView -PassThru -Title "Select Target Agent(s)"

#Check if at least one agent is selected
if ($instanceAgents -ne $null)
{
	$agentCount = $instanceAgents.Count
	Write-Host "Selected $agentCount agents:"
	foreach ($agent in $instanceAgents)
	{
		Write-Host $agent.DisplayName
	}
}
else
{
	Exit-WithMessage "No Agent Selected!"
}

#Load all the target instances
Write-Host "Getting Target Class Instances..." -ForegroundColor Yellow
$classInstances = Get-SCOMClass -Id $discovery.Target.Id | Get-SCOMClassInstance

$failedDiscoveries = @()

#Loop through all selected agents and generate a task for each one
Write-Host "Creating Tasks..." -ForegroundColor Yellow
$i = 1
foreach ($instanceAgent in $instanceAgents)
{
	Write-Host "##########################################################"
	Write-Host "Agent: $($instanceAgent.DisplayName)  ($i of $agentCount)"
	Write-Host "Gathering Additional Data..." -ForegroundColor Yellow
		
	#match target class isntance to agent selected by user
	$instance = $classInstances | Where-Object {$_.Path -match $instanceAgent.DisplayName}
	
	#Check if instance is found
	if ($instance -eq $null)
	{
		Write-Host "Target Instance Not Found!" -ForegroundColor Red
		continue
	}
	
	#Set override data
	$override = @{DiscoveryId=$discovery.id.tostring();TargetInstanceId=$instance.id.tostring()}
	
	#Start Task
	Write-Host "Starting Task..." -ForegroundColor Yellow
	$taskInstance = start-scomtask -task $task -instance $instanceAgent -override $override

	write-host  "task status:" (get-SCOMTaskResult -BatchID $taskInstance.BatchId | select -ExpandProperty Status)

	#Wait for task to complete
	$j = 1
	while ((get-SCOMTaskResult -BatchID $taskInstance.BatchId | select -ExpandProperty Status) -ne "Succeeded")
	{
	    write-Host "Waiting..." -ForegroundColor Yellow
		$taskStatus = (get-SCOMTaskResult -BatchID $taskInstance.BatchId | select -ExpandProperty Status)
		write-host  "task status: $taskStatus" 
		if ($taskStatus -eq "Failed" -or $j -gt 10) {Break}
	    $j++
		Sleep -Seconds 2
		
	}
	
	Write-Host "task status: Completed"
	
	#Show task output
	Write-Host "Checking task output..." -ForegroundColor Yellow
	$result = ""
	$result = get-SCOMTaskResult -BatchID $taskInstance.BatchId | Select-Object -ExpandProperty Output
	if ($result -like "*<Result>SUCCESS</Result>*")
	{
		Write-Host "Discovery triggered successfully" -ForegroundColor Green
	}
	else
	{
		Write-Host "Discovery failed to trigger" -ForegroundColor Red
		Write-Host "Output: $result"
		$failedDiscoveries += $instanceAgent
	}
	
	$i++
	Start-Sleep 2
}

Write-Host "Done!" -ForegroundColor Green
$failedCount = 0                                     
$failedCount = $failedDiscoveries.Count

if ($failedCount -ne 0)
{
	Write-Host "$failedCount failed discoveries!" -ForegroundColor Red
	foreach ($failedDiscovery in $failedDiscoveries)
	{
		Write-Host $failedDiscovery.DisplayName
	}
}

Read-Host "Press Enter to Exit"
