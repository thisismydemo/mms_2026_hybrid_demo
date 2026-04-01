# Built-in Azure Policy Reference for Update Management

Azure Policy definitions used in the Hybrid Update Blues demo.

## Guest Configuration / Update Management Policies

| Policy Name | Definition ID | Scope | Effect |
|---|---|---|---|
| Configure periodic checking for missing system updates | `/providers/Microsoft.Authorization/policyDefinitions/59efceea-0c96-497e-a4a1-4eb2290dac15` | Subscription | DeployIfNotExists |
| Machines should be configured to periodically check for missing updates | `/providers/Microsoft.Authorization/policyDefinitions/bd876905-5b84-4f73-ab2d-2e7a7c4568d9` | Subscription | Audit |
| Schedule recurring updates using Azure Update Manager | `/providers/Microsoft.Authorization/policyDefinitions/ba0df93e-e4ac-479a-aac2-134bbae39a12` | Subscription | DeployIfNotExists |
| [Preview]: Machines should be configured to check for missing system updates on a daily basis | `/providers/Microsoft.Authorization/policyDefinitions/a]` | Subscription | Audit |

## Arc-Specific Policies

| Policy Name | Description |
|---|---|
| Configure Arc-enabled servers to install the Azure Monitor agent | Ensures Arc servers have the AMA extension |
| Configure Windows Arc-enabled machines to run Azure Monitor Agent | Windows-specific AMA deployment |

## How to Assign

```bash
# Assign the periodic-checking policy at subscription scope
az policy assignment create \
    --name "periodic-update-check" \
    --scope "/subscriptions/<subscription-id>" \
    --policy "/providers/Microsoft.Authorization/policyDefinitions/59efceea-0c96-497e-a4a1-4eb2290dac15" \
    --mi-system-assigned \
    --location "eastus"
```

## Demo Tips

- Show the Azure Policy → Compliance blade to demonstrate compliance percentages
- Filter by "Update" to find all update-related policies
- Demonstrate the difference between Audit and DeployIfNotExists effects
- Show remediation tasks for non-compliant resources
