Import-Module <PSM1 folder>\HCX-GC-Migration-API_v0.4.psm1

$GCProperties = @{
    MacAddress = ""
    IpAddress = ""
    NetMask = ""
    Gateways = @()
    DnsServers = @()
    DnsSuffix = ""
} #Properties for the Guest customization object

$netCustomArray = @()
$NetworkMapping = @()

$Server = "192.168.1.30" #HCX Server IP
$Username = "administrator@vsphere.local" #vCenter/HCX admin
$Password = "Str0ngPassw0rd" #User password

Connect-HcxServerAPI -Server $Server -Username $Username -Password $Password #connect to the HCX server for an API session
Connect-HCXServer -Server $Server -Username $Username -Password $Password #connect to the HCX server for a PowerCLI session, to retrieve parameters


write-host("Getting Source HCX Site")
$HcxSrcSite = Get-HCXSite -Source -Server $Server

write-host("Getting Target HCX Site")
$HcxDstSite = Get-HCXSite -Destination -Server $Server

write-host("Getting VM to Migrate (This may take a while)") 
$HcxVM = Get-HCXVM -Name "demo-mig1" -Site $HcxSrcSite #Get VM object

write-host("Getting Destination Folder")
$DstFolder = Get-HCXContainer -Name "demo-folder" -Site $HcxDstSite #get the destination folder within VMWonAWS

write-host("Getting Container")
$DstCompute = Get-HCXContainer -Site $HcxDstSite -Name "Compute-ResourcePool" #get the destination RP within VMWonAWS

write-host("Getting Datastore")
$DstDatastore = Get-HCXDatastore -Name "WorkloadDatastore" -Site $HcxDstSite #get the destination datastore within VMWonAWS

write-host("Getting Source Network")
$SrcNetwork = Get-HCXNetwork -Name "DemoNetwork1" -Site $HcxSrcSite | Where {$_.type -eq "OpaqueNetwork"} #get the source network on-prem. Note - you might need to filter based on type if there's NSX on-prem

write-host("Getting Target Network")
$DstNetwork = Get-HCXNetwork -Name "HCXDemo1" -Type NsxtSegment -Site $HcxDstSite #Get the destination network within VMWonAWS

write-host("Creating Network Mapping")
$NetworkMap = New-HCXNetworkMapping -SourceNetwork $SrcNetwork -DestinationNetwork $DstNetwork #Create a mapping for the source and destination network

$NetworkMapping+=$NetworkMap

write-host("Getting Source Network")
$SrcNetwork = Get-HCXNetwork -Name "DemoNetwork2" -Site $HcxSrcSite | Where {$_.type -eq "OpaqueNetwork"} #get the source network on-prem. Note - you might need to filter based on type if there's NSX on-prem

write-host("Getting Target Network")
$DstNetwork = Get-HCXNetwork -Name "HCXDemo2" -Type NsxtSegment -Site $HcxDstSite #Get the destination network within VMWonAWS

write-host("Creating Network Mapping")
$NetworkMap = New-HCXNetworkMapping -SourceNetwork $SrcNetwork -DestinationNetwork $DstNetwork #Create a mapping for the source and destination network

$NetworkMapping+=$NetworkMap

write-host("Setting Schedule Start Time")
$StartTime = "6/25/2020 9:00PM" #Start date for the switchover schedule

write-host("Setting Schedule End Time")
$EndTime = "6/27/2020 9:00PM" #End date for the switchover schedule


write-host("Setting Host Name")
$GCName = "demo-mig1.corp.local" #If using GC, the hostname of the VM. Even if staying the same, the name must be specified. Can be with or without the FQDN. The host name, not including the FQDN, shouldn't be more than 15 charachters

write-host("Setting Domain Name")
$GCDomain = "corp.local" #If using GC, the DNS suffix for searches

$NetCustom = New-Object psobject -Property $GCProperties #Creating a new object for guest customization parameters

write-host("Setting MAC Address of NIC to change")
$NetCustom.MacAddress = "00:50:56:b3:7e:0b" #If using GC, the MAC of the NIC that needs to be customized

write-host("Setting Guest Customization IP Address")
$NetCustom.IpAddress = "192.168.25.25" #If using GC, the new IP

write-host("Setting Guest Customization Netmask")
$NetCustom.NetMask = "255.255.255.0" #If using GC, the new netmask

write-host("Setting Guest Customization Default Gateways")
$NetCustom.Gateways = @("192.168.25.1") #If using GC, the new GW. Can accept an array of GW if needed, but this will be rare - $GWs = @("172.25.25.1","172.25.25.2")

write-host("Setting DNS Servers")
$NetCustom.DnsServers = @("8.8.8.8","8.8.4.4") #If using GC, the new DNS servers to be used. Can accept a single DNS server if needed

write-host("Setting DNS Suffix")
$NetCustom.DNSSuffix = "corp.local" #If using GC, the DNS suffix for searches

$netCustomArray+=$NetCustom

$NetCustom = New-Object psobject -Property $GCProperties

write-host("Setting MAC Address of NIC to change")
$NetCustom.MacAddress = "00:50:56:b3:6b:57" #If using GC, the MAC of the NIC that needs to be customized

write-host("Setting Guest Customization IP Address")
$NetCustom.IpAddress = "192.168.103.25" #If using GC, the new IP

write-host("Setting Guest Customization Netmask")
$NetCustom.NetMask = "255.255.255.0" #If using GC, the new netmask

write-host("Setting Guest Customization Default Gateways")
$NetCustom.Gateways = "192.168.103.1" #If using GC, the new GW. Can accept an array of GW if needed, but this will be rare - $GWs = @("172.25.25.1","172.25.25.2")

write-host("Setting DNS Servers")
$NetCustom.DnsServers = "8.8.8.8" #If using GC, the new DNS servers to be used. Can accept a single DNS server if needed

write-host("Setting DNS Suffix")
$NetCustom.DNSSuffix = "corp.local" #If using GC, the DNS suffix for searches

$netCustomArray+=$NetCustom

$mig = Start-HcxMigrationAPI -VM $HcxVM -SourceHCX $HcxSrcSite -DestHCX $HcxDstSite -TargetComputeContainer $DstCompute -TargetFolder $DstFolder -NetworkMappings $NetworkMapping -TargetDatastore $DstDatastore -GuestCustomization $True -GCName $GCName -GCDomain $GCDomain -GCNetCustomization $netCustomArray -UpgradeVMTools $true -UpgradeHardware $True -ScheduleStartTime $StartTime -ScheduleEndTime $EndTime -ValidateOnly $false
