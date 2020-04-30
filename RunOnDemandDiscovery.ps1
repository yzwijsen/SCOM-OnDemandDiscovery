#import scom module
Import-Module OperationsManager
	
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
$discovery = Get-SCOMDiscovery | Select-Object -Property DisplayName,Description,Id | Out-GridView -PassThru -Title "Select Discovery" | Select-Object -First 1 | Get-SCOMDiscovery -Id $_.Id

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
	Write-Host "Selected:"
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

#Loop through all selected agents and generate a task for each one
Write-Host "Creating Tasks..." -ForegroundColor Yellow	
foreach ($instanceAgent in $instanceAgents)
{
	Write-Host "##########################################################"
	Write-Host "Agent: $($instanceAgent.DisplayName)"
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

	write-host  "task status: " (get-SCOMTaskResult -BatchID $taskInstance.BatchId | select -ExpandProperty Status)

	#Wait for task to complete
	while ((get-SCOMTaskResult -BatchID $taskInstance.BatchId | select -ExpandProperty Status) -ne "Succeeded")
	{
		write-Host "Waiting…" -ForegroundColor Yellow
		write-host  "task status: " (get-SCOMTaskResult -BatchID $taskInstance.BatchId | select -ExpandProperty Status)
		Sleep -Seconds 2
	}
	
	#Show task output
	get-SCOMTaskResult -BatchID $taskInstance.BatchId
}

Write-Host "Done!" -ForegroundColor Green
Read-Host "Press Enter to Exit"
