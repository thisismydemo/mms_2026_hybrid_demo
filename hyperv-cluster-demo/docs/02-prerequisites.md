# 02 — Prerequisites

Complete every item in this document **before** triggering workflow `hvlab-01-host-vm.yml`. A missing prerequisite will cause a workflow to fail partway through, potentially leaving orphaned resources.

---

## 1. Azure Access

### Required Permissions

| Scope | Role |
|-------|------|
| Subscription `00cd4357-ed45-4efb-bee0-10c467ff994b` | `Contributor` (for resource group creation and VM deployment) |
| Subscription | `User Access Administrator` (only if you need to assign RBAC) |
| Key Vault (see below) | `Key Vault Secrets Officer` |

### Verify CLI Access

```powershell
az login
az account set --subscription "00cd4357-ed45-4efb-bee0-10c467ff994b"
az account show --query "{name:name, id:id, state:state}"
```

Confirm the subscription ID matches `00cd4357-ed45-4efb-bee0-10c467ff994b` and state is `Enabled`.

---

## 2. Resource Group

The resource group must exist before deployment. Create it if needed:

```powershell
az group create `
  --name "rg-hvlab-mms26-eus-01" `
  --location "eastus" `
  --tags "project=mms2026" "environment=lab" "owner=hvlab-team"
```

> **Naming note**: `rg-hvlab-mms26-eus-01` follows Azure CAF naming convention: `rg` (resource type) `-hvlab` (workload) `-mms26` (project) `-eus` (East US) `-01` (instance).

---

## 3. Key Vault — Pre-Stage Secrets

All sensitive values are read from Azure Key Vault at deployment time. The Key Vault must exist and contain all 9 secrets listed below **before** running workflow 01.

### Create the Key Vault (if it doesn't exist)

```powershell
az keyvault create `
  --name "kv-hvlab-mms26-eus-01" `
  --resource-group "rg-hvlab-mms26-eus-01" `
  --location "eastus" `
  --sku standard `
  --enable-rbac-authorization true
```

### Assign Secret Access to the Deployment Identity

```powershell
$KV_ID = az keyvault show `
  --name "kv-hvlab-mms26-eus-01" `
  --query id -o tsv

az role assignment create `
  --role "Key Vault Secrets Officer" `
  --assignee "<your-service-principal-or-upn>" `
  --scope $KV_ID
```

### Required Secrets (all 9)

| Secret Name | Description | Example Format |
|-------------|-------------|----------------|
| `hvlab-host-admin-username` | Local admin username for host VM | `hvadmin` |
| `hvlab-host-admin-password` | Local admin password for host VM | Min 12 chars, complexity required |
| `hvlab-domain-admin-username` | `azrl.mgmt` domain admin UPN | `svc-hvlab-deploy@azrl.mgmt` |
| `hvlab-domain-admin-password` | Domain admin password | — |
| `hvlab-svcaccount-password` | Shared password for all `svc-*` service accounts | — |
| `hvlab-sqlsa-password` | SQL Server SA password for SCVMM SQL instance | Min 12 chars, complexity required |
| `hvlab-scvmm-product-key` | SCVMM 2025 product key (or `EVAL` for trial) | `XXXXX-XXXXX-XXXXX-XXXXX-XXXXX` |
| `hvlab-witness-storage-key` | Access key for `sthvlabwitness01` blob storage account | Base64 key string |
| `hvlab-github-runner-token` | GitHub Actions runner registration token | `AXXXXXXXXXXXXXXXXXX` (see section 4) |

### Set Each Secret

```powershell
az keyvault secret set `
  --vault-name "kv-hvlab-mms26-eus-01" `
  --name "hvlab-host-admin-username" `
  --value "hvadmin"

az keyvault secret set `
  --vault-name "kv-hvlab-mms26-eus-01" `
  --name "hvlab-host-admin-password" `
  --value "<your-secure-password>"

