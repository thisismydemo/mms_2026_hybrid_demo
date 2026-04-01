# The Hybrid Update Blues — Demo Guide

## Detailed Demo Documentation by Slide

This document maps every demo to its corresponding slide(s), provides step-by-step walkthrough instructions, talking points, fallback plans, and environment prerequisites.

---

## Demo Overview

| Demo | Block | Slide(s) | Duration | Portal Blade / Tool |
|------|-------|----------|----------|---------------------|
| 1. Azure Update Manager Overview | Block 2 | Slide 13 (transition) → live | ~4 min | Azure Update Manager |
| 2. Arc Onboarding & Update Readiness | Block 3 | Slide 19 (transition) → live | ~3 min | Arc-enabled servers, Azure Resource Graph |
| 3. Azure Local Update Management | Block 4 | Slide 26 (transition) → live | ~4 min | Azure Update Manager → Azure Local |
| 4. Hotpatching | Block 6 | Slide 36 (transition) → live | ~3 min | Arc-enabled server, Hotpatch blade |
| 5. Compliance & Reporting | Block 9 | Slide 55 (transition) → live | ~3 min | Azure Policy, Resource Graph, Cost Analysis |

**Total demo time: ~17–18 minutes**

---

## Demo 1: Azure Update Manager Overview (~4 min)

### Corresponding Slides
- **Slide 8**: SECTION HEADER — "Azure Update Manager: The Single Pane"
- **Slide 9**: "What it is vs. what it isn't" — two-column comparison
- **Slide 10**: Azure Update Manager architecture diagram (orchestrator → extension → local update agent)
- **Slide 11**: Key capabilities overview with icons
- **Slide 12**: Pricing table — what's free, what costs money
- **Slide 13**: DEMO TRANSITION — Azure Update Manager Overview

### Pre-Demo Slide Context
Before going live, Slides 9–12 establish that Azure Update Manager is an orchestration layer (not a patch host), supports Azure VMs + Arc-enabled servers, and is free for Azure VMs but ~$5/month for Arc servers. The demo proves this isn't just marketing — it's a real unified view.

### Step-by-Step Walkthrough

**Step 1 — Open the Azure Update Manager blade (30 sec)**
- Navigate to **Azure portal → Azure Update Manager** (search bar or left nav)
- Talking point: "This is the single pane of glass. Everything — Azure VMs, Arc-enabled on-prem servers, Azure Local guest VMs — shows up here."

**Step 2 — Show the Machines view with filtering (45 sec)**
- Click **Machines** in the left nav
- Apply filter: **Resource type = Azure VM** → show the count
- Change filter: **Resource type = Arc-enabled server** → show the count
- Talking point: "Notice both resource types appear in the same blade. No separate tools, no separate dashboards. A server in your datacenter shows up right next to a VM in Azure."

**Step 3 — Show a maintenance configuration (60 sec)**
- Navigate to **Maintenance Configurations** in the left nav
- Open a pre-created maintenance configuration
- Point out:
  - **Schedule**: Recurrence (e.g., every month, second Tuesday, 10 PM)
  - **Classifications**: Which update categories are selected (e.g., Critical + Security)
  - **Reboot setting**: "If Required" vs. "Always" vs. "Never"
  - **Maintenance window duration**: How long the window is open
- Talking point: "This is the replacement for your WSUS approval workflow. Instead of manually approving KB articles, you define a schedule, pick your classifications, set your reboot behavior, and Azure Update Manager handles the rest."

**Step 4 — Show dynamic scoping with tag-based filtering (45 sec)**
- Within the same maintenance configuration, click **Dynamic Scopes**
- Show the tag filter (e.g., `UpdateRing = Ring1`)
- Talking point: "This is the magic. Tag a machine with `UpdateRing = Ring1`, and it automatically joins this schedule. Remove the tag, it drops out. No manual group management, no WSUS computer groups. Tags are your groups now."

