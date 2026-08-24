# Changelog

All notable changes to this module are documented here. Format loosely follows [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Fixed
- `terraform fmt` failures in `envs/dev.tfvars`, `envs/prod-blue.tfvars`, `envs/staging.tfvars`, `external-dns.tf`, `falcon.tf`, `outputs.tf` — pre-existing (predates this PR entirely; none of these files were touched by anything else in this changeset), and CI's `Format` job was failing on `main` as a result. This PR is apparently the first to actually trigger `pull_request` CI in a while, surfacing it. Whitespace/alignment only, no semantic changes — ran `terraform fmt -recursive`.
- `CLAUDE.md`'s "Pending additions" summary claimed KEDA, Kong, external-dns, and Falcon sensor were still pending. All four are fully implemented — verified each defines a real `helm_release` resource (`keda.tf`, `kong.tf`, `external-dns.tf`, `falcon.tf`), and `versions.json` pins all their chart versions. ARC controller (`arc.tf`) is also fully implemented but wasn't even mentioned in the pending list. This also means the central `aj-infra-context/CLAUDE.md` roadmap's priority-#1 item ("Update aj-infra-platform... blocks full workload cluster operation") is largely already done — flagged separately for a fix there too.
  - Root cause, from git history: `cfe37d8` ("docs: update CLAUDE.md across all repos") landed, then `bec5a8d` ("feat: add KEDA, Kong, Gatekeeper, external-dns, Falcon") merged right after — the docs commit's snapshot was obsoleted almost immediately and never revisited.
  - The detailed per-add-on TODO list below the summary line was **not** stale — verified all 5 items still accurately open (AWS LBC still uses `active_private_subnets[0]` as a VPC ID placeholder, `install_falcon` defaults `false`, `external_dns_domain_filter` defaults empty, no Valkey/ESO wiring in `kong.tf`). Only Cloudability agent, Alloy, and ArgoCD agent registration are genuinely still missing.
- `CLAUDE.md`'s "Files" table was missing 6 files that already existed: `keda.tf`, `kong.tf`, `external-dns.tf`, `falcon.tf`, `arc.tf`, `gatekeeper.tf`. Added.
- `CLAUDE.md` opened with "Central orchestrator for the AI Search Engine infrastructure platform layer" — generalized to describe the module itself, not one specific product (same reasoning as the equivalent fixes in `aj-tf-module-vpc`/`aj-tf-module-eks`).
- `CLAUDE.md`'s "Running Locally" pointed at `My-Infra/ make shell` — repo since renamed to `aj-infra-context`; that Podman workflow currently has no `Makefile`/`Dockerfile` (documented gap, not fixed here).
- `CLAUDE.md` claimed "Not pushed to GitHub" — inaccurate (it obviously is, this is a git-tracked file); corrected.

### Added
- `README.md` — none existed. Covers the add-on table, apply order, usage, files, design decisions, provider pins, and TODOs.
- `skills.md` — none existed, meaning this repo had no context source for `aj-agent-farm`'s two-source context model. Notes the module's real dependency on live EKS remote state (no meaningful dry-run plan is possible, unlike other tf-module repos), and that `v1.0.0` is well behind `main` (6 add-ons landed after the last tag).

## [v1.0.0] - 2026-03-29

Initial release — Cilium, AWS LBC, Karpenter, cert-manager, External Secrets, metrics-server. IAM policies + Pod Identity associations for each. Everything else (Gatekeeper, KEDA, Kong, external-dns, Falcon, ARC) landed after this tag and is unreleased.
