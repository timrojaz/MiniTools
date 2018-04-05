#################################
# Functions
#################################

Function Get-VMwareOverCommit {
            Param($Cluster,[switch]$Details)
            
            $VMhosts = Get-Cluster -Name $cluster.name | Get-VMHost 
            $Datastore = Get-Cluster -Name $cluster.name | Get-Datastore | Where-Object {$_.Type -like "vsan"}
            If(!$Datastore){
                $DSTargets = Get-DSTargets -ClusterTarget $Cluster
                $Datastore = Get-DSTarget -DSTargets $DSTargets
            }

            # CPU
            $ClusterPoweredOnvCPUs = (Get-VM -Location $cluster.name | Where-Object {$_.PowerState -eq "PoweredOn" } | Measure-Object NumCpu -Sum).Sum
            $ClusterCPUCores = ($VMhosts | Measure-Object NumCpu -Sum).Sum
            # Preparing a collection to store information for each individual ESXi host
            $CPU = @()
            Foreach($VMhost in $VMhosts){$CPU += (Get-VM -Location $VMhost | Measure-Object NumCpu -Sum).Sum}
            $TotalvCPU = ($CPU | Measure-Object -Sum).Sum
            
            # Memory
            $ClusterPoweredOnvRAM = [Math]::Round((Get-VM -Location $cluster.name | Where-Object {$_.PowerState -eq "PoweredOn" } | Measure-Object MemoryGB -Sum).Sum, 2)
            $ClusterPhysRAM = [Math]::Round(($VMhosts | Measure-Object MemoryTotalGB -Sum).Sum, 2)
            $RAM = @()
            Foreach ($VMhost in $VMhosts){$RAM += [Math]::Round((Get-VM -Location $VMhost | Measure-Object MemoryGB -Sum).Sum, 2)}
            $TotalvRAM = ($RAM | Measure-Object -Sum).Sum

            # Storage
            if($datastore.type -ne "vsan"){
                $ClusterUsableCapacity = $ClusterCapacity = [Math]::Round(((Get-Datastore $Datastore.name).CapacityGB | Measure-Object -Sum).Sum, 2)
                $ClusterUsedSpace = [Math]::Round(((Get-VM -Datastore $Datastore.name).UsedSpaceGB | Measure-Object -Sum).Sum, 2)
                $ClusterProvisionedSpace = [Math]::Round(((Get-VM -Datastore $Datastore.name).ProvisionedSpaceGB | Measure-Object -Sum).Sum, 2)
            }
            #WARNING: VSAN Calculation is definitely a work in progress!
            else{
                $ClusterCapacity = (Get-Datastore $Datastore.name).CapacityGB
                $ClusterUsableCapacity = ((Get-Datastore $Datastore.name).CapacityGB * 0.7) / 2
                $ClusterUsedSpace = [Math]::Round(((Get-VM -Datastore $Datastore.name).UsedSpaceGB | Measure-Object -Sum).Sum, 2)
                $ClusterProvisionedSpace = [Math]::Round(((Get-VM -Datastore $Datastore.name).ProvisionedSpaceGB | Measure-Object -Sum).Sum, 2)
            }

            #OvercommitProperties
            $ClusterOvercommitCPUProperties = [ordered]@{
                    'Cluster Name'=$cluster.name                    
                    'CPU Cores'=$ClusterCPUCores
                    'Total vCPUs'=$TotalvCPU
                    'PoweredOn vCPUs'=if ($ClusterPoweredOnvCPUs) {$ClusterPoweredOnvCPUs} Else { 0 -as [int] }
                    'vCPU/Core ratio'=if ($ClusterPoweredOnvCPUs) {[Math]::Round(($ClusterPoweredOnvCPUs / $ClusterCPUCores), 3)} Else { $null }
                    'CPU Overcommit (%)'=if ($ClusterPoweredOnvCPUs) {[Math]::Round(100*(( $ClusterPoweredOnvCPUs - $ClusterCPUCores) / $ClusterCPUCores), 3)} Else { $null }
                    }
            $ClusterOvercommitMEMProperties = [ordered]@{
                    'Cluster Name'=$cluster.name                    
                    'Physical RAM (GB)'=$ClusterPhysRAM
                    'Total vRAM (GB)'=$TotalvRAM
                    'PoweredOn vRAM (GB)'=if ($ClusterPoweredOnvRAM) {$ClusterPoweredOnvRAM} Else { 0 -as [int] }
                    'vRAM/Physical RAM ratio'=if ($ClusterPoweredOnvRAM) {[Math]::Round(($ClusterPoweredOnvRAM / $ClusterPhysRAM), 3)} Else { $null }
                    'RAM Overcommit (%)'=if ($ClusterPoweredOnvRAM) {[Math]::Round(100*(( $ClusterPoweredOnvRAM - $ClusterPhysRAM) / $ClusterPhysRAM), 2)} Else { $null }
                    }
            $ClusterOvercommitStorageProperties = [ordered]@{
                    'Cluster Name'=$cluster.name                    
                    'Datastore Cluster'=$Datastore.name
                    'Capacity (GB)'=$ClusterCapacity
                    'Usable Capacity (GB)' = $ClusterUsableCapacity
                    'Used Space (GB)'=if ($ClusterUsedSpace) { $ClusterUsedSpace } Else { 0 -as [int] }
                    'Provisioned Space (GB)'=if ($ClusterProvisionedSpace) { $ClusterProvisionedSpace } Else { 0 -as [int] }
                    'Provisioned / Capacity ratio'=if ($ClusterProvisionedSpace) {[Math]::Round(($ClusterProvisionedSpace / $ClusterUsableCapacity), 3)} Else { $null }
                    'Storage Overcommit (%)'=if ($ClusterProvisionedSpace) {[Math]::Round(100*(( $ClusterProvisionedSpace - $ClusterUsableCapacity) / $ClusterUsableCapacity), 2)} Else { $null }
                    }      

            $ClusterOvercommitObjCPU = New-Object -TypeName PSObject -Property $ClusterOvercommitCPUProperties
            $ClusterOvercommitObjMEM = New-Object -TypeName PSObject -Property $ClusterOvercommitMEMProperties
            $ClusterOvercommitObjStorage = New-Object -TypeName PSObject -Property $ClusterOvercommitStorageProperties
            
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

            Clear-Host
            Write-Host "[$vcenter]\$($Cluster.Name)`n" -ForegroundColor Black  -BackgroundColor White
            
            #Show all details
            If($Details){
                Write-Host "Complete Cluster Details" -ForegroundColor Cyan
                Write-Host "------------------------" -ForegroundColor Cyan
                Write-Host "CPU:" -ForegroundColor DarkBlue  -BackgroundColor White
                $ClusterOvercommitObjCPU | Format-Table -Autosize
                Write-Host "Memory:" -ForegroundColor DarkBlue -BackgroundColor White
                $ClusterOvercommitObjMEM | Format-Table -Autosize
                Write-Host "Storage:" -ForegroundColor DarkBlue -BackgroundColor White
                $ClusterOvercommitObjStorage | Format-Table -Autosize
                
            }
            Else{
                #Display all information for anything not Green
                Write-Host "Cluster Details for OverCommit" -ForegroundColor Cyan
                Write-Host "------------------------------" -ForegroundColor Cyan
                If($CPUcolor -ne "Green"){Write-Host "CPU:" -ForegroundColor DarkBlue -BackgroundColor White;$ClusterOvercommitObjCPU | Format-Table -Autosize}
                If($RAMcolor -ne "Green"){ Write-Host "Memory:" -ForegroundColor DarkBlue -BackgroundColor White;$ClusterOvercommitObjMEM | Format-Table -Autosize}
                If($Storagecolor -ne "Green"){Write-Host "Storage:" -ForegroundColor DarkBlue -BackgroundColor White;$ClusterOvercommitObjStorage | Format-Table -Autosize}
            }

            #Display Summary
            Write-Host "Summary: "
            Write-Host "vCPU/Core Ratio: [" -NoNewLine; Write-Host "$($ClusterOvercommitObjCPU."vCPU/Core ratio")" -ForegroundColor $CPUcolor -NoNewline; Write-Host "]" 
            Write-Host "vRAM/Physical RAM ratio: [" -NoNewLine; Write-Host "$($ClusterOvercommitObjMEM."vRAM/Physical RAM ratio")" -ForegroundColor $RAMcolor -NoNewline; Write-Host "]"
            Write-Host "Provisioned / Capacity ratio: [" -NoNewLine; Write-Host "$($ClusterOvercommitObjStorage."Provisioned / Capacity ratio")" -ForegroundColor $StorageColor -NoNewline; Write-Host "]"

            
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

#Get-DSTargets Function to list available datastores available on a cluster
Function Get-DSTargets {
    Param($ClusterTarget)
    Write-Host "Getting available datastores (Please wait)..."
    $DSTargets = Get-Cluster $ClusterTarget.Name | Get-Datastore
    Return $DSTargets
}#End Get-DSTargets

#Get-DSTarget Function to pick datastore from available
Function Get-DSTarget {
    Param($DSTargets)
    $PickList = @()
    $Count = 1
    ForEach ($DSTarget in ($DSTargets | Select-Object Name, FreeSpaceGB, CapacityGB)) {
        $PickItem = "" | Select-Object Number, Name, FreeSpaceGB, CapacityGB
        $PickItem.Number = $Count++
        $PickItem.Name = $DSTarget.Name
        $PickItem.FreeSpaceGB = [Math]::Round($DSTarget.FreeSpaceGB)
        $PickItem.CapacityGB = [Math]::Round($DSTarget.CapacityGB)
        $PickList += $PickItem
    }
    $PickList | Format-Table Number, Name, FreeSpaceGB, CapacityGB -AutoSize | Out-Host
    $Length = ([string]$PickList.Count).Length
    If ($Length -eq 1) {$Length = 2}
    Do {
        $PickNum = Read-Host "Please select the number of the Target Datastore"
        If ($Picknum.length -lt $Length) {Do {$PickNum = "0$PickNum"}Until($Picknum.Length -eq $Length)}
    }
    Until(($PickList | Where-Object {$_.Number -eq $PickNum}) -ne $null)
    $DSTarget = $PickList | Where-Object {$_.Number -eq $PickNum}
    Return $DSTarget
}#End Get-DSTarget


#################################
# Main Code
#################################
If(!(Get-Module | Where {$_.Name -like "*VMWare*"})){Write-Host "Loading VMware Modules...";$VMware = get-module -ListAvailable | Where {$_.Name -like "*vmware*"};foreach($i in $Vmware){Import-Module $i.name}}
$Creds = Get-Credential -Message "Please enter system admin username (<USERNAME>@uk.wal-mart.com) and password"
$vcenter = Read-Host "Please enter the vcenter to connect to"
#Full details?
$Caption = “Please select an option” ;$Message = “Do you want to show all details or just a summary” ;$Choices = [System.Management.Automation.Host.ChoiceDescription[]] @(“&Details”, “&Summary”) 
[int]$DefaultChoice = 0;$ChoiceRTN = $Host.ui.PromptForChoice($Caption, $Message, $Choices, $DefaultChoice);switch ($choiceRTN) { 0 {$RunDetails = $true};1 {$RunDetails = $false}}

$Session = Connect-VC -vcenter $vcenter -vcred $creds
If(!$Session){exit}
$ClusterTargets = Get-ClusterTargets
$Cluster = Get-ClusterTarget -ClusterTargets $ClusterTargets
IF($RunDetails -eq $true){Get-VMwareOverCommit -Cluster $Cluster -Details}
Else{Get-VMwareOverCommit -Cluster $Cluster}

Disconnect-VIServer * -Confirm:$False -Force
pause
