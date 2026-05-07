# Platform Roadmap

This document captures the path from the current MMS 2026 Hyper-V cluster demo to a more customizable, repeatable lab platform that can grow beyond the conference scenario.

## Vision

Evolve the current demo into a parameter-driven lab platform that can:

- deploy a repeatable Hyper-V or Azure Local style lab in multiple environments
- support multiple identity and management models
- scale up or down based on hardware capacity and scenario goals
- separate platform plumbing from scenario-specific demo content

## Why This Should Become Its Own Repo

The current `hyperv-cluster-demo` folder is still a conference demo artifact. If the scope expands into a reusable platform, it should move into a dedicated repository for three reasons:

1. The code will stop being conference-specific and start needing product-like versioning.
2. The configuration surface will grow well beyond a single MMS scenario.
3. Demo scripts, platform engine, environment profiles, and scenario packs should be versioned independently.

Recommended approach:

- keep the current repo focused on the MMS 2026 implementation
- incubate the platform roadmap here for now
- cut a new repo once the configuration model and deployment target model are defined

## Core Design Principles

- configuration first: the lab shape should come from a manifest, not from hard-coded script assumptions
- environment portable: the same logical lab should target Azure, nested virtualization, or physical hardware
- opinionated defaults: common lab shapes should work without forcing users to answer 50 questions
- modular roles: identity, storage, cluster, and management roles should be independently composable
- scenario overlays: Azure Local, Hyper-V cluster, WAC, SCVMM, and future scenarios should layer on top of the base platform

## Configuration Areas

### 1. Cluster Shape

Make cluster size and node shape explicit configuration choices.

Parameters to support:

- node count: `1`, `2`, `4`, `8`
- node memory profile: `small`, `medium`, `large`, `xlarge`
- node cpu profile: vCPU count or hardware tier
- node disk profile: boot-only, iSCSI-attached, or local-capacity profile
- cluster role preset: `demo`, `lab`, `performance`, `validation`

Recommended first implementation:

- support `2-node` and `4-node` presets first
- expose node memory and CPU as profile-based options instead of raw per-node tuning at the start

### 2. Storage Mode

Treat storage as a selectable platform capability, not a hard-coded implementation.

Candidate modes:

- `iscsi`: easiest repeatable path for nested labs and demo reliability
- `s2d`: higher-value platform mode, but more host-sensitive and more complex to validate
- `none`: useful for management-only or identity-only environments

Roadmap guidance:

- keep `iscsi` as the first portable default
- add `s2d` after the configuration engine and deployment targets are stable
- represent the storage stack as a mode plus version/profile, not as scattered script branching

Example configuration concepts:

- storage mode
- storage capacity preset
- disk count per node
- cache and capacity role settings for S2D-capable targets

### 3. Deployment Targets

The platform should eventually support multiple execution targets under one logical model.

Target types:

- Azure VM host
- nested VM on Hyper-V
- nested VM on VMware
- physical hardware

Recommended order of support:

1. Azure VM host
2. nested Hyper-V host
3. physical hardware
4. nested VMware host

Reasoning:

- Azure VM and nested Hyper-V are closest to the current implementation
- physical hardware adds out-of-band provisioning and driver variability
- VMware requires separate networking and nested virtualization assumptions that should not distort the first platform abstraction

### 4. Management Plane Strategy

If the platform targets physical hardware, management services should become a first-class deployment choice.

Management roles to support:

- domain controllers
- DNS and supporting identity services
- Windows Admin Center
- SCVMM
- optional jump box or orchestration VM

Management plane modes:

- `external`: use existing management infrastructure
- `cohosted`: run management VMs on the same host or cluster being built
- `sidecar-hyperv`: stand up a dedicated Hyper-V management host for identity and tooling

Recommended direction:

- keep `external` and `cohosted` in scope first
- add `sidecar-hyperv` specifically for physical hardware scenarios where the management plane should survive cluster experiments

### 5. Identity Options

Identity needs to be a deliberate platform decision instead of a demo assumption.

Identity modes:

- `existing-domain`: join an existing domain and integrate with existing DNS and identity services
- `custom-domain`: build a new user-defined domain name during deployment
- `built-in-domain`: use a standard platform-provided lab domain with known defaults
- `workgroup`: optional future mode for minimal or non-domain scenarios

Recommended direction:

- keep `existing-domain` for hybrid integration scenarios
- add `built-in-domain` as the default portable lab mode
- add `custom-domain` once domain bootstrap is parameterized end to end

### 6. Azure Local Lab Mode

Longer term, the platform can grow into a lab-oriented Azure Local deployment option.

Potential outcomes:

- deploy a lightweight Azure Local style lab topology for training and validation
- choose between Hyper-V cluster mode and Azure Local mode from the same configuration model
- share common identity, management, networking, and artifact pipelines

Guardrail:

- do not force Azure Local requirements into the base platform too early
- keep the base platform generic enough that Azure Local becomes a scenario pack, not the only product identity

## Recommended Platform Model

