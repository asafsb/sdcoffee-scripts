Function New-MultiAzTags {
<#
    .NOTES
    -------------------------------------------------------
    Created by:    Asaf Blubshtein
    Date:          May 26, 2020
    Blog:          https://softwaredefinedcoffee.com
    Twitter:       @AsafBlubshtein
    -------------------------------------------------------

    .SYNOPSIS
        Create tags for MultiAZ clsuter VM placement
    .DESCRIPTION
        This command will create a tag category based on the parameter provided, tags for each AZ and a VM-Host affinity compute policy for each AZ. By default the category name will be 'MultiAZ'.
        For every vCenter with a stretched cluster two tags will be created for the preferred and non-preferred sites. The tag naming convention is 'Category Name'-Preferred/'Category Name'-Non-Preferred, e.g. MultiAZ-Preferred and MultiAZ-Non-Preferred.
        The description for each tag will be the corresponding AZ name. The tag names or description should not be changed, as this will cause the Set-MultiAzHostTag command to stop working.
        Two compute policies will be created for the preferred and non-preferred sites. The policy naming convention is 'Category Name'-Preferred/'Category Name'-Non-Preferred, e.g. MultiAZ-Preferred and MultiAZ-Non-Preferred.
    .EXAMPLE
        New-MultiAzTags -TagCategoryName $Name
    .EXAMPLE
        New-MultiAzTags -SkipPolicyCreation
#>
    Param (
        [Parameter(Mandatory=$false)][String]$TagCategoryName="MultiAZ",
        [Switch]$SkipPolicyCreation
)

    $Clusters = (Get-Cluster | Get-VsanFaultDomain).Cluster | Get-Unique

    If ($Clusters) {
        Write-Host "Creating tags for vCenter with the following stretched-clusters:"
        $i = 1
        foreach ($Cluster in $Clusters) {
            Write-Host "`t$i. $Cluster"
            $i++
        }
    
        Write-Host "`nValidating tag category $TagCategoryName exists..."
        $TagCategory = Get-TagCategory | Where {$_.Name -eq $TagCategoryName}
     
        If ($TagCategory) {
            Write-Host -ForegroundColor Green "Tag Category $TagCategory exists"
        } Else {
            Write-Host -ForegroundColor Yellow "Tag Category $TagCategoryName doesn't exists. Creating the category"
            $TagCategory = New-TagCategory -Name $TagCategoryName -Cardinality Single -EntityType @("VM","VMhost") -Description "Sites for Stretched Clusters. Do not change tag names or descriptions. This will cause the host tagging cmdlet to fail."
        }

        $ComputeCIS = Get-CisService "com.vmware.vcenter.compute.policies"

        $Cluster = $Clusters[0]    
    
        $FaultDomains = $Cluster | Get-VsanFaultDomain
        $ClustView = $cluster.ExtensionData.MoRef
        $vSanStretchedView = Get-VsanView -Id "VimClusterVsanVcStretchedClusterSystem-vsan-stretched-cluster-system"
        $PrefFD = $vSanStretchedView.VSANVcGetPreferredFaultDomain($ClustView).PreferredFaultDomainName

        Write-Host "`nCreating tag for preferred fault domain in $PrefFD"
        
        $PrefTagName = "$TagCategoryName-Preferred" 
        If ($PrefTag = Get-Tag -Category $TagCategory | where {$_.Name -eq $PrefTagName})
        {
            Write-Host -ForegroundColor Green "Tag $PrefTagName in category $TagCategoryName already exists"
        } Else {
            Write-Host -ForegroundColor Yellow "Creating tag $PrefTagName in category $TagCategoryName for AZ $($FaultDomains | Where {$_.Name -eq $PrefFD})"
            $PrefTag = New-Tag -Name $PrefTagName -Category $TagCategory -Description "$($FaultDomains | Where {$_.Name -eq $PrefFD})"
        }
        
        #Nonpreferred FD
        $NoPrefTagName = "$TagCategoryName-Non-Preferred" 
        If ($NoPrefTag = Get-Tag -Category $TagCategory | where {$_.Name -eq $NoPrefTagName})
        {
            Write-Host -ForegroundColor Green "Tag $NoPrefTagName in category $TagCategoryName already exists"
        } Else {
            Write-Host -ForegroundColor Yellow "Creating tag $NoPrefTagName in category $TagCategoryName for AZ $($FaultDomains | Where {$_.Name -ne $PrefFD})"
            $NoPrefTag = New-Tag -Name $NoPrefTagName -Category $TagCategory -Description "$($FaultDomains | Where {$_.Name -ne $PrefFD})"
        }

        Write-Host -ForegroundColor Green "`n`nThe following tags were created or validated:"
        Get-Tag -Category $TagCategory | Format-Table

        #Creating Policies
        If (-Not $SkipPolicyCreation) {
            $NoPrefPolicyName = "$TagCategoryName-Non-Preferred"
            $ComputeCis = Get-CisService "com.vmware.vcenter.compute.policies"

            $PolicySpec = @{
                capability = "com.vmware.vcenter.compute.policies.capabilities.vm_host_affinity"
                name = ""
                description = ""
                host_tag = ""
                vm_tag = ""
            }

            
            #Preferred Site Policy
            $PrefPolicyName = "$TagCategoryName-Preferred"
            If ($PrefPolicy = $ComputeCis.list() | Where {$_.Name -eq $PrefPolicyName -and $_.capability -like "*vm_host_affinity"})
            {
                Write-Host -ForegroundColor Green "VM-Host affinity policy $PrefPolicyName already exists."

            } Else {
                Write-Host -ForegroundColor Yellow "Creating VM-Host affinity policy $PrefPolicyName"
                $PolicySpec.name = $PrefPolicyName
                $PolicySpec.description = "Do not change"
                $PolicySpec.host_tag = $PrefTag.Id
                $PolicySpec.vm_tag = $PrefTag.Id
                
                $ComputeCis.Create($PolicySpec)
            }

            #Non-Preferred Site Policy
            $NoPrefPolicyName = "$TagCategoryName-Non-Preferred"
            If ($PrefPolicy = $ComputeCis.list() | Where {$_.Name -eq $NoPrefPolicyName -and $_.capability -like "*vm_host_affinity"})
            {
                Write-Host -ForegroundColor Green "VM-Host affinity policy $NoPrefPolicyName already exists."

            } Else {
                Write-Host -ForegroundColor Yellow "`nCreating VM-Host affinity policy $NoPrefPolicyName"
                $PolicySpec.name = $NoPrefPolicyName
                $PolicySpec.description = "Do not change"
                $PolicySpec.host_tag = $NoPrefTag.Id
                $PolicySpec.vm_tag = $NoPrefTag.Id
                
                $ComputeCis.Create($PolicySpec)
            }
                                    
        } Else { Write-Host "Skipping compute policy creation"}

    } Else { Write-Error "No stretched clusters found in the connected vCenter" }

}

