<# 
    Microsoft Defender for Endpoint → Sentinel Ingestion Estimator
    Features:
      - Secure ClientSecret
      - Correct JSON Content-Type
      - User-defined lookback period
      - User-defined sample size for AvgRecordSizeKB
      - Choice between 'take' and 'sample'
      - Calculates AvgRecordSizeKB by actual CSV export
      - Calculates daily/total MB and GB ingestion
      - Outputs CSV and table
#>

# ======== CONFIGURE THESE ========
$TenantId   = "TENANTID"
$ClientId   = "CLIENTID"
$plainSecret = "SECRET"   # Will be converted to SecureString

# Output folder for samples
$OutputPath = "C:\MDE_IngestionEstimate"
New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null

# Tables to test
$Tables = @(
    "DeviceInfo",
    "DeviceNetworkEvents",
    "DeviceFileEvents",
    "DeviceProcessEvents",
    "DeviceRegistryEvents",
    "DeviceLogonEvents",
    "DeviceImageLoadEvents",
    "DeviceEvents",
    "DeviceNetworkInfo",
    "AlertInfo",
    "AlertEvidence"
)

# ======== USER INPUT ========
$lookbackDays = Read-Host "Enter the number of days to look back for estimation (e.g., 7)"
[int]$lookbackDays = [Math]::Max(1, [int]$lookbackDays)
$lookbackPeriod = "ago($lookbackDays" + "d)"

$sampleSize = Read-Host "Enter the number of records to sample for AvgRecordSizeKB (default 10000, max 100000)"
if ([string]::IsNullOrWhiteSpace($sampleSize)) { $sampleSize = 10000 }
[int]$sampleSize = [Math]::Min([Math]::Max(1, [int]$sampleSize), 100000)

# Choice between 'take' or 'sample'
$sampleMethod = Read-Host "Choose sampling method for AvgRecordSizeKB: 'take' or 'sample' (default 'sample')"
if ([string]::IsNullOrWhiteSpace($sampleMethod)) { $sampleMethod = "sample" }
$sampleMethod = $sampleMethod.ToLower()
if ($sampleMethod -ne "take" -and $sampleMethod -ne "sample") { $sampleMethod = "sample" }

Write-Host "`nLookback period: $lookbackDays days"
Write-Host "Sample size per table: $sampleSize records"
Write-Host "Sampling method: $sampleMethod`n"

# ======== AUTHENTICATION ========
Import-Module MSAL.PS -ErrorAction Stop
Write-Host "Authenticating to Microsoft 365 Defender API..." -ForegroundColor Cyan

$ClientSecret = ConvertTo-SecureString $plainSecret -AsPlainText -Force

$token = Get-MsalToken -TenantId $TenantId `
                        -ClientId $ClientId `
                        -ClientSecret $ClientSecret `
                        -Scopes "https://api.security.microsoft.com/.default"

$headers = @{ Authorization = "Bearer $($token.AccessToken)" }

# ======== FUNCTION TO INVOKE API ========
function Invoke-AdvancedHuntingQuery {
    param($Query)
    $uri = "https://api.security.microsoft.com/api/advancedhunting/run"
    $body = @{ Query = $Query } | ConvertTo-Json -Compress

    try {
        $response = Invoke-RestMethod -Method POST `
                                      -Uri $uri `
                                      -Headers $headers `
                                      -Body $body `
                                      -ContentType "application/json"
        return $response.Results
    } catch {
        Write-Warning "API call failed: $_"
        return @()
    }
}

# ======== MAIN PROCESS ========
$results = @()

foreach ($table in $Tables) {
    Write-Host "`nProcessing table: $table" -ForegroundColor Yellow

    # --- 1️⃣ Total events in lookback period ---
    $countQuery = "$table | where Timestamp > $lookbackPeriod | summarize TotalEvents = count()"
    try {
        $countResult = Invoke-AdvancedHuntingQuery -Query $countQuery
        $totalEvents = [int64]($countResult.TotalEvents)
    } catch {
        Write-Warning "Failed to get count for $table : $_"
        continue
    }

    if ($totalEvents -eq 0 -or $null -eq $totalEvents) {
        Write-Host "No data found for $table in lookback period." -ForegroundColor DarkGray
        continue
    }

    # --- 2️⃣ Sample rows to measure AvgRecordSizeKB ---
    $sampleQuery = "$table | where Timestamp > $lookbackPeriod | $sampleMethod $sampleSize"
    $sampleFile = Join-Path $OutputPath "$table-sample.csv"

    try {
        $sampleResult = Invoke-AdvancedHuntingQuery -Query $sampleQuery
        $sampleCount = [Math]::Max(1, $sampleResult.Count)

        # Export to CSV
        $sampleResult | Export-Csv -Path $sampleFile -NoTypeInformation -Force

        # Measure file size
        $fileSizeKB = (Get-Item $sampleFile).Length / 1024

        # Calculate AvgRecordSizeKB based on CSV
        $avgRecordKB = [Math]::Round($fileSizeKB / $sampleCount, 2)
    } catch {
        Write-Warning "Failed to export sample for $table : $_"
        $avgRecordKB = 2.5  # fallback default
    }

    # --- 3️⃣ Estimate daily and total ingestion ---
    $dailyEvents = [math]::Round(($totalEvents / $lookbackDays), 0)

    # MB calculations
    $dailyMB = [Math]::Round(($dailyEvents * $avgRecordKB) / 1024, 2)
    $totalMB = [Math]::Round(($totalEvents * $avgRecordKB) / 1024, 2)

    # GB calculations
    $estimatedGB = [Math]::Round($dailyMB / 1024, 2)
    $totalGB = [Math]::Round($totalMB / 1024, 2)

    $results += [PSCustomObject]@{
        TableName               = $table
        EventsInLookback        = $totalEvents
        AvgRecordSizeKB         = $avgRecordKB
        EstDailyEvents          = $dailyEvents
        EstDailyMBIngested      = $dailyMB
        EstTotalMBInLookback    = $totalMB
        EstDailyGBIngested      = $estimatedGB
        EstTotalGBInLookback    = $totalGB
    }
}

# ======== OUTPUT ========
$results | Sort-Object EstTotalGBInLookback -Descending | Format-Table -AutoSize

# Export results to CSV
$csvPath = Join-Path $OutputPath "MDE_IngestionEstimate.csv"
$results | Export-Csv -NoTypeInformation -Path $csvPath
Write-Host "`nEstimation complete! Results exported to $csvPath" -ForegroundColor Green

# ======== SUMMARY MESSAGE ========
$totalMBAllTables = [Math]::Round(($results | Measure-Object -Property EstTotalMBInLookback -Sum).Sum, 2)
$totalGBAllTables = [Math]::Round(($results | Measure-Object -Property EstTotalGBInLookback -Sum).Sum, 2)

Write-Host "`n=============================================================" -ForegroundColor Cyan
Write-Host "Output is based on the timeperiod: $lookbackDays days" -ForegroundColor Cyan
Write-Host "Sample method: $sampleMethod, Sample size per table: $sampleSize records" -ForegroundColor Cyan
Write-Host "Total estimated ingestion across all tables:" -ForegroundColor Cyan
Write-Host "  MB: $totalMBAllTables MB" -ForegroundColor Cyan
Write-Host "  GB: $totalGBAllTables GB" -ForegroundColor Cyan
Write-Host "=============================================================`n" -ForegroundColor Cyan
