Function Create-MultiAzTags {
<#
    .NOTES
    ===========================================================================
    Created by:    Asaf Blubshtein
    Date:          5/26/2020
    Organization:  VMware
    Blog:          https://softwaredefinedcoffee.com
    Twitter:       @AsafBlubshtein
    ===========================================================================

    .SYNOPSIS
        Create Multi AZ tags
    .DESCRIPTION
        This cmdlet connects to the HCX Enterprise Manager
    .EXAMPLE
        Connect-HcxServer -Server $HCXServer -Username $Username -Password $Password
#>
#    Param (
#        [Parameter(Mandatory=$true)][String]$Server,
#        [Parameter(Mandatory=$true)][String]$Username,
#        [Parameter(Mandatory=$true)][String]$Password
#    )
    
    $TagCategoryName = "MultiAZSites"

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
        $TagCategory = New-TagCategory -Name $TagCategoryName -Cardinality Single -EntityType @("VM","VMhost") -Description "Sites for Stretched Clusters"
    }
    
    foreach ($Cluster in $Clusters) {
        $FaultDomains = $Cluster | Get-VsanFaultDomain
        Write-Host "`nPlease select the preferred vSAN Fault Domain for cluster $Cluster`:"
        Write-Host -ForegroundColor Gray "To view the preferred fault domain go to Hosts and Clusters > $Cluster > Configure > vSAN > Fault Domains"
        For ($i=0; $i -lt $FaultDomains.Count; $i++)  {
          Write-Host "$($i+1): $($FaultDomains[$i])"
        }

        do
        {
            try {
            [int]$PrefFd = Read-Host "Enter a number to select the preferred fault domain: " 
            } catch {}
        } until ($FaultDomains[$PrefFd-1])

        #preferred FD
        $PrefTag = "$Cluster-Preferred" 
        If (Get-Tag -Category $TagCategory | where {$_.Name -eq $PrefTag})
        {
            Write-Host -ForegroundColor Green "`nTag $PrefTag in category $TagCategoryName already exists"
        } Else {
            Write-Host -ForegroundColor Yellow "`nCreating tag $PrefTag in category $TagCategoryName for AZ $($FaultDomains[$PrefFd-1])"
            New-Tag -Name $PrefTag -Category $TagCategory -Description "$($FaultDomains[$PrefFd-1])" | Out-Null
        }
        
        #Nonpreferred FD
        $NoPrefTag = "$Cluster-Non-Preferred" 
        If (Get-Tag -Category $TagCategory | where {$_.Name -eq $NoPrefTag})
        {
            Write-Host -ForegroundColor Green "`nTag $NoPrefTag in category $TagCategoryName already exists"
        } Else {
            Write-Host -ForegroundColor Yellow "`nCreating tag $NoPrefTag in category $TagCategoryName for AZ $($FaultDomains[$PrefFd-2])"
            New-Tag -Name $NoPrefTag -Category $TagCategory -Description "$($FaultDomains[$PrefFd-2])" | Out-Null
        }
    }
    Write-Host -ForegroundColor Green "`n`nThe following tags were created or validated:"
    Get-Tag -Category $TagCategory | Format-Table
}

Function Tag-MultiAzHosts {
<#
    .NOTES
    ===========================================================================
    Created by:    Asaf Blubshtein
    Date:          5/26/2020
    Organization:  VMware
    Blog:          https://softwaredefinedcoffee.com
    Twitter:       @AsafBlubshtein
    ===========================================================================

    .SYNOPSIS
        Create Multi AZ tags
    .DESCRIPTION
        This cmdlet connects to the HCX Enterprise Manager
    .EXAMPLE
        Connect-HcxServer -Server $HCXServer -Username $Username -Password $Password
#>
#    Param (
#        [Parameter(Mandatory=$true)][String]$Server,
#        [Parameter(Mandatory=$true)][String]$Username,
#        [Parameter(Mandatory=$true)][String]$Password
#    )
    
    $TagCategoryName = "MultiAZSites"
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

            Write-Host "`nValidating tag $Cluster`:"
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