Function Set-MultiAzHostTag {
<#
    .NOTES
    -------------------------------------------------------
    Created by:    Asaf Blubshtein
    Date:          May 26, 2020
    Blog:          https://softwaredefinedcoffee.com
    Twitter:       @AsafBlubshtein
    -------------------------------------------------------

    .SYNOPSIS
        Assign MultiAZ tags to hosts in MultiAZ clusters
    .DESCRIPTION
        Will tag each host in a stretched cluster with an appropriate tag from the category provided. By default the category is 'MultiAZ'.
        The tag name should correspond to the following format - 'Category Name'-Preferred/'Category Name'-Non-Preferred, e.g. MultiAZ-Preferred and MultiAZ-Non-Preferred. The description for each tag should be the corresponding AZ name.
    .EXAMPLE
        Set-MultiAzHostTag -TagCategoryName $Name
    .EXAMPLE
        Set-MultiAzHostTag -ClusterName $ClusterName
    .EXAMPLE
        Set-MultiAzHostTag -HostName $HostName
#>
    Param (
        [Parameter(Mandatory=$false)][String]$TagCategoryName="MultiAZ",
        [Parameter(Mandatory=$false)][String]$ClusterName,
        [Parameter(Mandatory=$false)][String]$HostName
)
    
    $CreatedTags = @()

    If ($HostName) {
        Write-Host "Tagging host $HostName"
        $VMHosts = Get-VMHost -Name $HostName
        $Clusters = ($VMHosts | Get-Cluster | Get-VsanFaultDomain).Cluster | Get-Unique
    } ElseIf ($ClusterName) {
        $Clusters = (Get-Cluster -Name $ClusterName | Get-VsanFaultDomain).Cluster | Get-Unique
        Write-Host "Tagging hosts in the stretched-cluster $ClusterName"
    } Else {
        $Clusters = (Get-Cluster | Get-VsanFaultDomain).Cluster | Get-Unique

        Write-Host "Tagging hosts in the following stretched-clusters:"
        $i = 1
        foreach ($Cluster in $Clusters) {
            Write-Host "`t$i. $Cluster"
            $i++
        }
    }
    
    Write-Host "`nValidating tag category $TagCategoryName exists..."
    $TagCategory = Get-TagCategory | Where {$_.Name -eq $TagCategoryName}
     
    If (-not $TagCategory) {
        Write-error "Tag category $TagCategoryName could not be found. Please create the tag category manually or using the New-MultiAzTags cmdlet"
    } Else {
        Write-Host -ForegroundColor Green "Tag Category $TagCategory found"
    

        foreach ($Cluster in $Clusters) {
            $FaultDomains = $Cluster | Get-VsanFaultDomain
            $PrefTagName = "$TagCategoryName-Preferred"
            $NoPrefTagName = "$TagCategoryName-Non-Preferred"

            $FDTags = Get-Tag -Category $TagCategory | Where {($_.Name -eq $PrefTagName) -or ($_.Name -eq $NoPrefTagName)}

            Write-Host "`nValidating tags for $Cluster exists..."
            If ($FDTags.Count -ne 2) {
                Write-Error "Tags $PrefTagName or $NoPrefTagName in category $TagCategoryName could not be found. Please create the tags manually or using the New-MultiAzTags cmdlet"
            } Else {
                Write-Host -ForegroundColor Green "Tags $PrefTagName and $NoPrefTagName in category $TagCategory found"
                If (-Not $HostName) {
                    $VMHosts = Get-VMHost -Location $cluster 
                }
                Foreach ($VMHost in $VMHosts) {
                    $FD = Get-VsanFaultDomain -VMHost $VMHost -Cluster $Cluster
                    $VMHostTag = $FDTags | where {$_.Description -eq "$($FD.Name)"}
                    If ($VMHostTag) {
                        If (Get-TagAssignment -Entity $VMHost -Category $TagCategory) {
                            Write-Host -ForegroundColor Green "Host $VMHost already has a tag from category $TagCategory assigned. Skipping tag assignment"
                        } Else {
                            Write-Host -ForegroundColor Yellow "Assigning tag $VMHostTag to host $VMhost"
                            $CreatedTags += New-TagAssignment -Entity $VMHost -Tag $VMHostTag
                        }
                    } Else {Write-Error "An appropriate tag with a description of $($FD.Name) could not be found. Please add the descriptions manually or re-create the tags using the New-MultiAzTags cmdlet"}
                }
            }
        }

        If ($CreatedTags) {
            Write-Host "`nNo tags were assigned"
        } Else {
            Write-Host "`nThe following tags were assigned:"
            $CreatedTags
        }
    }
}