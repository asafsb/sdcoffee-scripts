Function Connect-HcxServerAPI {
<#
    .NOTES
    ===========================================================================
    Created by:    William Lam
    Date:          09/16/2018
    Organization:  VMware
    Blog:          http://www.virtuallyghetto.com
    Twitter:       @lamw
    ===========================================================================
    Updated by:    Asaf Blubshtein
    Date:          04/20/2020
    Blog:          https://softwaredefinedcoffee.com/
    Twitter:       @AsafBlubshtein
	===========================================================================

    .SYNOPSIS
        Connect to the HCX Enterprise Manager
    .DESCRIPTION
        This cmdlet connects to the HCX Enterprise Manager
    .EXAMPLE
        Connect-HcxServerAPI -Server $HCXServer -Username $Username -Password $Password
#>
    Param (
        [Parameter(Mandatory=$true)][String]$Server,
        [Parameter(Mandatory=$true)][String]$Username,
        [Parameter(Mandatory=$true)][String]$Password
    )

    $payload = @{
        "username" = $Username
        "password" = $Password
    }
    $body = $payload | ConvertTo-Json

    $hcxLoginUrl = "https://$Server/hybridity/api/sessions"

    if($PSVersionTable.PSEdition -eq "Core") {
        $results = Invoke-WebRequest -Uri $hcxLoginUrl -Body $body -Method POST -UseBasicParsing -ContentType "application/json" -SkipCertificateCheck
    } else {
        $results = Invoke-WebRequest -Uri $hcxLoginUrl -Body $body -Method POST -UseBasicParsing -ContentType "application/json"
    }

    if($results.StatusCode -eq 200) {
        $hcxAuthToken = $results.Headers.'x-hm-authorization'

        $headers = @{
            "x-hm-authorization"="$hcxAuthToken"
            "Content-Type"="application/json"
            "Accept"="application/json"
        }

        $global:hcxConnection = new-object PSObject -Property @{
            'Server' = "https://$server/hybridity/api";
            'headers' = $headers
        }
        $global:hcxConnection
    } else {
        Write-Error "Failed to connect to HCX Manager, please verify your vSphere SSO credentials"
    }
}

