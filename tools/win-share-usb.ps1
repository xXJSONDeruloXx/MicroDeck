# Shares this PC's internet connection with a handheld plugged in over USB (Windows Internet Connection Sharing).
# The handheld appears as a "UsbNcm Host Device" adapter (usb-gadget, docs/roadmap.md); it then gets 192.168.137.x by DHCP.
# Needs an elevated PowerShell. Only one public and one private connection can exist, so any sharing already on is switched off.
#   powershell -ExecutionPolicy Bypass -File tools/win-share-usb.ps1 [-Internet "Ethernet"]
param([string]$Internet = (Get-NetRoute -DestinationPrefix 0.0.0.0/0 | Sort-Object RouteMetric | Select-Object -First 1).InterfaceAlias)
$usb = (Get-NetAdapter | Where-Object { $_.InterfaceDescription -like "UsbNcm*" -and $_.Status -eq "Up" } | Select-Object -First 1).Name
if (-not $usb) { throw "no UsbNcm adapter is up: is the handheld plugged in and booted?" }
$m = New-Object -ComObject HNetCfg.HNetShare
$conns = @{}
foreach ($c in $m.EnumEveryConnection) { $conns[$m.NetConnectionProps($c).Name] = $c }
foreach ($k in $conns.Keys) {
  $cfg = $m.INetSharingConfigurationForINetConnection($conns[$k])
  if ($cfg.SharingEnabled) { Write-Host "switching off sharing on $k"; $cfg.DisableSharing() }
}
$m.INetSharingConfigurationForINetConnection($conns[$Internet]).EnableSharing(0)
$m.INetSharingConfigurationForINetConnection($conns[$usb]).EnableSharing(1)
Write-Host "sharing $Internet with $usb"
