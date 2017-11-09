#Ping Console v0.1


##############################
#
##############################

Function Get-FileName($initialDirectory)
{
    [System.Reflection.Assembly]::LoadWithPartialName("System.windows.forms") | Out-Null
    
    $OpenFileDialog = New-Object System.Windows.Forms.OpenFileDialog
    $OpenFileDialog.initialDirectory = $initialDirectory
    $OpenFileDialog.filter = "CSV (*.csv)| *.csv"
    $OpenFileDialog.ShowDialog() | Out-Null
    $OpenFileDialog.filename
}

Function Get-Status ($Servers)
                    {
                    $PingInfo = @()
                    Foreach ($Server in $Servers){   
                            $Ping = New-Object -TypeName PSObject
                            $Test = Test-Connection -ComputerName $Server -Count 1 -ea silentlycontinue 
						    if($Test -ne $Null)
			                    {
                                Add-Member -InputObject $Ping -MemberType NoteProperty -Name Status -Value "Online "
                                Add-Member -InputObject $Ping -MemberType NoteProperty -Name Host -Value $Server
                                Add-Member -InputObject $Ping -MemberType NoteProperty -Name IPV4Address -Value $test.IPV4Address
                                }
						    else
			                    { 	
                                Add-Member -InputObject $Ping -MemberType NoteProperty -Name Status -Value "Offline"
                                Add-Member -InputObject $Ping -MemberType NoteProperty -Name Host -Value $Server
                                Add-Member -InputObject $Ping -MemberType NoteProperty -Name IPV4Address -Value "---.---.---.---"                                            
                                }
                            $PingInfo += $Ping
                        }
                    $PingInfo
                    }

Function Get-IPAM ()
                    {
                    #$File = Read-Host "Please enter file to csv import"
                    Write-Host "Please select the csv to import" -ForegroundColor Yellow
                    $File = Get-FileName "%UserProfile%\Desktop\"
                    $Items = Import-Csv -Delimiter "," -Path "$file"
                    clear
                    Write-Host "Imported file contains:" -ForegroundColor White
                    Write-Host ""
                    If ($items -eq $null){
                    exit
                    }
                    $Items
                    }

##############################
# CODE                       #
##############################
$Host.UI.RawUI.WindowTitle = 'Wallboard'
$DNS = @()
$Ping = @()
$Date = Get-Date -Format HHmmss
$FilePath = "C:\temp\pingIPResults_$Date.csv"
$Exit = $null
$myshell = New-Object -com "Wscript.Shell"
$refresh = 15 #in seconds

$Caption = “Please select an option” 
$Message = “Stop device from going to sleep?” 
$Choices = [System.Management.Automation.Host.ChoiceDescription[]] @(“&Yes”, “&No”) 
[int]$DefaultChoice = 1
$ChoiceRTN = $Host.ui.PromptForChoice($Caption,$Message,$Choices,$DefaultChoice) 
switch($choiceRTN)
            { 
             0    {$sleep = 'off'} 
             1    {$sleep = 'on'}
            }

$Items = Get-IPAM
$Items | ft

$Time = Get-Date
$TimeWait = $Time.AddHours(12)
#GET STATUS OF $ITEMS.NAME
$Measure = Measure-Command{$States = Get-Status($Items.Name)}

Do{
#Write ouput.
clear
$Time = Get-Date
Write-Host "Wallboard status updated at: " -ForegroundColor Yellow -NoNewline
Write-Host $time -ForegroundColor Cyan
Write-Host ""
Write-Host "Status  `tIPv4 Address   `t`tHostName" -ForegroundColor Gray
Write-Host "------  `t---------------`t`t--------" -ForegroundColor Gray

    Foreach ($State in $States){
    If ($State.Status -eq "Offline")
        {$StatusColor = 'Red'
        $HostColor = 'Gray'
        }
    Else{$StatusColor = 'Green';$HostColor= 'White'}
    [string]$StateIPAddressString = $State.IPv4Address
    While ($StateIPAddressString.Length -lt 15){$StateIPAddressString = $StateIPAddressString+" "}
    Write-Host $State.Status`t -ForegroundColor $Statuscolor -NoNewline
    Write-Host $StateIPAddressString`t`t -NoNewLine -ForegroundColor $HostColor
    Write-Host $State.Host -ForegroundColor $HostColor
    }

Write-Host ""
$nexttime = $time.AddSeconds($measure.seconds)
Write-Host "Last refresh took: " -ForegroundColor Yellow -NoNewline
Write-Host $measure.seconds -ForegroundColor Cyan -NoNewline
Write-Host " seconds" -ForegroundColor Cyan
Write-Host "Refresh expected at: " -ForegroundColor Yellow -NoNewline
Write-Host $nexttime -ForegroundColor Cyan
if($sleep -eq 'off'){$myShell.sendkeys(".")}
$Measure = Measure-Command{$States = Get-Status($Items.Name)}
}
Until($Time -like $TimeWait)

