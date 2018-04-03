#################################
# Functions
#################################

Function Get-VMwareOverCommit {
            Param($Cluster)
            
            $VMhosts = Get-Cluster -Name $cluster.name | Get-VMHost 
            $Datastore = Get-Cluster -Name $cluster.name | Get-Datastore | Where-Object {$_.Name -like "*vsan*"}

            # CPU
            $ClusterPoweredOnvCPUs = (Get-VM -Location $cluster.name | Where-Object {$_.PowerState -eq "PoweredOn" } | Measure-Object NumCpu -Sum).Sum
            $ClusterCPUCores = ($VMhosts | Measure-Object NumCpu -Sum).Sum
            
            # Memory
            $ClusterPoweredOnvRAM = [Math]::Round((Get-VM -Location $cluster.name | Where-Object {$_.PowerState -eq "PoweredOn" } | Measure-Object MemoryGB -Sum).Sum, 2)
            $ClusterPhysRAM = [Math]::Round(($VMhosts | Measure-Object MemoryTotalGB -Sum).Sum, 2)
            
            # Storage
            $ClusterCapacity = [Math]::Round(((Get-Datastore $Datastore.name).CapacityGB | Measure-Object -Sum).Sum, 2)
            $ClusterUsedSpace = [Math]::Round(((Get-VM -Datastore $Datastore.name).UsedSpaceGB | Measure-Object -Sum).Sum, 2)
            $ClusterProvisionedSpace = [Math]::Round(((Get-VM -Datastore $Datastore.name).ProvisionedSpaceGB | Measure-Object -Sum).Sum, 2)

            #OvercommitProperties
            $ClusterOvercommitCPUProperties = [ordered]@{
                    'Cluster Name'=$cluster.name                    
                    'CPU Cores'=$ClusterCPUCores
                    'Total vCPUs'=($OvercommitInfoCollection."Total vCPUs" | Measure-Object -Sum).Sum
                    'PoweredOn vCPUs'=if ($ClusterPoweredOnvCPUs) {$ClusterPoweredOnvCPUs} Else { 0 -as [int] }
                    'vCPU/Core ratio'=if ($ClusterPoweredOnvCPUs) {[Math]::Round(($ClusterPoweredOnvCPUs / $ClusterCPUCores), 3)} Else { $null }
                    'CPU Overcommit (%)'=if ($ClusterPoweredOnvCPUs) {[Math]::Round(100*(( $ClusterPoweredOnvCPUs - $ClusterCPUCores) / $ClusterCPUCores), 3)} Else { $null }
                    }
            $ClusterOvercommitMEMProperties = [ordered]@{
                    'Cluster Name'=$cluster.name                    
                    'Physical RAM (GB)'=$ClusterPhysRAM
                    'Total vRAM (GB)'=[Math]::Round(($OvercommitInfoCollection."Total vRAM (GB)" | Measure-Object -Sum).Sum, 2)
                    'PoweredOn vRAM (GB)'=if ($ClusterPoweredOnvRAM) {$ClusterPoweredOnvRAM} Else { 0 -as [int] }
                    'vRAM/Physical RAM ratio'=if ($ClusterPoweredOnvRAM) {[Math]::Round(($ClusterPoweredOnvRAM / $ClusterPhysRAM), 3)} Else { $null }
                    'RAM Overcommit (%)'=if ($ClusterPoweredOnvRAM) {[Math]::Round(100*(( $ClusterPoweredOnvRAM - $ClusterPhysRAM) / $ClusterPhysRAM), 2)} Else { $null }
                    }      
            $ClusterOvercommitStorageProperties = [ordered]@{
                    'Cluster Name'=$cluster.name                    
                    'Datastore Cluster'=$Datastore
                    'Capacity (GB)'=$ClusterCapacity
                    'Used Space (GB)'=if ($ClusterUsedSpace) { $ClusterUsedSpace } Else { 0 -as [int] }
                    'Provisioned Space (GB)'=if ($ClusterProvisionedSpace) { $ClusterProvisionedSpace } Else { 0 -as [int] }
                    'Provisioned / Capacity ratio'=if ($ClusterProvisionedSpace) {[Math]::Round(($ClusterProvisionedSpace / $ClusterCapacity), 3)} Else { $null }
                    'Storage Overcommit (%)'=if ($ClusterProvisionedSpace) {[Math]::Round(100*(( $ClusterProvisionedSpace - $ClusterCapacity) / $ClusterCapacity), 2)} Else { $null }
                    }      

            $ClusterOvercommitObj = New-Object -TypeName PSObject -Property $ClusterOvercommitProperties
            $ClusterOvercommitObjCPU = New-Object -TypeName PSObject -Property $ClusterOvercommitCPUProperties
            $ClusterOvercommitObjMEM = New-Object -TypeName PSObject -Property $ClusterOvercommitMEMProperties
            $ClusterOvercommitObjStorage = New-Object -TypeName PSObject -Property $ClusterOvercommitStorageProperties
            $ClusterOvercommitObjCPU,$ClusterOvercommitObjMEM,$ClusterOvercommitObjStorage
}

Function Get-ClusterTargets {
    Write-Host "Getting available clusters (Please wait)..."
    $ClusterTargets = Get-Cluster
    Return $ClusterTargets
}#End Get-ClusterTargets