**Step 5 — Show the compliance/assessment view (30 sec)**
- Navigate back to **Overview** or **Machines**
- Show the compliance summary: machines with pending updates, machines compliant, machines not assessed
- Talking point: "At a glance — how many machines are compliant, how many have pending updates, how many haven't been assessed recently. That last category is your canary — if a machine hasn't been assessed, its Arc agent might be unhealthy."

**Step 6 — Show update history for a specific machine (30 sec)**
- Click into a specific machine
- Navigate to **Update history**
- Show a recent update run: which KBs were installed, result (succeeded/failed), reboot status
- Talking point: "Full audit trail. Every patch, every result, every reboot. This is what your auditors want to see."

### Fallback Plan
- **If portal is slow/down**: Switch to pre-captured screenshots showing the same views. Have screenshots saved as a local PowerPoint slide deck backup.
- **If no machines appear**: Verify the subscription filter at the top of the portal. Ensure you're in the correct tenant.

### Environment Prerequisites
- [ ] At least 2 Azure VMs visible in Azure Update Manager
- [ ] At least 2 Arc-enabled servers visible in Azure Update Manager
- [ ] One maintenance configuration with a schedule, classifications, reboot setting, and at least one dynamic scope with tag-based filtering
- [ ] At least one machine with update history showing recent successful and/or failed update runs

---

## Demo 2: Arc Onboarding & Update Readiness (~3 min)

### Corresponding Slides
- **Slide 14**: SECTION HEADER — "Arc-Enabling Everything: The On-Ramp"
- **Slide 15**: Arc architecture diagram — on-prem server → Connected Machine agent → Azure Resource Manager
- **Slide 16**: Onboarding methods comparison (single, script, GPO, SCCM)
- **Slide 17**: "Before and after Arc" — what you can see and manage
- **Slide 18**: Arc agent health & AMA — auto-upgrades, agent vs. AMA distinction, heartbeat monitoring
- **Slide 19**: DEMO TRANSITION — Arc Onboarding & Update Readiness

### Pre-Demo Slide Context
Slides 15–18 explain that Arc projects on-prem servers into Azure as ARM resources, covers the onboarding methods, and distinguishes the Connected Machine agent from the Azure Monitor Agent. The demo shows what "it looks like Azure" actually means in practice.

### Step-by-Step Walkthrough

**Step 1 — Show an Arc-enabled server in the Azure portal (30 sec)**
- Navigate to **Azure Arc → Servers** (or search for the specific server name)
- Open the server's overview page
- Point out: Resource group, location (on-prem!), status (Connected), OS, last heartbeat
- Talking point: "This is a physical server sitting in my lab. But in Azure, it looks exactly like an Azure VM. Same RBAC, same tags, same policies apply to it."

**Step 2 — Show the Updates blade for this server (45 sec)**
- Click **Updates** in the left nav of the Arc server
- Show: Assessment results, list of recommended/pending updates, classifications
- Talking point: "Same Updates blade you saw on Azure VMs a minute ago. Same compliance data, same patch classifications. The experience is identical regardless of where the machine physically lives."

**Step 3 — Show Connected Machine agent version and auto-upgrade (30 sec)**
- Navigate to **Properties** or **Extensions** on the Arc server
- Show the agent version number
- Show auto-upgrade status (enabled/disabled)
- Talking point: "The Arc agent itself needs to stay current. Enable automatic upgrades — don't let it become another thing you have to manually patch."

**Step 4 — Show cross-resource maintenance configuration (30 sec)**
- Go back to **Azure Update Manager → Maintenance Configurations**
- Open the same maintenance configuration from Demo 1
- Show that both Azure VMs AND Arc-enabled servers are in scope (via dynamic scope or static assignment)
- Talking point: "One maintenance configuration, one schedule, covers both cloud and on-prem. This is the promise delivered."

