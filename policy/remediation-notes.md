# Remediation Notes

Known issues and tips for policy remediation in the demo environment.

## Common Remediation Issues

### 1. Remediation task stuck in "Evaluating"
- **Cause**: Managed identity for the policy assignment lacks permissions
- **Fix**: Ensure the assignment has a system-managed identity with Contributor role on the scope

### 2. Arc server shows non-compliant after remediation
- **Cause**: Arc agent is disconnected — policy can't deploy the extension
- **Fix**: Reconnect the Arc agent, then re-trigger evaluation

### 3. Assessment shows "Not assessed" even after policy assignment
- **Cause**: The periodic assessment extension hasn't run its first cycle (up to 24 hours)
- **Fix**: Trigger an on-demand assessment:
  ```bash
  az vm assess-patches --resource-group <rg> --name <vm>
  # or for Arc servers
  az connectedmachine assess-patches --resource-group <rg> --name <machine>
  ```

### 4. DINE policy doesn't apply to existing resources
- **Cause**: DeployIfNotExists only triggers on new deployments by default
- **Fix**: Create a remediation task for existing resources:
  ```bash
  az policy remediation create \
      --name "remediate-periodic-assessment" \
      --policy-assignment "periodic-update-check" \
      --resource-group <rg>
  ```

## Demo-Specific Notes

- Remediation tasks take 5-15 minutes to complete — start them early in the session
- If time is tight, run remediation ahead of time and show "completed" status
- Keep screenshots in `assets/screenshots/` as fallback
