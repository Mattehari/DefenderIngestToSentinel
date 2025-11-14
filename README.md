# Microsoft Defender for Endpoint → Sentinel Ingestion Estimator

Estimate **daily** and **period** data ingestion (MB/GB) for Microsoft Defender for Endpoint (MDE) tables when sending to **Microsoft Sentinel (Log Analytics)** or a **data lake**.  
The script samples real event rows via the **Advanced Hunting API**, measures **average record size** from CSV, and extrapolates **per‑table** and **aggregate** ingestion.

> ✅ **Use cases**
>
> *   Pre-sizing Sentinel ingestion costs before enabling MDE streaming
> *   Comparing ingestion by table to optimize table selection
> *   Estimating data lake footprint for exports

***

## ✨ Features

*   Secure authentication using **Client Secret** (converted to `SecureString`)
*   **Correct** JSON content type for the Defender API
*   **User-defined** lookback period (days)
*   **User-defined** sample size for `AvgRecordSizeKB` (with bounds)
*   Choice between sampling methods: **`take`** (first N) or **`sample`** (random N)
*   Calculates `AvgRecordSizeKB` from **actual CSV export**
*   Computes **daily** and **total** ingestion in **MB** and **GB**
*   Outputs:
    *   Sorted **table view** in the console
    *   **CSV** file with per-table details and totals

***

## 🧰 What it measures

For each Advanced Hunting table (default set below), the script:

1.  Counts **total events** in your lookback window
2.  Pulls a **sample** of records (CSV), measures file size, and computes **average record size (KB)**
3.  Calculates:
    *   `EstDailyEvents` = `TotalEvents / lookbackDays`
    *   `EstDailyMBIngested` and `EstTotalMBInLookback`
    *   `EstDailyGBIngested` and `EstTotalGBInLookback`
4.  Prints a **sorted table** and exports a **CSV** summary

**Default tables:**

    DeviceInfo
    DeviceNetworkEvents
    DeviceFileEvents
    DeviceProcessEvents
    DeviceRegistryEvents
    DeviceLogonEvents
    DeviceImageLoadEvents
    DeviceEvents
    DeviceNetworkInfo
    AlertInfo
    AlertEvidence

***

## ⚙️ Requirements

*   **PowerShell** 5.1+ (Windows) or PowerShell 7.x (cross‑platform)
*   PowerShell module: **MSAL.PS**
*   **Azure AD app registration** with:
    *   `ClientId` and **Client Secret**
    *   API permissions for Microsoft 365 Defender **Advanced Hunting**:
        *   **Application** permission: `AdvancedHunting.Read.All`
    *   Admin consent granted
*   Network egress to:
    *   `https://api.security.microsoft.com/` (Defender API)

***

## 🔐 Authentication

The script uses **client credentials flow**:

*   `TenantId`
*   `ClientId`
*   `ClientSecret` (converted securely from `plainSecret`)

Scope requested:

    https://api.security.microsoft.com/.default

> **Note:** The `.default` scope picks up the **application permissions** you granted in the Azure AD app registration.

***

## 📦 Installation

1.  **Clone** this repository (or download the script file):
    ```powershell
    git clone https://github.com/<your-org-or-user>/<your-repo>.git
    cd <your-repo>
    ```

2.  **Install** the MSAL.PS module (if not installed):
    ```powershell
    Install-Module MSAL.PS -Scope CurrentUser
    ```

3.  Ensure you have a **writable** output directory (defaults to `C:\MDE_IngestionEstimate`—configurable).

***

## 🛠️ Configuration

Open the script and edit the **CONFIGURE THESE** block:

```powershell
$TenantId    = "TENANTID"
$ClientId    = "CLIENTID"
$plainSecret = "SECRET"          # Will be converted to SecureString

# Output folder for samples and results
$OutputPath  = "C:\MDE_IngestionEstimate"

# Tables to test (modify as needed)
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
```

> You can add/remove tables depending on what you plan to **ingest into Sentinel** or export to a **data lake**.

***

## ▶️ Usage

Run the script and follow prompts:

```powershell
.\MDE_Ingestion_Estimator.ps1
```

You will be asked:

*   **Lookback days** (e.g., `7`)
*   **Sample size** (default `10000`, max `100000`)
*   **Sampling method**: `take` or `sample` (default `sample`)

**Recommended starting point**

*   Lookback: `7`–`14` days (smooths daily variance)
*   Sample size: `10000` (increase for more accuracy if API/time allows)
*   Method: `sample` (more representative than `take`)

***

## 📤 Output

*   **Console table**, sorted by `EstTotalGBInLookback` (descending)

*   **CSV file**:
        <OutputPath>\MDE_IngestionEstimate.csv
    with columns:
    *   `TableName`
    *   `EventsInLookback`
    *   `AvgRecordSizeKB`
    *   `EstDailyEvents`
    *   `EstDailyMBIngested`
    *   `EstTotalMBInLookback`
    *   `EstDailyGBIngested`
    *   `EstTotalGBInLookback`

*   **Summary block**:
    *   Lookback period and sampling settings
    *   **Totals across all tables** (MB and GB)

