# Lab 10: ASR Reporting and Monitoring

## Objective

Explore ASR diagnostic data in Log Analytics and build queries for replication health reporting.

## Prerequisites

- The environment is deployed (`azd up`) with the Log Analytics workspace (`drsandbox-law`) and vault diagnostic settings already configured.
- At least one VM is replicating via ASR (wait ~15 minutes after enabling replication for log data to appear).

## Steps

### 1. Verify Diagnostic Settings

1. Open the Recovery Services Vault (`drsandbox-rsv`) in the Azure Portal.
2. Navigate to **Monitoring** > **Diagnostic settings**.
3. Confirm a setting named `drsandbox-rsv-diag` exists, sending all log categories and metrics to the `drsandbox-law` workspace.

### 2. Open the Log Analytics Workspace

1. Navigate to **Log Analytics workspaces** > `drsandbox-law`.
2. Open **Logs** to access the KQL query editor.

### 3. Query ASR Replication Health

Run the following KQL query to view the latest replication health for each protected item:

```kql
AzureDiagnostics
| where Category == "AzureSiteRecoveryReplicatedItems"
| summarize arg_max(TimeGenerated, *) by replicationProtectedItemName_s
| project TimeGenerated,
          replicationProtectedItemName_s,
          replicationHealth_s,
          protectionState_s,
          lastSuccessfulTestFailoverTime_t
| order by replicationProtectedItemName_s asc
```

### 4. Query ASR Job History

Review recent ASR job outcomes:

```kql
AzureDiagnostics
| where Category == "AzureSiteRecoveryJobs"
| where TimeGenerated > ago(24h)
| project TimeGenerated,
          operationName_s,
          replicationProtectedItemName_s,
          resultType,
          resultDescription_s
| order by TimeGenerated desc
```

### 5. Query RPO Trends

Monitor recovery point objective adherence over time:

```kql
AzureDiagnostics
| where Category == "AzureSiteRecoveryReplicationStats"
| where TimeGenerated > ago(24h)
| project TimeGenerated,
          replicationProtectedItemName_s,
          rpoInSeconds_d
| order by TimeGenerated desc
| render timechart
```

### 6. Check Data Upload Rates

Observe replication data upload rates:

```kql
AzureDiagnostics
| where Category == "AzureSiteRecoveryReplicationDataUploadRate"
| where TimeGenerated > ago(24h)
| project TimeGenerated,
          replicationProtectedItemName_s,
          dataUploadRateInMBps_d
| order by TimeGenerated desc
```

### 7. Explore Built-in Workbooks (Optional)

1. In the Recovery Services Vault, navigate to **Monitoring** > **Workbooks**.
2. Open the **Azure Site Recovery** workbook to see pre-built dashboards for replication health, RPO, and job status.

## Expected Outcome

- Diagnostic settings are confirmed sending vault logs to Log Analytics.
- KQL queries return replication health, job history, RPO trends, and upload rates.
- You can identify which VMs have healthy replication and whether RPO targets are being met.
