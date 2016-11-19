param (
  [string] $SqlDbConnectionString,
  [string] $OctopusMasterNode,
  [string] $OctopusMasterKey,
  [string] $OctopusAdminUsername,
  [string] $OctopusAdminPassword,
  [string] $VMAdminUsername,
  [string] $VMAdminPassword,
  [string] $StorageAccountName,
  [string] $storageAccountKey,
  [string] $fileShareName
)

$config = @{}
$msiFileName = "Octopus.latest-x64.msi"
$downloadUrl = "https://octopus.com/downloads/latest/OctopusServer64"
$userRightsFileName = "ntrights.exe"
$userRightsdownloadUrl = "https://dioctofileshare.blob.core.windows.net/octopusha/ntrights.exe"
$installBasePath = "D:\Install\"
$userRightsPath = $installBasePath + $userRightsFileName
$msiPath = $installBasePath + $msiFileName
$msiLogPath = $installBasePath + $msiFileName + '.log'
$null = $installBasePath + 'Configure-OctopusDeployNode.ps1.log'

$OFS = "`r`n"

function Write-Log
{
  param (
    [string] $message
  )
  
  $timestamp = ([datetime]::UTCNow).ToString("yyyy'-'MM'-'dd'T'HH':'mm':'ss")
  Write-Output "[$timestamp] $message"
}

function Write-CommandOutput 
{
  param (
    [string] $output
  )    
  
  if ($output -eq "") { return }
  
  Write-Output ""
  $output.Trim().Split("`n") |ForEach-Object { Write-Output "`t| $($_.Trim())" }
  Write-Output ""
}

function Get-Config
{
  Write-Log "======================================"
  Write-Log " Get Config"
  Write-Log ""    
  Write-Log "Parsing script parameters ..."
    
  $config.Add("sqlDbConnectionString", [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($SqlDbConnectionString)))
  $config.Add("octopusAdminUsername", [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($OctopusAdminUsername)))
  $config.Add("octopusAdminPassword", [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($OctopusAdminPassword)))
   $config.Add("VMAdminUsername", [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($VMAdminUsername)))
  $config.Add("VMAdminPassword", [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($VMAdminPassword)))
  $config.Add("OctopusMasterNode", [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($OctopusMasterNode)))
  $config.Add("OctopusMasterKey", [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($OctopusMasterKey)))
    $config.Add("StorageAccountName", [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($StorageAccountName)))
  $config.Add("storageAccountKey", [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($storageAccountKey)))
	$config.Add("fileShareName", [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($fileShareName)))
    
  Write-Log "done."
  Write-Log ""
}

function Create-InstallLocation
{
  Write-Log "======================================"
  Write-Log " Create Install Location"
  Write-Log ""
    
  if (!(Test-Path $installBasePath))
  {
    Write-Log "Creating installation folder at '$installBasePath' ..."
    New-Item -ItemType Directory -Path $installBasePath | Out-Null
    Write-Log "done."
  }
  else
  {
    Write-Log "Installation folder at '$installBasePath' already exists."
  }
  
  Write-Log ""
}

function Install-OctopusDeploy
{
  Write-Log "======================================"
  Write-Log " Install Octopus Deploy"
  Write-Log ""
    
  Write-Log "Downloading Octopus Deploy installer '$downloadUrl' to '$msiPath' ..."
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  Invoke-WebRequest -Uri $downloadUrl -Method GET -OutFile $msiPath
  Write-Log "done."
  
  Write-Log "Installing via '$msiPath' ..."
  $exe = 'msiexec.exe'
  $args = @(
    '/qn', 
    '/i', $msiPath, 
    '/l*v', $msiLogPath
  )
  $output = .$exe $args
  Write-CommandOutput $output
  Write-Log "done."
    
  Write-Log ""
}


function SetCmdKey
{
  Write-Log "======================================"
  Write-Log " Setting File share for Octopus Deploy"
  Write-Log ""

  Write-Log "Setting via cmdkey ..."

if (!(Get-ScheduledTask -TaskName "OctopusCmdKey" -ErrorAction SilentlyContinue))
{
  Write-Log "Task Does not exists"
}
else
{
  Write-Log "Unregister the existing Task"
Unregister-ScheduledTask -TaskPath "\" -TaskName "OctopusCmdKey" -Confirm:$false
}
$action = New-ScheduledTaskAction -Execute 'cmdkey' -Argument "/add:$($Config.StorageAccountName).file.core.windows.net /user:$($Config.StorageAccountName) /pass:$($config.storageAccountKey)"
$trigger =  New-ScheduledTaskTrigger -AtStartup
Register-ScheduledTask -Action $action -Trigger $trigger -TaskName "OctopusCmdKey" -TaskPath "\" -Description "Octopus Key" -User $($Config.VMAdminUsername) -Password $($Config.VMAdminPassword)
sleep(20)
Start-ScheduledTask -TaskName "OctopusCmdKey" -TaskPath "\"
sleep(20)
  Write-CommandOutput $output
  Write-Log "done."
    
  Write-Log ""
}