**Step 5 — Show Azure Resource Graph query for cross-resource compliance (45 sec)**
- Navigate to **Azure Resource Graph Explorer**
- Run a pre-saved query that shows update compliance across both Azure VMs and Arc-enabled servers
- Example query output: machine name, resource type, OS, compliance status, pending update count
- Talking point: "This is the query your auditors will love. One query, every machine type, compliance status across your entire estate. Export to CSV, embed in a workbook, drop it in your executive dashboard."

### Fallback Plan
- **If the Arc server shows as Disconnected**: Acknowledge it — "This is actually a great example of what happens when the agent loses connectivity. Notice it says 'Disconnected' and the last heartbeat is stale. This is exactly the scenario we'll cover in the Graveyard Shift section."
- **If Resource Graph query fails**: Have the query results pre-captured as a screenshot.

### Environment Prerequisites
- [ ] At least one Arc-enabled server in "Connected" status with recent assessment data
- [ ] Connected Machine agent with auto-upgrade enabled
- [ ] A saved Azure Resource Graph query for cross-resource update compliance
- [ ] The maintenance configuration from Demo 1 should include Arc-enabled servers in its scope

---

## Demo 3: Azure Local Update Management (~4 min)

### Corresponding Slides
- **Slide 20**: SECTION HEADER — "Azure Local Cluster Updates: A Different Beast"
- **Slide 21**: "Azure Local is not a server" — the solution update stack diagram (OS → agents → services → SBE)
- **Slide 22**: Update type taxonomy — feature releases, cumulative, SBE
- **Slide 23**: Update flow diagram with rolling node updates
- **Slide 24**: "Don't do this" — list of unsupported update methods (WSUS, SCCM, manual Windows Update on nodes)
- **Slide 25**: Coordination matrix — what to update when, and what NOT to update at the same time
- **Slide 26**: DEMO TRANSITION — Azure Local Update Management

### Pre-Demo Slide Context
Slides 21–25 are critical setup. They establish that Azure Local is a *solution* (not just an OS), that the Lifecycle Manager orchestrates coordinated updates across OS + agents + services + OEM firmware/drivers (SBE), and that using WSUS/SCCM/manual Windows Update on cluster nodes is **unsupported**. The "Don't do this" slide (24) is the one people will photograph. The demo shows the supported path.

### Step-by-Step Walkthrough

**Step 1 — Navigate to Azure Local systems in Azure Update Manager (30 sec)**
- Open **Azure Update Manager** → filter or navigate to **Azure Local** systems
- Alternatively: **Azure Arc → Azure Local** → select a cluster → **Updates**
- Talking point: "Azure Local clusters appear in Azure Update Manager just like individual servers — but the update experience is fundamentally different. You're not patching individual nodes. You're applying a coordinated solution update across the entire stack."

**Step 2 — Show available solution updates and SBE status (60 sec)**
- On the cluster's update page, show:
  - **Available updates**: Feature release version (e.g., 2504), cumulative updates
  - **Solution Builder Extension (SBE) status**: OEM driver/firmware package availability
  - **Current version**: What the cluster is running now
- Talking point: "Notice there are multiple layers here — the Microsoft OS update and the OEM-specific SBE package. Both need to be available and compatible before you update. If your hardware vendor hasn't released the SBE yet, you wait. Don't force it."

**Step 3 — Show update readiness checks (45 sec)**
- Click into the update details or run readiness check
- Show: Health state prerequisites (cluster health, storage health, quorum status)
- Point out any warnings or prerequisites that must be met
- Talking point: "Always run readiness checks before starting an update. This validates cluster health, storage health, quorum, and SBE prerequisites. If anything is yellow or red here, stop. Fix it first. The number one cause of bricked clusters is skipping this step."

**Step 4 — Show update history — successful and failed runs (45 sec)**
- Navigate to **Update history**
- Show a successful update run: start time, end time, nodes updated, version applied
- If available, show a failed update run: error message, which node failed, what phase
- Talking point: "Full audit trail of every update run. When an update fails, look here first — the error message and the phase (download, install, post-install) tell you exactly where to start troubleshooting."