The long-term engine should be driven by a single environment definition file.

Suggested concepts:

- target profile
- cluster profile
- storage profile
- identity profile
- management profile
- scenario overlay

Example shape:

```yaml
solution:
  name: corp-lab-01
target:
  type: azure-vm
cluster:
  nodeCount: 4
  nodeSizeProfile: medium
storage:
  mode: iscsi
identity:
  mode: built-in-domain
management:
  mode: cohosted
scenario:
  overlay: hyperv-cluster
```

## Proposed Roadmap Phases

### Phase 0. Stabilize The Current Demo

- finish script validation and workflow sequencing
- eliminate remaining hard-coded assumptions where practical
- capture current architecture as the first supported reference implementation

### Phase 1. Extract The Platform Skeleton

- create a new repo for the platform codebase
- define configuration schema and environment manifest
- separate reusable engine code from demo-specific orchestration
- introduce environment profiles and scenario overlays

### Phase 2. Support Portable Identity And Topology Choices

- add `built-in-domain` mode
- parameterize node count and node size
- make `iscsi` the default portable storage mode
- support both Azure-hosted and nested Hyper-V targets from the same manifest

### Phase 3. Add Physical Hardware And Management Plane Choices

- add physical host deployment path
- add `cohosted` versus `sidecar-hyperv` management plane options
- formalize management service roles and placement rules

### Phase 4. Add S2D And Advanced Storage Profiles

- introduce `s2d` as a validated storage mode
- add capacity and cache profile definitions
- add validation rules to stop unsupported target and storage combinations early

### Phase 5. Add Azure Local Scenario Overlay

- add Azure Local lab mode
- share common bootstrap, identity, and management logic with the base platform
- publish validated reference profiles for training, demos, and lab automation

## Repo And Branding Direction

If this grows beyond the conference demo, avoid keeping `demo` in the platform identity.

Branding goals:

- broad enough to include Hyper-V, Azure Local, and hybrid lab scenarios
- technical and credible, not marketing-heavy
- short enough to work as both repo name and solution name
- consistent across repo, docs site, and future public references

### Current Preferred Direction

- solution name: `Hybrid Infrastructure Toolkit`
- GitHub org: `thisismydemo`
- GitHub repo: `thisismydemo/hybrid-infra-toolkit`
- canonical docs URL: `https://www.thisismydemo.cloud/hybrid-infra-toolkit`

Reasoning:

- broad enough for Azure, Hyper-V, VMware, physical hardware, and future Azure Local overlays
- `toolkit` positions the solution as a reusable engineering asset instead of a single locked-down demo
- `infrastructure` fits better than `cloud` because the scope is not limited to cloud-only deployment targets
- the GitHub location and docs URL are related, but they are not the same naming surface

### Branding Conventions

- use title case for the public product name
- use lowercase kebab-case for repo names, docs paths, and URLs
- keep the repo slug and docs path slug aligned where practical
- treat the website as a path under `thisismydemo.cloud`, not as a GitHub-style `org/repo` identifier

Recommended convention:

- product name: `Hybrid Infrastructure Toolkit`
- GitHub repository: `https://github.com/thisismydemo/hybrid-infra-toolkit`
- docs path slug: `hybrid-infra-toolkit`
- docs URL: `https://www.thisismydemo.cloud/hybrid-infra-toolkit`

Optional short alias:

- no secondary alias recommended right now
- use `hybrid-infra-toolkit` as the primary repo and docs slug

### Fallback Naming Options

Option 1:

- solution name: `Hybrid Infrastructure Lab Builder`
- repo name: `hybrid-infrastructure-lab-builder`

Option 2:

- solution name: `Fabric Lab Platform`
- repo name: `fabric-lab-platform`

Option 3:

- solution name: `Hybrid Fabric Lab`
- repo name: `hybrid-fabric-lab`

### Branding Decision Guardrails

- do not brand the solution around Azure Local unless Azure Local becomes the primary platform story
- do not brand the solution around `cloud` because the roadmap includes nested and physical deployment targets
- do not assume the docs URL should mirror GitHub syntax; it should remain a clean path under `thisismydemo.cloud`

## Initial Success Criteria

The first platform milestone should be considered successful when it can:

- deploy a `2-node` or `4-node` environment from a single manifest
- run in Azure or on nested Hyper-V with minimal branching
- choose between `existing-domain` and `built-in-domain`
- choose between `iscsi` and `none`
- optionally add WAC and SCVMM through a management profile

## Open Design Questions

- how much raw tuning should be exposed versus hidden behind profiles
- whether VMware support belongs in the core platform or as a later extension
- whether Azure Local should be an overlay, a sibling solution, or eventually the default scenario
- whether management roles should always be separated from cluster roles on physical deployments

## Recommended Immediate Next Steps

1. Finish hardening the current Hyper-V demo as the reference implementation.
2. Draft the configuration schema for target, identity, cluster, storage, and management profiles.
3. Decide on the long-term product name before creating the new repo.
4. Create the new repo only after the schema and phase 1 scope are agreed.