# Repeat for all 9 secrets
```

### Verify All Secrets Are Present

```powershell
$secrets = @(
  "hvlab-host-admin-username",
  "hvlab-host-admin-password",
  "hvlab-domain-admin-username",
  "hvlab-domain-admin-password",
  "hvlab-svcaccount-password",
  "hvlab-sqlsa-password",
  "hvlab-scvmm-product-key",
  "hvlab-witness-storage-key",
  "hvlab-github-runner-token"
)

foreach ($s in $secrets) {
    $result = az keyvault secret show `
        --vault-name "kv-hvlab-mms26-eus-01" `
        --name $s `
        --query "name" -o tsv 2>$null
    if ($result) {
        Write-Host "✓ $s" -ForegroundColor Green
    } else {
        Write-Host "✗ $s  ← MISSING" -ForegroundColor Red
    }
}
```

---

## 4. GitHub Runner Token

The self-hosted runner is installed on the host VM by workflow `hvlab-02-runner-bootstrap.yml`. A runner registration token is required and is **short-lived (1 hour)**.

### Generate the Token

1. In GitHub, go to the repository → **Settings** → **Actions** → **Runners** → **New self-hosted runner**
2. Copy the token from the `--token` parameter in the configuration command shown
3. Immediately store it in Key Vault:

```powershell
az keyvault secret set `
  --vault-name "kv-hvlab-mms26-eus-01" `
  --name "hvlab-github-runner-token" `
  --value "<RUNNER_TOKEN>"
```

> **Timing**: Generate this token immediately before running workflow 02. If more than 1 hour passes, generate a new token and update the secret.

The runner will register with label `hvlab-host`. All workflows from step 03 onward use `runs-on: [self-hosted, hvlab-host]`.

---

## 5. GitHub Repository Secrets

These four secrets must be set in the GitHub repository before any workflow can authenticate to Azure.

Navigate to: **Repository → Settings → Secrets and variables → Actions → New repository secret**

| Secret Name | Value |
|-------------|-------|
| `AZURE_CLIENT_ID` | Service principal Application (client) ID |
| `AZURE_TENANT_ID` | Azure AD tenant ID |
| `AZURE_SUBSCRIPTION_ID` | `00cd4357-ed45-4efb-bee0-10c467ff994b` |
| `AZURE_CLIENT_SECRET` | Service principal client secret |

### Create the Service Principal (if needed)

```powershell
az ad sp create-for-rbac `
  --name "sp-hvlab-mms26-github" `
  --role "Contributor" `
  --scopes "/subscriptions/00cd4357-ed45-4efb-bee0-10c467ff994b/resourceGroups/rg-hvlab-mms26-eus-01" `
  --sdk-auth
```

The output JSON contains all four values. Store them in the GitHub secrets listed above.

---

## 6. ISO Files

The nested VM creation scripts require Windows Server ISO files accessible from the host VM. Upload them to an Azure Blob container that the host VM's managed identity can read.

| ISO | Version | Notes |
|-----|---------|-------|
| `WS2022_SERVER_EVAL_x64FRE_en-us.iso` | Windows Server 2022 Evaluation | [Download from Microsoft Evaluation Center](https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2022) |
| `WS2025_SERVER_EVAL_x64FRE_en-us.iso` | Windows Server 2025 Evaluation | [Download from Microsoft Evaluation Center](https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2025) — **Required for hvwac01** |

### Upload to Blob Storage

```powershell
# Create storage account and container for ISOs
az storage account create `
  --name "sthvlabisomms26" `
  --resource-group "rg-hvlab-mms26-eus-01" `
  --location "eastus" `
  --sku Standard_LRS

az storage container create `
  --name "isos" `
  --account-name "sthvlabisomms26"

# Upload ISOs
az storage blob upload `
  --account-name "sthvlabisomms26" `
  --container-name "isos" `
  --name "WS2022_SERVER_EVAL_x64FRE_en-us.iso" `
  --file "C:\ISOs\WS2022_SERVER_EVAL_x64FRE_en-us.iso"

az storage blob upload `
  --account-name "sthvlabisomms26" `
  --container-name "isos" `
  --name "WS2025_SERVER_EVAL_x64FRE_en-us.iso" `
  --file "C:\ISOs\WS2025_SERVER_EVAL_x64FRE_en-us.iso"
```

---

## 7. Cloud Witness Storage Account

The Failover Cluster uses Azure Blob Storage as a Cloud Witness. The storage account must exist before cluster formation.

```powershell
az storage account create `
  --name "sthvlabwitness01" `
  --resource-group "rg-hvlab-mms26-eus-01" `
  --location "eastus" `
  --sku Standard_LRS `
  --kind StorageV2 `
  --access-tier Hot `
  --min-tls-version TLS1_2
```

Retrieve the access key and store it in Key Vault:

```powershell
$key = az storage account keys list `
  --account-name "sthvlabwitness01" `
  --resource-group "rg-hvlab-mms26-eus-01" `
  --query "[0].value" -o tsv

az keyvault secret set `
  --vault-name "kv-hvlab-mms26-eus-01" `
  --name "hvlab-witness-storage-key" `
  --value $key
```

---

## 8. Domain Credentials

The deployment scripts join the host VM and all nested VMs to `azrl.mgmt`. The account used must have permission to join computers to the domain.

| Requirement | Detail |
|-------------|--------|
| Domain | `azrl.mgmt` |
| Existing DCs | `10.250.1.36` and `10.250.1.37` |
| Account needed | An account with **Delegate control** to join computers to the target OUs (see [`docs/05-active-directory.md`](05-active-directory.md)) |
| Stored as | `hvlab-domain-admin-username` and `hvlab-domain-admin-password` in Key Vault |

> **Do not use the default `Domain Admins` account** for automated deployment. Use the dedicated `svc-hvlab-deploy` service account with scoped delegation.

---

## 9. Networking Pre-Checks

Verify the existing VNet and subnet are in place and have capacity:

```powershell
# Confirm VNet exists
az network vnet show `
  --name "vnet-lab-prodtech-eus-connectivity-hub" `
  --resource-group "rg-hvlab-mms26-eus-01" `
  --query "{name:name, addressSpace:addressSpace.addressPrefixes}"

# Confirm subnet exists
az network vnet subnet show `
  --name "snet-lab-prodtech-eus-connectivity-mgmt" `
  --vnet-name "vnet-lab-prodtech-eus-connectivity-hub" `
  --resource-group "rg-hvlab-mms26-eus-01" `
  --query "{name:name, prefix:addressPrefix, available:availableIpAddressCount}"
```

Confirm that IPs `10.250.1.45`, `10.250.1.46`, and `10.250.1.47` are not already allocated.

```powershell
# Check each IP
foreach ($ip in @("10.250.1.45","10.250.1.46","10.250.1.47")) {
    $result = az network nic list `
        --query "[?contains(ipConfigurations[].privateIPAddress, '$ip')].[name]" `
        -o tsv
    if ($result) {
        Write-Host "✗ $ip is already in use: $result" -ForegroundColor Red
    } else {
        Write-Host "✓ $ip is available" -ForegroundColor Green
    }
}
```

---

## 10. Pre-Flight Checklist Summary

Use this checklist as a final gate before running workflow 01:

- [ ] Azure subscription access confirmed (`az account show`)
- [ ] Resource group `rg-hvlab-mms26-eus-01` exists
- [ ] Key Vault `kv-hvlab-mms26-eus-01` exists with all 9 secrets set
- [ ] GitHub repo secrets set: `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `AZURE_CLIENT_SECRET`
- [ ] WS2022 ISO uploaded to `sthvlabisomms26/isos`
- [ ] WS2025 ISO uploaded to `sthvlabisomms26/isos`
- [ ] Storage account `sthvlabwitness01` created
- [ ] IPs `10.250.1.45`, `.46`, `.47` confirmed available
- [ ] VNet `vnet-lab-prodtech-eus-connectivity-hub` and subnet `snet-lab-prodtech-eus-connectivity-mgmt` confirmed existing
- [ ] Domain admin account `svc-hvlab-deploy@azrl.mgmt` created with scoped OU delegation
- [ ] GitHub runner token generated (≤1 hour before running workflow 02)