**Step 5 — Show the distinction between cluster infrastructure updates and guest VM updates (45 sec)**
- While still on the Azure Local cluster page, show the infrastructure update view
- Then navigate to a guest VM running on the cluster → show its individual **Updates** blade in Azure Update Manager
- Talking point: "This is the critical distinction. The cluster infrastructure update — OS, agents, firmware — is managed by the Lifecycle Manager. Guest VMs on the cluster are managed by Azure Update Manager individually, just like any other Arc-enabled server. These are two separate update paths, and they must NEVER run at the same time."

### Fallback Plan
- **If no Azure Local cluster is accessible**: Use pre-captured screenshots or a short screen recording showing the update blade, readiness checks, and update history. This is the most likely demo to need a fallback since not everyone has a live Azure Local cluster available.
- **If update history is empty**: Note that this is a freshly deployed cluster and show the available updates and readiness checks instead.

### Environment Prerequisites
- [ ] Azure Local cluster registered in Azure and visible in Azure Update Manager
- [ ] Cluster should have at least one available update (or recent update history)
- [ ] SBE status visible (even if current/no update needed)
- [ ] At least one guest VM on the cluster that is Arc-enabled and visible in Azure Update Manager separately
- [ ] Update history with at least one completed run (successful preferred; a failed run is a bonus for storytelling)

---

## Demo 4: Hotpatching (~3 min)

### Corresponding Slides
- **Slide 32**: SECTION HEADER — "Hotpatching: The Reboot Killer"
- **Slide 33**: Hotpatch calendar — which months are hotpatch vs. baseline, visualized across a year
- **Slide 34**: "Where it works" matrix — Azure VMs, Azure Local, Arc-enabled, with cost per scenario
- **Slide 35**: Enabling hotpatch — step-by-step with screenshots
- **Slide 36**: DEMO TRANSITION — Hotpatching

### Pre-Demo Slide Context
Slides 33–35 set up the value proposition: 8 months of no-reboot security patching, 4 months of baseline reboots (Jan/Apr/Jul/Oct). The calendar visual (Slide 33) is the hero — it makes the impact immediately obvious. Slide 34 covers where hotpatching works and what it costs ($1.50/core/month for Arc-enabled on-prem, free for Azure VMs and Azure Local VMs). The demo proves it's real and shows how to verify enrollment.

### Step-by-Step Walkthrough

**Step 1 — Show an Arc-enabled Windows Server 2025 machine (30 sec)**
- Navigate to the Arc-enabled server in the portal
- Point out: OS version (Windows Server 2025), Arc agent status (Connected)
- Talking point: "Hotpatching on-prem requires Windows Server 2025 and an Arc-enabled server. This is a physical server in my lab running Server 2025, connected to Azure via Arc."

**Step 2 — Show the Hotpatch enrollment status (30 sec)**
- Navigate to the server's **Updates** blade → **Hotpatch** section
- Show: Enrollment status (Enrolled / Not Enrolled)
- If enrolled, show the enrollment date
- Talking point: "Enrollment is a checkbox. Once you check it, hotpatch updates start being delivered automatically via Windows Update on the hotpatch-eligible months. The $1.50/core/month billing starts immediately."

**Step 3 — Show update history with hotpatch vs. baseline distinction (60 sec)**
- Navigate to **Update history** for this machine
- Identify and point out:
  - **Hotpatch months**: Updates installed with no reboot. Look for the "Hotpatch" label or the absence of a reboot event.
  - **Baseline months**: Updates that required a reboot (January, April, July, October)
- Talking point: "Look at the pattern. March — hotpatch, no reboot. February — hotpatch, no reboot. January — baseline, reboot required. That's 2 out of 3 months where this server stayed up continuously. Scale that across hundreds of servers and the operational impact is massive."