Function Get-HcxMigrationAPI {
<#
    .NOTES
    ===========================================================================
    Created by:    William Lam
    Date:          09/24/2018
    Organization:  VMware
    Blog:          http://www.virtuallyghetto.com
    Twitter:       @lamw
    ===========================================================================
    Updated by:    Asaf Blubshtein
    Date:          06/01/2020
    Blog:          https://softwaredefinedcoffee.com/
    Twitter:       @AsafBlubshtein
	===========================================================================

    .SYNOPSIS
        List all HCX Migrations that are in-progress, have completed or failed
    .DESCRIPTION
        This cmdlet lists all HCX Migrations that are in-progress, have completed or failed
    .EXAMPLE
        List all HCX Migrations

        Get-HcxMigrationAPI
    .EXAMPLE
        List ten running HCX Migrations

        Get-HcxMigrationAPI -RunningMigrations -NumberOfMigrations 10
    .EXAMPLE
        List a specific HCX Migration

        Get-HcxMigrationAPI -MigrationId <MigrationID>
#>
    Param (
        [Parameter(Mandatory=$false)][String[]]$MigrationId,
        [Parameter(Mandatory=$false)][int]$NumberOfMigrations=0,
        [Switch]$RunningMigrations,
        [Switch]$FormatJSON
    )

    If (-Not $global:hcxConnection) { Write-error "HCX Auth Token not found, please run Connect-HcxManagerAPI " } Else {
        If($PSBoundParameters.ContainsKey("MigrationId")){
            $spec = @{
                filter = @{
                    migrationId = $MigrationId
                }
                options =@{
                    resultLevel = "MOBILITYGROUP_ITEMS"
                    compat = 2.1
                }
            }
        } Else {
            $spec = @{
                filter = @{
                }
                options =@{
                    resultLevel = "MOBILITYGROUP_ITEMS"
                    compat = 2.1
                }
            }
        }
        $body = $spec | ConvertTo-Json

        $hcxQueryUrl = $global:hcxConnection.Server + "/migrations?action=query"
        if($PSVersionTable.PSEdition -eq "Core") {
            $requests = Invoke-WebRequest -Uri $hcxQueryUrl -Method POST -Body $body -Headers $global:hcxConnection.headers -UseBasicParsing -SkipCertificateCheck
        } else {
            $requests = Invoke-WebRequest -Uri $hcxQueryUrl -Method POST -Body $body -Headers $global:hcxConnection.headers -UseBasicParsing
        }

        $migrations = ($requests.content | ConvertFrom-Json).data.items

        if($RunningMigrations){
            $migrations = $migrations | where { $_.state -ne "MIGRATE_FAILED" -and $_.state -ne "MIGRATE_CANCELED" -and $_.state -ne "MIGRATED" -and $_.state -ne "TRANSFER_FAILED" -and $_.state -ne "MIGRATION_FAILED" -and $_.state -ne "MIGRATION_COMPLETE" -and $_.state -ne "MIGRATION_CANCELLED"}
        }

        If (($NumberOfMigrations -ne 0) -and ($migrations.Count -gt $NumberOfMigrations)){
            $migrations = $migrations[0..$($NumberOfMigrations-1)]            
        }
        
        If ($FormatJSON) {
            $migrations
        } Else {
            $results = @()
            foreach ($migration in $migrations) {
			    [datetime]$EpochTime = '1970-01-01 00:00:00'
			    $CreateTime = ($EpochTime.AddMilliseconds($migration.creationDate)).ToLocalTime()
			    $UpdateTime = ($EpochTime.AddMilliseconds($migration.lastUpdated)).ToLocalTime()
			    if ($migration.switchoverParams.schedule.startTime -ne "0" -and $migration.switchoverParams.schedule.startTime -ne $null) {
				    $ScheduleStart = ($EpochTime.AddMilliseconds($migration.switchoverParams.schedule.startTime)).ToLocalTime()
				    $ScheduleEnd = ($EpochTime.AddMilliseconds($migration.switchoverParams.schedule.expiryTime)).ToLocalTime()
			    } Else {
				    $ScheduleStart = ""
				    $ScheduleEnd = ""
			    }
			    if ($migration.version -eq 2) {
                    if ($migration.progress.total.value -eq 0) {
                        $Progress = 0
                    } Else {$Progress = [math]::round((($migration.progress.total.bytesTransferred)/($migration.progress.total.value))*100)}
			    } Else {
                    $Progress = $migration.progress.percentComplete
			    }
                $tmp = [pscustomobject] @{
				    VM = $migration.entity.entityName;
				    ID = $migration.migrationId;
				    State = $migration.state;
				    Message = $migration.progress.message;
				    InitiatedBy = $migration.username;
                    Progress = $Progress;
				    CreateDate = $CreateTime;
				    LastUpdated = $UpdateTime;
				    ScheduleStartTime = $ScheduleStart;
				    ScheduleExpiryTime = $ScheduleEnd;
			    }
                $results+=$tmp
            }
            $results
        }
    }
}

