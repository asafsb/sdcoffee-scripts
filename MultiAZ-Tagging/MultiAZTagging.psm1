Function Create-MultiAzTags {
<#
    .NOTES
    -------------------------------------------------------
    Created by:    Asaf Blubshtein
    Date:          
    Blog:          https://softwaredefinedcoffee.com
    Twitter:       @AsafBlubshtein
    -------------------------------------------------------

    .SYNOPSIS
        Create tags for MultiAZ clsuter VM placement
    .DESCRIPTION
        This command will create a tag category based on the parameter provided. By default the category name will be 'MultiAZSites'.
        For every stretched cluster two tags will be created for the preferred and non-preferred sites. The tag naming convention is 'Cluster-Name'-Preferred/'Cluster-Name'-Non-Preferred, e.g. Cluster-1-Preferred and Cluster-1-Non-Preferred.
        The description for each tag will be the corresponding AZ name. The tag names or description should not be changed.
    .EXAMPLE
        Create-MultiAzTags -TagCategoryName $Name
#>
    Param (
        [Parameter(Mandatory=$false)][String]$TagCategoryName="MultiAZSites"
)

    $Clusters = (Get-Cluster | Get-VsanFaultDomain).Cluster | Get-Unique

    Write-Host "Creating tags for the following stretched-clusters:"
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
    
    foreach ($Cluster in $Clusters) {
        $FaultDomains = $Cluster | Get-VsanFaultDomain
        $ClustView = $cluster.ExtensionData.MoRef
        $vSanStretchedView = Get-VsanView -Id "VimClusterVsanVcStretchedClusterSystem-vsan-stretched-cluster-system"
        $PrefFD = $vSanStretchedView.VSANVcGetPreferredFaultDomain($ClustView).PreferredFaultDomainName

        Write-Host "`nCreating tags for cluster $Cluster with a preferred fault domain in $PrefFD"
        
        $PrefTag = "$Cluster-Preferred" 
        If (Get-Tag -Category $TagCategory | where {$_.Name -eq $PrefTag})
        {
            Write-Host -ForegroundColor Green "Tag $PrefTag in category $TagCategoryName already exists"
        } Else {
            Write-Host -ForegroundColor Yellow "Creating tag $PrefTag in category $TagCategoryName for AZ $($FaultDomains | Where {$_.Name -eq $PrefFD})"
            New-Tag -Name $PrefTag -Category $TagCategory -Description "$($FaultDomains | Where {$_.Name -eq $PrefFD})" | Out-Null
        }
        
        #Nonpreferred FD
        $NoPrefTag = "$Cluster-Non-Preferred" 
        If (Get-Tag -Category $TagCategory | where {$_.Name -eq $NoPrefTag})
        {
            Write-Host -ForegroundColor Green "Tag $NoPrefTag in category $TagCategoryName already exists"
        } Else {
            Write-Host -ForegroundColor Yellow "Creating tag $NoPrefTag in category $TagCategoryName for AZ $($FaultDomains | Where {$_.Name -ne $PrefFD})"
            New-Tag -Name $NoPrefTag -Category $TagCategory -Description "$($FaultDomains | Where {$_.Name -ne $PrefFD})" | Out-Null
        }
    }
    Write-Host -ForegroundColor Green "`n`nThe following tags were created or validated:"
    Get-Tag -Category $TagCategory | Format-Table
}

Function Tag-MultiAzHosts {
<#
    .NOTES
    -------------------------------------------------------
    Created by:    Asaf Blubshtein
    Date:          
    Blog:          https://softwaredefinedcoffee.com
    Twitter:       @AsafBlubshtein
    -------------------------------------------------------

    .SYNOPSIS
        Assign MultiAZ tags to hosts in MultiAZ clusters
    .DESCRIPTION
        Will tag each host in a stretched cluster with an appropriate tag from the category provided. By default the category is 'MultiAZSites'.
        The tag name should correspond to the following format - 'Cluster-Name'-Preferred/'Cluster-Name'-Non-Preferred, e.g. Cluster-1-Preferred and Cluster-1-Non-Preferred. The description for each tag should be the corresponding AZ name.
    .EXAMPLE
        Tag-MultiAzHosts -TagCategoryName $Name
#>
    Param (
        [Parameter(Mandatory=$false)][String]$TagCategoryName="MultiAZSites"
)
    
    $CreatedTags = @()

    $Clusters = (Get-Cluster | Get-VsanFaultDomain).Cluster | Get-Unique

    Write-Host "Tagging hosts in the following stretched-clusters:"
    $i = 1
    foreach ($Cluster in $Clusters) {
        Write-Host "`t$i. $Cluster"
        $i++
    }
    
    Write-Host "`nValidating tag category $TagCategoryName exists..."
    $TagCategory = Get-TagCategory | Where {$_.Name -eq $TagCategoryName}
     
    If (-not $TagCategory) {
        Write-error "Tag category $TagCategoryName could not be found. Please create the tag category manually or using the Create-MultiAzTags cmdlet"
    } Else {
        Write-Host -ForegroundColor Green "Tag Category $TagCategory found"
    
        foreach ($Cluster in $Clusters) {
            $FaultDomains = $Cluster | Get-VsanFaultDomain
            $PrefTagName = "$Cluster-Preferred"
            $NoPrefTagName = "$Cluster-Non-Preferred"

            $FDTags = Get-Tag -Category $TagCategory | Where {($_.Name -eq $PrefTagName) -or ($_.Name -eq $NoPrefTagName)}

            Write-Host "`nValidating tags for $Cluster exists..."
            If ($FDTags.Count -ne 2) {
                Write-Error "Tags $PrefTagName or $NoPrefTagName in category $TagCategoryName could not be found. Please create the tags manually or using the Create-MultiAzTags cmdlet"
            } Else {
                Write-Host -ForegroundColor Green "Tags $PrefTagName and $NoPrefTagName in category $TagCategory found"

                $VMHosts = Get-VMHost -Location $cluster
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
                    } Else {Write-Error "An appropriate tag with a description of $($FD.Name) could not be found. Please add the descriptions manually or re-create the tags using the Create-MultiAzTags cmdlet"}
                }
            }
        }

        Write-Host "`nThe following tags were assigned:"
        $CreatedTags
    }
}