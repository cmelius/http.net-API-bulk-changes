$apiKey = "<api-key>"
$targetIp = "<server-ip>"
$newTtl = 300 # 5 minutes
$testDomain = "<test-domain>"

$baseUrl = "https://partner.http.net/api/dns/v1/json"

function Invoke-HttpNetApi {
    param (
        [string]$Endpoint,
        [object]$Body
    )

    $url = "$baseUrl/$Endpoint"
    $jsonBody = $Body | ConvertTo-Json -Depth 10
    
    try {
        $response = Invoke-RestMethod -Uri $url -Method Post -Body $jsonBody -ContentType "application/json"
        return $response
    }
    catch {
        Write-Error "API Call failed: $_"
        return $null
    }
}

function Get-A-Records {
    param (
        [string]$IpFilter,
        [string]$DomainFilter
    )

    $body = @{
        authToken = $apiKey
        limit = 100
    }

    if ($DomainFilter) {
        $body.filter = @{
            field = "ZoneName"
            value = "*$DomainFilter*"
        }
    }

    $response = Invoke-HttpNetApi -Endpoint "zoneConfigsFind" -Body $body
    
    # The API returns data in response.data
    if ($response -and $response.response -and $response.response.data) {
        $allRecords = New-Object System.Collections.Generic.List[PSCustomObject]
        $zoneConfigs = $response.response.data
        Write-Host "DEBUG: Found $($zoneConfigs.Count) zone configurations." -ForegroundColor Gray
        
        foreach ($config in $zoneConfigs) {
            $zoneName = $config.name
            $zoneConfigId = $config.id
            Write-Host "DEBUG: Fetching records for zone: $zoneName (ID: $zoneConfigId)" -ForegroundColor Gray
            
            $recordBody = @{
                authToken = $apiKey
                filter = @{
                    field = "ZoneConfigId"
                    value = $zoneConfigId
                }
            }
            $recordResponse = Invoke-HttpNetApi -Endpoint "recordsFind" -Body $recordBody
            
            if ($recordResponse -and $recordResponse.response -and $recordResponse.response.data) {
                $records = $recordResponse.response.data
                Write-Host "DEBUG: Found $($records.Count) records in zone $zoneName." -ForegroundColor Gray
                foreach ($record in $records) {
                    $isA = $record.type -eq "A"
                    $matchesIp = ($null -eq $IpFilter) -or ($record.content -eq $IpFilter)
                    
                    if ($isA -and $matchesIp) {
                        $record | Add-Member -MemberType NoteProperty -Name "zoneName" -Value $zoneName
                        $allRecords.Add($record)
                    }
                }
            } else {
                Write-Host "DEBUG: No records found for $zoneName or error in recordResponse." -ForegroundColor Yellow
                if ($recordResponse) { Write-Host "DEBUG: Record Status: $($recordResponse.status)" -ForegroundColor Gray }
            }
        }
        return $allRecords
    }
    return @()
}

function Update-Record-Ttl {
    param (
        [array]$Records,
        [int]$Ttl
    )

    if ($Records.Count -eq 0) {
        Write-Host "No records to update."
        return
    }

    # The API requires updates to be scoped to a zoneName
    $groupedRecords = $Records | Group-Object -Property zoneName

    foreach ($group in $groupedRecords) {
        $zoneName = $group.Name
        Write-Host "Updating records for zone: $zoneName"
        
        $recordsToModify = foreach ($record in $group.Group) {
            # Debug: show properties once to be sure
            if ($null -eq $debugShown) {
                $propNames = ($record | Get-Member -MemberType NoteProperty).Name -join ', '
                Write-Host "DEBUG: First record properties: $propNames" -ForegroundColor Gray
                $debugShown = $true
            }

            @{
                id      = $record.id
                name    = $record.name
                type    = $record.type
                content = $record.content
                ttl     = $Ttl
            }
        }

        $body = @{
            authToken = $apiKey
            zoneName = $zoneName
            recordsToModify = $recordsToModify
        }

        $response = Invoke-HttpNetApi -Endpoint "recordsUpdate" -Body $body
        
        if ($response -and ($response.status -eq "success" -or $response.status -eq "pending")) {
            Write-Host "  Successfully updated $($group.Count) records in $zoneName (Status: $($response.status))." -ForegroundColor Green
        }
        else {
            Write-Host "  Failed to update records in ${zoneName}: $($response.status)" -ForegroundColor Red
            if ($response) {
                Write-Host "  Full Error Response: $($response | ConvertTo-Json -Depth 5)" -ForegroundColor Yellow
            } else {
                Write-Host "  API response was null." -ForegroundColor Yellow
            }
        }
    }
}

# --- Execution ---

Write-Host "--- Step 1: Testing with $testDomain ---"
$testRecords = Get-A-Records -DomainFilter $testDomain -IpFilter $targetIp

if ($testRecords.Count -gt 0) {
    Write-Host "Found $($testRecords.Count) A records for $testDomain pointing to $targetIp."
    Update-Record-Ttl -Records $testRecords -Ttl $newTtl
} else {
    Write-Host "No A records found for $testDomain pointing to $targetIp."
}

# Uncomment the block below to run for ALL domains with the target IP
<#
Write-Host "`n--- Step 2: Processing ALL domains for IP $targetIp ---"
$allRecords = Get-A-Records -IpFilter $targetIp
if ($allRecords.Count -gt 0) {
    Write-Host "Found $($allRecords.Count) A records pointing to $targetIp."
    Update-Record-Ttl -Records $allRecords -Ttl $newTtl
}
#>