**Step 4 — Show the Hotpatch status column in Azure Update Manager machines view (30 sec)**
- Navigate back to **Azure Update Manager → Machines**
- Add or show the **Hotpatch status** column
- Show which machines are enrolled, which aren't
- Talking point: "At scale, you can see hotpatch enrollment across your entire fleet. This tells you which machines are getting the reboot reduction benefit and which aren't enrolled yet."

**Step 5 (Optional) — Show a hotpatch being applied (30 sec)**
- If timing works and a hotpatch is available, trigger an on-demand update
- Show that the update installs without prompting for a reboot
- Talking point: "No reboot dialog. No maintenance window anxiety. The patch is live in memory right now."

### Fallback Plan
- **If the machine isn't enrolled**: Walk through the enrollment process live — it's just checking a box, which is actually a good demo of simplicity.
- **If no update history shows hotpatch distinction**: Use a screenshot showing several months of update history with hotpatch vs. baseline labeled.
- **If the machine is an Azure VM (not Arc)**: Still show it — hotpatching is free on Azure VMs with Azure Edition, which demonstrates the feature even if the cost model is different.

### Environment Prerequisites
- [ ] At least one Windows Server 2025 machine (Standard or Datacenter) that is Arc-enabled
- [ ] Hotpatch enrollment enabled on the machine
- [ ] Several months of update history visible (to show the hotpatch vs. baseline pattern)
- [ ] VBS and Secure Boot enabled on the machine (prerequisites for hotpatching)

---

## Demo 5: Compliance & Reporting (~3 min)

### Corresponding Slides
- **Slide 51**: SECTION HEADER — "Compliance, Reporting & Cost Control"
- **Slide 52**: Unified compliance dashboard screenshot
- **Slide 53**: Sample Azure Resource Graph queries (copy-paste ready)
- **Slide 54**: Cost breakdown — what's free, what costs, where the hidden costs live
- **Slide 55**: DEMO TRANSITION — Compliance & Reporting

### Pre-Demo Slide Context
Slides 52–54 cover the reporting capabilities (Resource Graph, Policy, Workbooks), sample queries, and the cost model (Update Manager free for Azure VMs, $5/server/month for Arc, hidden Log Analytics ingestion costs). The demo ties it all together with live views.

### Step-by-Step Walkthrough

**Step 1 — Show Azure Update Manager compliance overview (45 sec)**
- Navigate to **Azure Update Manager → Overview**
- Show the compliance summary:
  - Percentage of machines compliant by resource type
  - Machines with pending critical/security updates
  - Machines not recently assessed
- Talking point: "This is your executive dashboard. Green means compliant, red means action needed. The 'not assessed' category is the sneaky one — those machines might be compliant, but you can't prove it because the agent isn't reporting."

**Step 2 — Show Azure Resource Graph query (60 sec)**
- Navigate to **Azure Resource Graph Explorer**
- Run a pre-saved query for machines with pending critical updates
- Show the results: machine name, resource type, OS, pending critical update count, last assessment time
- Talking point: "This is free. No Log Analytics required. Azure Resource Graph queries are included at no cost. This query runs across every subscription you have access to and gives you a compliance snapshot in seconds. Save it, schedule it, embed it in a workbook."
- Optionally show a second query: machines not assessed in the last 7 days (the "agent health canary")

**Step 3 — Show Azure Policy compliance for update-related policies (45 sec)**
- Navigate to **Azure Policy → Compliance**
- Filter for update-related policies (e.g., "Periodic assessment should be enabled," "System updates should be installed")
- Show compliance percentage and non-compliant resources
- Talking point: "Azure Policy isn't just for reporting — it's for enforcement. 'DeployIfNotExists' policies can automatically configure assessment on new machines. No manual intervention needed. And this compliance view is what your auditors want to see."

