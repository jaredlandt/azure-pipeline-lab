# azure-pipeline-lab

Event-driven ticket pipeline on Azure — Terraform-provisioned, GitHub Actions-deployed, managed-identity-secured.

The portfolio companion to [`azure-terraform-lab`](https://github.com/jaredlandt/azure-terraform-lab): that one is the first move (a VM, apply/destroy); this one is the second (modules, remote state, CI/CD, an event loop).

Inspired by the *infrastructure pattern* of [MncRydr](https://github.com/jaredlandt/MncRydr) — a Windows Sandbox-hosted ticket-triage cockpit. This repo lifts the plumbing (filesystem watcher → state store → dashboard) and rebuilds it cloud-native (blob trigger → Table Storage → Azure Monitor). It does **not** rebuild the cockpit, classifier, or mesh.

## Status

Phase 0–1 in progress (remote state + module skeleton). See [Lab 2 roadmap](https://app.notion.com/p/Lab-2-Ticket-Pipeline-on-Azure-37b02ef2def0815fa6b9e37a56f151ae).

## What this lab signals

Event-driven architecture · managed identity / RBAC / OIDC · Terraform modules + remote state · GitHub Actions CI/CD · Azure Monitor.

## What this is NOT

Not the MncRydr cockpit. Not the classifier. Not production MSP tooling. **Synthetic ticket data only** — no real ticket IDs or hostnames.

## License

MIT.
