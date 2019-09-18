# VMware/Pure Analyzer
# Written by Joshua Woleben


# Pure arrays
$pure_arrays = @("pure_array1","pure_array2")
$pure_volumes= @{}
$datastore_to_pure = @{}
# Vcenter host
$vcenter_host = "vcenter_host"

$TranscriptFile = "C:\Temp\VMwarePureReport_$(get-date -f MMddyyyyHHmmss).txt"
Start-Transcript -Path $TranscriptFile
Write-Output "Initializing..."

# Import required modules
Import-Module PureStoragePowerShellSDK
Import-Module VMware.VimAutomation.Core

# Define a gigabyte in bytes
$gb = 1073741824

# Gather authentication credentials
Write-Output "Please enter the following credentials: `n`n"

# Collect vSphere credentials
Write-Output "`n`nvSphere credentials:`n"
$vsphere_user = Read-Host -Prompt "Enter the user for the vCenter host"
$vsphere_pwd = Read-Host -Prompt "Enter the password for connecting to vSphere: " -AsSecureString
$vsphere_creds = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $vsphere_user,$vsphere_pwd -ErrorAction Stop

$pure_user = Read-Host -Prompt "Enter the user for the Pure storage arrays"
$pure_pwd = Read-Host -Prompt "Enter the password for the Pure storage array user: " -AsSecureString
$pure_creds = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $pure_user,$pure_pwd -ErrorAction Stop

# Connect to vCenter
Connect-VIServer -Server $vcenter_host -Credential $vsphere_creds -ErrorAction Stop

# Get All VMs
Write-Host "Gathering all VMs..."
$vm_collection = Get-VM -Server $vcenter_host

# Get all datastores
Write-Host "Gathering datastores..."
$datastore_collection = Get-Datastore -Server $vcenter_host


# Get all pure volumes on all arrays
Write-Host "Gathering Pure volumes..."
ForEach ($array in $pure_arrays) {

    # Connect to Pure Array
    $pure_connect = New-PfaArray -EndPoint $array -Credentials $pure_creds -IgnoreCertificateError -ErrorAction Stop

    # Get all volumes
    $pure_volumes[$array] += Get-PfaVolumes -Array $pure_connect

    # Disconnect Pure array
    Disconnect-PfaArray -Array $pure_connect

}

# Figure out what array a datastore is on
Write-Host "Determining datastore array locations..."
$datastore_collection | ForEach-Object {

    # Get disk name
    $disk_name = $_.Name

    # Get UUID from VMware
    $uuid = $_.ExtensionData.Info.Vmfs.Extent[0].DiskName

    Write-Host "Processing $disk_name..."

    # Translate VMware UUID to Pure UUID by removing the naa. and the first eight characters, and converting to uppercase
    $pure_uuid = ($uuid -replace "naa\.\w{8}","").ToUpper()
    Write-Host "UUID: $uuid Pure UUID: $pure_uuid"

    # Search each array for the Pure UUID
    ForEach ($array in $pure_arrays) {

        # Search each volume for the correct UUID
        $pure_volumes[$array] | ForEach-Object { 
            # If UUID found, store with array name
            if (($_ | Select -ExpandProperty serial) -eq $pure_uuid) {
               Write-Host "$disk_name found on $array!"
               $datastore_to_pure[$disk_name] = $array
            }

        }
    }
    
}

Write-Host "Inventorying all VMs and disks..."

# Write header
$csv = @("VM Name, Physical Host, Disk Name, Datastore, Pure Array")

# Go through every VM
$vm_collection | ForEach-Object {

    # Get VM guest name
    $vm_name = ($_.Name).ToString()

    # Get physical host
    $vm_host = ($_.VMHost.Name).ToString()

    # Get disks, associated datastores and Pure array
    $_ | Get-HardDisk | Where-Object {$_.DiskType -notlike "Raw*" } | ForEach-Object { $filename = $_.FileName; $diskname = $_.Name; $current_datastore = $filename.split("]")[0].split("[")[1]; $csv += ($vm_name + ", " + $vm_host + ", " + $diskname + ", " + $current_datastore + ", " + $datastore_to_pure[$current_datastore]) }
#    $_ | Get-HardDisk | Where-Object {$_.DiskType -like "Raw*" } | ForEach-Object { $filename = $_.FileName; $diskname = $_.Name; $current_datastore = $filename.split("]")[0].split("[")[1]; $csv += ($vm_name + ", " + $vm_host + ", " + $diskname + ", " + $current_datastore + ", " + $datastore_to_pure[$current_datastore] + "`n") }

}

# Disconnect from vCenter
Disconnect-VIServer -Server $vcenter_host -Confirm:$false

# Generate email report
$email_list=@("user1@example.com","user2@example.com")
$subject = "Storage Inventory Report"

$body = ($csv | Out-String)

Stop-Transcript

$MailMessage = @{
    To = $email_list
    From = "InventoryReport<Donotreply@example.com>"
    Subject = $subject
    Body = $body
    SmtpServer = "smtp.example.com"
    ErrorAction = "Stop"
    Attachment = $TranscriptFile
}
Send-MailMessage @MailMessage

