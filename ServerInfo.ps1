If(((Get-CimInstance win32_bios).SerialNumber).length -gt 50){($Serial = (Get-CimInstance win32_bios).SerialNumber).substring(0, 50)} Else {$Serial = (Get-CimInstance win32_bios).SerialNumber}
$ServersObj = New-Object -TypeName PSObject
$ServersObj | Add-Member -MemberType NoteProperty -Name Servername -Value ($ENV:COMPUTERNAME + "." + (get-wmiobject win32_computersystem).Domain)
$ServersObj | Add-Member -MemberType NoteProperty -Name OS -Value ((Get-CimInstance Win32_OperatingSystem).Caption)
$ServersObj | Add-Member -MemberType NoteProperty -Name CPU -Value ((Get-WmiObject Win32_processor).NumberOfLogicalProcessors)
$ServersObj | Add-Member -MemberType NoteProperty -Name Memory -Value ((Get-WMIObject Win32_PhysicalMemory).capacity / 1GB)
$ServersObj | Add-Member -MemberType NoteProperty -Name Serial -Value $Serial
$ServersObj | Add-Member -MemberType NoteProperty -Name Manufacturer -Value ((Get-WMIObject win32_computersystem).Manufacturer)
$ServersObj | Add-Member -MemberType NoteProperty -Name Model -Value ((Get-WMIObject win32_computersystem).Model)
$ServersObj | Add-Member -MemberType NoteProperty -Name SystemDisk -Value ([Math]::Round((Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='C:'").Size / 1GB))

Write-Host "Server Info:" -Nonewline -ForegroundColor Cyan
$ServersObj