#Get-ClusterTarget Function to pick from a list of available clusters
Function Get-ClusterTarget {
    Param($ClusterTargets)
    $PickList = @()
    $Count = 1
    ForEach ($ClusterTarget in ($ClusterTargets | Select-Object Name)) {
        $PickItem = "" | Select-Object Option, Name
        $PickItem.Option = $Count++
        $PickItem.Name = $ClusterTarget.Name
        $PickList += $PickItem
    }
    #Reselect option
    $PickItem = "" | Select-Object Option, Name
    $PickItem.Option = "R"
    $PickItem.Name = "Re-select vCenter"
    $PickList += $PickItem
    #List
    $PickList | Format-Table Option, Name -AutoSize | Out-Host
    $Length = ([string]$PickList.Count).Length
    If ($Length -eq 1) {$Length = 2}
    Do {
        $PickNum = Read-Host "Please select the number of the Target Cluster"
        If ($PickNum -ne "r") {If ($Picknum.length -lt $Length) {Do {$PickNum = "0$PickNum"}Until($Picknum.Length -eq $Length)}}
    }
    Until(($PickList | Where-Object {$_.Option -eq $PickNum}) -ne $null -or $PickNum -eq "r")
    If ($PickNum -eq "r") {$ClusterTarget = $null}
    Else {$ClusterTarget = $PickList | Where-Object {$_.Option -eq $PickNum}}
    Return $ClusterTarget
}#End Get-ClusterTarget

#Connect-VC Function for establishing session to vCenter
Function Connect-VC {
    Param([Parameter(Mandatory = $True)]$vCenter, $vcred)
    Write-Host "Attempting to Connect to " -NoNewLine -ForegroundColor White
    Write-Host $vCenter -NoNewLine -ForegroundColor Cyan
    Write-Host "..." -NoNewLine -ForegroundColor White
    $VCSession = Connect-VIServer $vCenter -Credential $vcred -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
    If ($VCSession -ne $null) {
        Write-Host "Connected!" -ForegroundColor Green
    }
    Else {
        Write-Host "Failed!" -ForegroundColor Red
        pause
        return
    }
    Return $VCSession
}#End Connect-VC

#################################
# Main Code
#################################
If(!(Get-Module | Where {$_.Name -like "*VMWare*"})){$VMware = get-module -ListAvailable | Where {$_.Name -like "*vmware*"};foreach($i in $Vmware){Import-Module $i.name}}
$Creds = Get-Credential -Message "Please enter system admin username (<USERNAME>@uk.wal-mart.com) and password"
$vcenter = Read-Host "Please enter the vcenter to connect to"
$Details = $true
$Session = Connect-VC -vcenter $vcenter -vcred $creds
$ClusterTargets = Get-ClusterTargets
$Cluster = Get-ClusterTarget -ClusterTargets $ClusterTargets
$ClusterOvercommitObjCPU,$ClusterOvercommitObjMEM,$ClusterOvercommitObjStorage = Get-VMwareOverCommit -Cluster $Cluster

#Show all details
If($Details){
    Write-Host "Complete Cluster Details" -ForegroundColor Cyan
    Write-Host "------------------------" -ForegroundColor Cyan
    Write-Host "`nCPU:"
    $ClusterOvercommitObjCPU
    Write-Host "`nMemory:"
    $ClusterOvercommitObjMEM
    Write-Host "`nStorage:"
    $ClusterOvercommitObjStorage
}

#Color for summary output
If($ClusterOvercommitObjCPU.'vCPU/Core ratio' -lt "0.75"){$CPUcolor = "Green"}
Elseif($ClusterOvercommitObjCPU.'vCPU/Core ratio' -ge "0.75" -and $ClusterOvercommitObjCPU.'vCPU/Core ratio' -lt "0.90"){$CPUcolor = "Yellow"}
Elseif($ClusterOvercommitObjCPU.'vCPU/Core ratio'-ge "0.90"){$CPUcolor = "Red"}
If($ClusterOvercommitObjMEM.'vRAM/Physical RAM ratio' -lt "0.75"){$RAMcolor = "Green"}
Elseif($ClusterOvercommitObjMEM.'vRAM/Physical RAM ratio' -ge "0.75" -and $ClusterOvercommitObjMEM.'vRAM/Physical RAM ratio' -lt "0.90"){$RAMcolor = "Yellow"}
Elseif($ClusterOvercommitObjMEM.'vRAM/Physical RAM ratio'-ge "0.90"){$RAMcolor = "Red"}
If($ClusterOvercommitObjStorage.'Provisioned / Capacity ratio' -lt "0.75"){$Storagecolor = "Green"}
Elseif($ClusterOvercommitObjStorage.'Provisioned / Capacity ratio' -ge "0.75" -and $ClusterOvercommitObjStorage.'Provisioned / Capacity ratio' -lt "0.90"){$Storagecolor = "Yellow"}
Elseif($ClusterOvercommitObjStorage.'Provisioned / Capacity ratio'-ge "0.90"){$Storagecolor = "Red"}

#Display Summary
Write-Host "Summary: "
Write-Host "vCPU/Core Ratio: [" -NoNewLine; Write-Host "$($ClusterOvercommitObjCPU."vCPU/Core ratio")" -ForegroundColor $CPUcolor -NoNewline; Write-Host "]" 
Write-Host "vRAM/Physical RAM ratio: [" -NoNewLine; Write-Host "$($ClusterOvercommitObjMEM."vRAM/Physical RAM ratio")" -ForegroundColor $RAMcolor -NoNewline; Write-Host "]"
Write-Host "Provisioned / Capacity ratio: [" -NoNewLine; Write-Host "$($ClusterOvercommitObjStorage."Provisioned / Capacity ratio")" -ForegroundColor $StorageColor -NoNewline; Write-Host "]"

#Display all information for anything not Green
If($CPUcolor -ne "Green"){Write-Host "`nCPU Details:";$ClusterOvercommitObjCPU}
If($RAMcolor -ne "Green"){ Write-Host "`nMemory Details:";$ClusterOvercommitObjMEM}
If($Storagecolor -ne "Green"){Write-Host "`nStorage Details:"$ClusterOvercommitObjStorage}
Disconnect-VIServer * -Confirm:$False -Force
pause