Function Start-HcxMigrationAPI {
<#
    .NOTES
    ===========================================================================
    Created by:    William Lam
    Date:          09/24/2018
    Organization:  VMware
    Blog:          http://www.virtuallyghetto.com
    Twitter:       @lamw
    ===========================================================================
    Updated by:    Asaf Blubshtein
    Date:          06/01/2020
    Blog:          https://softwaredefinedcoffee.com/
    Twitter:       @AsafBlubshtein
	===========================================================================

    .SYNOPSIS
        Initiate a "Bulk" migration with or without guest customization. Cold migration, vMotion and RAV is not implemented at the moment.
    
	.DESCRIPTION
        This cmdlet initiates a "Bulk" migration with or without guest customization. Cold migration, vMotion and RAV are not implemented at the moment.
	
    .EXAMPLE
        Validate Migration request only:

        Start-HcxMigrationAPI  -VM $HCXVM -SourceHCX $SourceHCX -DestHCX $DestHCX `
			-TargetComputeContainer $TargetResPool -TargetFolder $TargetFolder  -TargetDatastore $TargetDS `
            -NetworkMapping $NetMap -SrcVCConnection $ViSession -ValidateOnly $true
    .EXAMPLE
        Start Migration request with guest customization:

        Start-HcxMigrationAPI  -VM $HCXVM -SourceHCX $SourceHCX -DestHCX $DestHCX `
			-TargetComputeContainer $TargetResPool -TargetFolder $TargetFolder  -TargetDatastore $TargetDS `
            -NetworkMapping $NetMap -ScheduleStartTime "April 25 2020 1:30 PM" -ScheduleEndTime "April 25 2020 2:30 PM" `
			-UpgradeVMTools $True -GuestCustomization $True  -GCNetCustomization $NetCustomization -GCName "host1.vmware.com"`
			 -DnsSuffix "vmware.com" -SrcVCConnection $ViSession -ValidateOnly $false
#>

    Param (
		[Parameter(Mandatory=$true)]$VM,
        [Parameter(Mandatory=$true)]$SourceHCX,
        [Parameter(Mandatory=$true)]$DestHCX,
		[Parameter(Mandatory=$true)]$TargetComputeContainer,
		[Parameter(Mandatory=$true)]$TargetFolder,
		[Parameter(Mandatory=$true)]$TargetDatastore,
		[Parameter(Mandatory=$true)]$NetworkMappings,
		[Parameter(Mandatory=$false)][ValidateSet("thin","thick","sameAsSource")][string]$DiskProvisionType="thin",
		[Parameter(Mandatory=$false)][bool]$UpgradeVMTools=$false,
		[Parameter(Mandatory=$false)][bool]$RemoveISOs=$false,
		[Parameter(Mandatory=$false)][bool]$ForcePowerOffVm=$false,
		[Parameter(Mandatory=$false)][bool]$RetainMac=$true,
		[Parameter(Mandatory=$false)][bool]$UpgradeHardware=$false,
		[Parameter(Mandatory=$false)][bool]$RemoveSnapshots=$false,
		[Parameter(Mandatory=$false)][String]$ScheduleStartTime="0",
        [Parameter(Mandatory=$false)][String]$ScheduleEndTime="0",
		[Parameter(Mandatory=$false)][bool]$ContinuosSync=$false,
		[Parameter(Mandatory=$false)][int]$syncInterval=120,
		[Parameter(Mandatory=$false)][bool]$ChangeSID =$false,
		[Parameter(Mandatory=$false)][String]$GCName="",
		[Parameter(Mandatory=$false)][String]$GCDomain ="",
		[Parameter(Mandatory=$false)]$GCNetCustomization,
        [Parameter(Mandatory=$false)][bool]$GuestCustomization=$false,
        [Parameter(Mandatory=$false)]$SrcVCConnection,
		[Parameter(Mandatory=$false)][bool]$ValidateOnly=$true
    )

    If (-Not $global:hcxConnection) { Write-error "HCX Auth Token not found, please run Connect-HcxServerAPI " } Else {
        $MigrationType = "vSphereReplication"
		If($ScheduleStartTime -ne "0") {
			[datetime]$EpochTime = '1970-01-01 00:00:00'
			try {
				$startDateTime = $ScheduleStartTime | Get-Date
			} catch {
				Write-Host -Foreground Red "Invalid input for -ScheduleStartTime, please check for typos"
				exit
			}
			try {
				$endDateTime = $ScheduleEndTime | Get-Date
			} catch {
				Write-Host -Foreground Red "Invalid input for -ScheduleEndTime, please check for typos"
				exit
			}
			
			$StartTime = ([math]::Floor((New-TimeSpan -Start $EpochTime -End $startDateTime.ToUniversalTime()).TotalMilliseconds))
			$ExpiryTime = ([math]::Floor((New-TimeSpan -Start $EpochTime -End $endDateTime.ToUniversalTime()).TotalMilliseconds))
		} Else {
			$StartTime = 0
			$ExpiryTime = 0
		}
		
		$inputArray = @()
        
        $entity = @{
			"entityId"=$VM.Id;
            "entityName"=$VM.Name;
			"entityType"="VirtualMachine";
		}

        If ($SrcVCConnection) {
            $vmView = Get-View -Server $SrcVCConnection -ViewType VirtualMachine -Filter @{"name"=$VM.Name}
			$summary = @{
					"guestFullName"=$vmView.Summary.Config.GuestFullName;
                    "guestId"=$vmView.Summary.Config.GuestId;
					"memorySizeMB"=$vmView.Summary.Config.MemorySizeMB;
                    "numCpu"=$vmView.Summary.Config.NumCpu;
                    "diskSize"=$(($vmView.Config.Hardware.Device | Measure-Object CapacityInKB -Sum).Sum*1024);
                    "memorySize"=$(($vmview.Summary.Config.MemorySizeMB)*1048576)
				}
            $entity.Add("summary",$summary)
		} 


		$transferProfileArray = @()
		$transferOption = @{
			"option"="removeIso";
			"value"=$RemoveISOs;
		}
		$transferProfileArray+=$transferOption
		$transferOption = @{
			"option"="removeSnapshot";
			"value"=$RemoveSnapshots;
		}
		$transferProfileArray+=$transferOption
		
		$switchoverTypeArray = @()
		$switchoverOption = @{
			"option"="retainMac";
			"value"=$RetainMac;
		}
		$switchoverTypeArray+=$switchoverOption
		$switchoverOption = @{
			"option"="forcePowerOffVm";
			"value"=$ForcePowerOffVm;
		}
		$switchoverTypeArray+=$switchoverOption
		$switchoverOption = @{
			"option"="upgradeHardware";
			"value"=$UpgradeHardware;
		}
		$switchoverTypeArray+=$switchoverOption
		$switchoverOption = @{
			"option"="upgradeVMTools";
			"value"=$UpgradeVMTools;
		}
		$switchoverTypeArray+=$switchoverOption
		
		$placementArray = @()
		$placement = @{
			"id"=$TargetComputeContainer.Id;
			"name"=$TargetComputeContainer.Name;
			"type"=$TargetComputeContainer.Type;
		}
		$placementArray+=$placement
		$placement = @{
			"id"=$TargetFolder.Id;
			"name"=$TargetFolder.Name;
			"type"=$TargetFolder.Type;
		}
		$placementArray+=$placement

		$netMappingsArray = @()
		foreach ($networkMap in $NetworkMappings) {
			$netMap = @{
				"srcNetworkType"=$networkMap.SourceNetworkType;
				"srcNetworkId"=$networkMap.SourceNetworkValue;
				"srcNetworkName"=$networkMap.SourceNetworkName;
				"destNetworkId"=$networkMap.DestinationNetworkValue;
				"destNetworkType"=$networkMap.DestinationNetworkType;
				"destNetworkName"=$networkMap.DestinationNetworkName;
			}
			$netMappingsArray+=$netMap
		}
		
		$input = @{
			
				"migrationType"=$MigrationType;
				"entity" = $entity;
				"source" = @{
					"endpointId"=$SourceHCX.EndpointId;
					"computeResourceId"=$SourceHCX.Id;
				}
				"destination" = @{
					"endpointId"=$DestHCX.EndpointId;
					"computeResourceId"=$DestHCX.Id;
				}
				"transferParams" = @{
					"transferType"=$MigrationType;
					"transferProfile"=$transferProfileArray
					"continuousSync" = $ContinuosSync;
					"syncInterval" = $SyncInterval;
					"schedule" =@{
						"startTime"=$StartTime;
						"expiryTime"=$ExpiryTime;
					}
				}
				"switchoverParams" = @{
					"switchoverType"=$MigrationType;
					"switchoverProfile"=$switchoverTypeArray;
					"schedule" =@{
						"startTime"=$StartTime;
						"expiryTime"=$ExpiryTime;
					}
				}
				"placement" = $placementArray
				"storage" = @{
					"defaultStorage"=@{
						"id"=$TargetDatastore.Id;
						"type"=$TargetDatastore.Type;
						"name"=$TargetDatastore.Name;
						"diskProvisionType"=$DiskProvisionType;
					}
				}
				"networkParams" = @{
					"defaultMappings" = $netMappingsArray;
				}
			
		}


        if ($GuestCustomization) {
            $netCustomArray = @()
			ForEach ($GCNetCust in $GCNetCustomization) {
                $Gateways = @() + $GCNetCust.Gateways
                $DnsServers = @() + $GCNetCust.DnsServers
                $netCust = @{
				    "macAddress"=$GCNetCust.MacAddress;
				    "ipAddress"=$GCNetCust.IpAddress;
				    "netmask"=$GCNetCust.NetMask;
				    "gateways"=$Gateways;
				    "dns"=$DnsServers;
				    "dnsSuffix"=$GCNetCust.DnsSuffix;
			    }
                $netCustomArray+=$netCust  
            }

			$guestCustom = @{
				"changeSID"=$ChangeSID;
				"networkCustomizations"=$netCustomArray;
				"identity"=@{
					"name"=$GCName;
					"domain"=$GCDomain;
				}
			}
            $input.Add("guestCustomization",$guestCustom)
		} 

		$inputArray+=$input
				

        $spec = @{
            "items"=$inputArray
        }
        $body = $spec | ConvertTo-Json -Depth 20

        Write-Verbose -Message "Pre-Validation JSON Spec: $body"
        $hcxMigrationValiateUrl = $global:hcxConnection.Server+ "/mobility/migrations/validate"
        $responseErr = ""
        $respBody = ""
        if($PSVersionTable.PSEdition -eq "Core") {
			try{
				$requests = Invoke-WebRequest -Uri $hcxMigrationValiateUrl -Body $body -Method POST -Headers $global:hcxConnection.headers -UseBasicParsing -ContentType "application/json" -SkipCertificateCheck -ErrorVariable responseErr
			}
			catch [System.Net.WebException] {
				$respStream = $_.Exception.Response.GetResponseStream()
				$reader = New-Object System.IO.StreamReader($respStream)
				$respBody = $reader.ReadToEnd() | ConvertFrom-Json
			}
        } else {
			try{
				$requests = Invoke-WebRequest -Uri $hcxMigrationValiateUrl -Body $body -Method POST -Headers $global:hcxConnection.headers -UseBasicParsing -ContentType "application/json" -ErrorVariable responseErr
			}
			catch [System.Net.WebException] {   
				$respStream = $_.Exception.Response.GetResponseStream()
				$reader = New-Object System.IO.StreamReader($respStream)
				$respBody = $reader.ReadToEnd() | ConvertFrom-Json
			}
        }

        if($requests.StatusCode -eq 202 -or $responseErr -like "*400*") {
			$validationErrors = $respBody.items.errors
			$validationWarnings = $respBody.items.warnings
            if($validationErrors -ne $null) {
                Write-Host -Foreground Red "`nThere were validation errors found for this HCX Migration Spec:"
                foreach ($message in $validationErrors) {
                    Write-Host -Foreground Red "`t" $message.message
                }
            } else {
				if($validationWarnings -ne $null) {
					Write-Host -Foreground Yellow "`nThere were validation warnings found for this HCX Migration Spec:"
					foreach ($message in $validationWarnings) {
						Write-Host -Foreground Yellow "`t" $message.message
					}
                }				
                Write-Host -Foreground Green "`nHCX Pre-Migration Spec successfully validated"
                if($ValidateOnly -eq $false) {

                    Write-Verbose -Message "Validated JSON Spec: $body"
                    $hcxMigrationStartUrl = $global:hcxConnection.Server+ "/mobility/migrations/start"

                    if($PSVersionTable.PSEdition -eq "Core") {
                        $requests = Invoke-WebRequest -Uri $hcxMigrationStartUrl -Body $body -Method POST -Headers $global:hcxConnection.headers -UseBasicParsing -ContentType "application/json" -SkipCertificateCheck
                    } else {
                        $requests = Invoke-WebRequest -Uri $hcxMigrationStartUrl -Body $body -Method POST -Headers $global:hcxConnection.headers -UseBasicParsing -ContentType "application/json"
                    }

                    if($requests.StatusCode -eq 202) {
                        $migrationItems = ($requests.Content | ConvertFrom-Json).items
                        Write-Host -ForegroundColor Green "Starting HCX Migration ..."
                        foreach ($migrationItem in $migrationItems) {
                            Write-Host -ForegroundColor Green "`tMigrationID:" $migrationItem.migrationId
                            $migrationItem
                        }
                    } else {
                        Write-Error "Failed to start HCX Migration"
                    }
                }
            }
        } else {
            Write-Error "Failed to validate HCX Migration spec"
        }
    }
}