function Import-UserRights
{
  Write-Log "======================================"
  Write-Log " Install Octopus Deploy"
  Write-Log ""
    $userRightsPath = $installBasePath + $userRightsFileName
  Write-Log "Downloading NTRights '$userRightsFileName' to '$userRightsPath' ..."
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  Invoke-WebRequest -Uri $userRightsdownloadUrl -Method GET -OutFile $userRightsPath
  Write-Log "done."
  
  Write-Log "Installing via '$userRightsPath' ..."
  $exe = $userRightsPath
  $args = @(
    '-u', "$($Config.VMAdminUsername)", 
    '+r', 'SeServiceLogonRight'
  )

  $output = .$exe $args
  Write-CommandOutput $output
  Write-Log "done."
    
  Write-Log ""
}

function Configure-OctopusDeploy
{
  Write-Log "======================================"
  Write-Log " Configure Octopus Deploy"
  Write-Log ""
    
  $exe = 'C:\Program Files\Octopus Deploy\Octopus\Octopus.Server.exe'
    
  $count = 0
  while(!(Test-Path $exe) -and $count -lt 5)
  {
    Write-Log "$exe - not available yet ... waiting 10s ..."
    Start-Sleep -s 10
    $count = $count + 1
  }
    
  Write-Log "Creating Octopus Deploy instance ..."
  $args = @(
    'create-instance', 
    '--console', 
    '--instance', 'OctopusServer', 
    '--config', 'C:\Octopus\OctopusServer.config'     
  )
  $output = .$exe $args
  Write-CommandOutput $output
  Write-Log "done."
  
  Write-Log "Configuring Octopus Deploy instance ..."
  $args = @(
    'configure', 
    '--console',
    '--instance', 'OctopusServer', 
    '--home', 'C:\Octopus', 
    '--storageConnectionString', $($config.sqlDbConnectionString), 
    '--upgradeCheck', 'True', 
    '--upgradeCheckWithStatistics', 'True', 
    '--webAuthenticationMode', 'UsernamePassword', 
    '--webForceSSL', 'False', 
    '--webListenPrefixes', 'http://localhost:80/', 
    '--commsListenPort', '10943' ,
    '--serverNodeName', $($config.OctopusMasterNode),
    '--masterKey',$($config.OctopusMasterKey)    
  )
  $output = .$exe $args
  Write-CommandOutput $output
  Write-Log "done."
    
  Write-Log "Creating Octopus Deploy database ..."
  $args = @(
    'database', 
    '--console',
    '--instance', 'OctopusServer', 
    '--create'
  )
  $output = .$exe $args
  Write-CommandOutput $output
  Write-Log "done."
    
  Write-Log "Stopping Octopus Deploy instance ..."
  $args = @(
    'service', 
    '--console',
    '--instance', 'OctopusServer', 
    '--stop'
  )
  $output = .$exe $args
  Write-CommandOutput $output
  Write-Log "done."
  
   
  Write-Log "Reconfigure and start Octopus Deploy instance ..."
  $args = @(
    'service',
    '--console', 
    '--instance', 'OctopusServer', 
    '--install', 
    '--reconfigure', 
    '--start',
    '--username', ".\$($Config.VMAdminUsername)",
    '--password', $($Config.VMAdminPassword)
  )
  $output = .$exe $args
  Write-CommandOutput $output
  Write-Log "done."
    
  Write-Log ""
} 

function Configure-Firewall
{
  Write-Log "======================================"
  Write-Log " Configure Firewall"
  Write-Log ""
    
  $firewallRuleName = "Allow_Port80_HTTP"
    
  if ((Get-NetFirewallRule -Name $firewallRuleName -ErrorAction Ignore) -eq $null)
  {
    Write-Log "Creating firewall rule to allow port 80 HTTP traffic ..."
    $firewallRule = @{
      Name=$firewallRuleName
      DisplayName ="Allow Port 80 (HTTP)"
      Description="Port 80 for HTTP traffic"
      Direction='Inbound'
      Protocol='TCP'
      LocalPort=80
      Enabled='True'
      Profile='Any'
      Action='Allow'
    }
    $output = (New-NetFirewallRule @firewallRule | Out-String)
    Write-CommandOutput $output
    Write-Log "done."
  }
  else
  {
    Write-Log "Firewall rule to allow port 80 HTTP traffic already exists."
  }
  
  Write-Log ""
}

 
try
{
  Write-Log "======================================"
  Write-Log " Installing Octopus Deploy"
  Write-Log "======================================"
  Write-Log ""
  
  Get-Config
  Create-InstallLocation
  Import-UserRights
  SetCmdKey
  Install-OctopusDeploy
  Configure-OctopusDeploy
  Configure-Firewall
   
  Write-Log "Installation successful."
  Write-Log ""
}
catch
{
  Write-Log $_
}