**Step 4 — Show cost analysis for Update Manager and Arc charges (30 sec)**
- Navigate to **Cost Management → Cost Analysis**
- Apply filter for Azure Update Manager or Arc-related charges
- Show the monthly cost breakdown
- Talking point: "Know what you're spending. Arc-enabled server management is about $5/server/month. Hotpatching adds $1.50/core/month. But the hidden cost killer is Log Analytics ingestion if you're piping everything there for reporting. Use Resource Graph first — it's free."

### Fallback Plan
- **If Resource Graph query returns no results**: Have a pre-captured screenshot of query results. Verify the query targets the correct subscriptions.
- **If Policy compliance data isn't populated**: Policy compliance can take 24+ hours to evaluate. Have screenshots ready.
- **If Cost Management isn't accessible**: This blade requires specific RBAC permissions. Have a screenshot of a sample cost view.

### Environment Prerequisites
- [ ] Azure Update Manager with multiple machines (mix of Azure VMs and Arc-enabled servers) showing compliance data
- [ ] At least one saved Azure Resource Graph query for update compliance
- [ ] Azure Policy assignments for update-related built-in policies with compliance data populated
- [ ] Cost Management accessible with visible Azure Update Manager / Arc charges (or screenshots)

---

## Master Demo Preparation Checklist

### Environment Setup (Complete 48+ Hours Before Session)
- [ ] Azure subscription with Contributor access to all demo resources
- [ ] At least 2 Azure VMs in Azure Update Manager with recent assessment data
- [ ] At least 2 Arc-enabled on-prem servers in "Connected" status
- [ ] One maintenance configuration with schedule, classifications, reboot setting, and tag-based dynamic scope
- [ ] Azure Local cluster registered and visible in Azure Update Manager with update history
- [ ] At least one guest VM on the Azure Local cluster, Arc-enabled and separately visible
- [ ] Windows Server 2025 machine with hotpatch enrolled and several months of history
- [ ] Azure Policy assignments for update-related policies, evaluated and showing compliance data
- [ ] Saved Azure Resource Graph queries (pending critical updates, machines not assessed in 7 days)
- [ ] Cost Management blade accessible with relevant charges visible

### Fallback Materials (Complete 24+ Hours Before Session)
- [ ] Screenshots of every demo step saved as backup slides in a separate PowerPoint file
- [ ] Short screen recordings (30–60 sec each) of the key demo moments as video fallback
- [ ] A "broken" scenario captured (disconnected Arc agent, WSUS GPO conflict, or Azure Local update failure) for Block 8 storytelling

### Day-Of Checks (Complete 30 Minutes Before Session)
- [ ] Verify Azure portal loads and all blades are accessible
- [ ] Verify Arc-enabled servers show "Connected" status
- [ ] Verify Azure Local cluster is healthy and accessible
- [ ] Verify Resource Graph queries return expected results
- [ ] Clear browser tabs — have only the portal open with bookmarks to each demo starting point
- [ ] Set browser zoom to 125–150% for audience visibility
- [ ] Disable browser notifications and OS notifications
- [ ] Test projector/screen share with the portal open

### Demo Flow Quick Reference

| Demo | Start Trigger | End Signal | Transition |
|------|--------------|------------|------------|
| 1. AUM Overview | After Slide 13 | "Now you've seen the tool — let's talk about how your on-prem servers get into it." | → Slides 14–18 (Arc) |
| 2. Arc & Readiness | After Slide 19 | "So that's how individual servers get managed. But Azure Local clusters? That's a different beast entirely." | → Slides 20–25 (Azure Local) |
| 3. Azure Local Updates | After Slide 26 | "Now let's talk about something everyone wants — fewer reboots." | → Slides 32–35 (Hotpatching) |
| 4. Hotpatching | After Slide 36 | "So we can patch smarter, reboot less — but can we prove it? Let's look at compliance." | → Slides 51–54 (Compliance) |
| 5. Compliance & Reporting | After Slide 55 | "That's the full picture — one control plane, many engines, full visibility." | → Slides 56+ (WSUS / Wrap-up) |