***

## 🎯 How the estimation works

1.  **Count events**  
    Uses:
    ```kusto
    <Table>
    | where Timestamp > ago(<lookbackDays>d)
    | summarize TotalEvents = count()
    ```

2.  **Measure average record size**
    *   Retrieves `<sampleSize>` rows via Advanced Hunting
    *   Exports to CSV
    *   Computes: `AvgRecordSizeKB = FileSizeKB / SampleRowCount`
    *   Falls back to **2.5 KB** per record if sampling/export fails (logged as warning)

3.  **Compute ingestion**
    *   **Daily events**: `TotalEvents / lookbackDays` (rounded)
    *   **MB/GB**: calculated from `AvgRecordSizeKB` × events

***

## 📌 Notes & Limits

*   **Sampling realism**: `sample` is more representative; `take` returns the **first** rows which may cluster in time or pattern.
*   **CSV size inflation**: CSV adds quotes, commas, and headers; this tends to **overestimate** record size slightly versus native ingestion. Use larger samples for stability.
*   **Daily shape**: If your telemetry is spiky (weekdays vs weekends), a longer lookback gives **better daily average**.
*   **API limits**: Advanced Hunting API has throttling—very large sample sizes across many tables may hit rate limits. Increase sample gradually if needed.
*   **Permissions**: Missing permission/consent produces **empty results** and warnings.
*   **Regionality**: Advanced Hunting queries operate on Defender XDR data; ensure your tenant and API access are enabled.

***

### 📊 Accuracy vs. Actual Sentinel Ingestion

The estimates produced by this script are based on **sampled CSV sizes** and event counts from the Microsoft 365 Defender Advanced Hunting API. While this provides a strong approximation, actual ingestion measured in **Sentinel’s Cost Analysis workbook** can differ due to:

*   **Serialization and compression** applied during ingestion
*   **Additional columns or enrichment** added by connectors
*   **Data shape variations** (e.g., spikes, weekends, or bursty workloads)

**Observed variance:**

*   Typically around **±10%** compared to Sentinel’s reported ingestion
*   In some cases, differences can range between **10–20%**, especially for tables with highly variable record sizes or when using small sample sizes

> ✅ **Recommendation:** Use this script for **planning and sizing**, but validate with Sentinel’s **Cost Analysis workbook** after enabling ingestion for a few days to fine-tune estimates.

***

## 🧪 Examples

**Estimate for 14 days with 20k random samples**

    Enter the number of days to look back for estimation (e.g., 7): 14
    Enter the number of records to sample for AvgRecordSizeKB (default 10000, max 100000): 20000
    Choose sampling method for AvgRecordSizeKB: 'take' or 'sample' (default 'sample'):

**Narrow focus to a few noisy tables**  
Edit `$Tables` to:

```powershell
$Tables = @(
  "DeviceProcessEvents",
  "DeviceNetworkEvents",
  "DeviceFileEvents"
)
```

***

## 🧯 Troubleshooting

*   **`API call failed` warnings**
    *   Check app permissions (`AdvancedHunting.Read.All`) and **admin consent**
    *   Verify `TenantId`, `ClientId`, and **secret** are correct
    *   Confirm outbound access to `https://api.security.microsoft.com/`

*   **No data found for table**
    *   The tenant may not produce that table in the selected period
    *   Use a **longer lookback** or smaller table set

*   **CSV export errors / access denied**
    *   Ensure `$OutputPath` exists and is writable
    *   Avoid paths requiring elevated privileges

*   **Sampling too slow / timeouts**
    *   Reduce `sampleSize` or the number of tables
    *   Prefer `sample` (random) over `take` for representativeness with fewer rows

***

## 🔒 Security Considerations

*   Store secrets securely—avoid committing `plainSecret` to source control
*   Prefer reading secrets from:
    *   Environment variables
    *   Local vault (e.g., Windows Credential Manager, SecretManagement)
    *   Azure Key Vault (if running in Azure contexts)
*   Limit app permissions to **minimum necessary**

***

## 🧭 Roadmap ideas (optional)

*   Add **environment variable** and **Key Vault** secret providers
*   Add **progress bar** and timing metrics
*   Support **parallelization** per table (with throttle control)
*   Output **JSON** alongside CSV for automation
*   Option to **exclude** specific columns when exporting CSV (reduce inflation)

***

## ⚖️ Disclaimer

This is an **estimator**. Actual Sentinel ingestion depends on:

*   Connector payloads and transformations
*   Log Analytics serialization and compression
*   Enrichment/expanded columns at ingestion time
*   Changes in workload over time

Use this as a **planning tool**, not as a contractual meter.

***

### Quick Start (TL;DR)

```powershell
Install-Module MSAL.PS -Scope CurrentUser

# Edit TenantId / ClientId / plainSecret / OutputPath / Tables in the script
.\MDE_Ingestion_Estimator.ps1

# Provide:
# - Lookback days (e.g., 7–14)
# - Sample size (e.g., 10000)
# - Sampling method (press Enter for 'sample')
```

***