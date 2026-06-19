# azure-pipeline-lab

Event-driven ticket pipeline on Azure — Terraform-provisioned, GitHub Actions-deployed, managed-identity-secured.

The portfolio companion to [`azure-terraform-lab`](https://github.com/jaredlandt/azure-terraform-lab): that one is the first move (a VM, apply/destroy); this one is the second (modules, remote state, CI/CD, an event loop).

Inspired by the *infrastructure pattern* of [MncRydr](https://github.com/jaredlandt/MncRydr) — a Windows Sandbox-hosted ticket-triage cockpit. This repo lifts the plumbing (filesystem watcher → state store → dashboard) and rebuilds it cloud-native (blob trigger → Table Storage → Azure Monitor). It does **not** rebuild the cockpit, classifier, or mesh.

## Status

Phases 0–4 complete (Phase 4 ships: GitHub Actions CI/CD via OIDC federation to Entra ID, function deploys from the same workflow). Phase 5 next (observability + portfolio polish). See [Lab 2 roadmap](https://app.notion.com/p/Lab-2-Ticket-Pipeline-on-Azure-37b02ef2def0815fa6b9e37a56f151ae).

## CI/CD

Two GitHub Actions workflows live in `.github/workflows/`:

- **`terraform-plan.yml`** — runs on every PR to `main`. Posts a sticky comment containing the full plan output. No apply.
- **`terraform-apply.yml`** — runs on push to `main` (i.e. PR merge). Applies the plan, then a dependent job zips `function_app/`, uploads it to the `function-package` container, flips `WEBSITE_RUN_FROM_PACKAGE`, and restarts the Function App.

Auth is **OIDC federation to Entra ID** — there are **no long-lived secrets in this repo or in GitHub**. The flow:

```
GitHub Actions (workflow run)
  └─> requests OIDC token (subject = repo:<org>/<repo>:<trigger>)
      └─> Entra ID app registration (federated credential matches subject)
          └─> SP assumes scoped roles
              ├─ Storage Blob Data Contributor on rg-tfstate (state read/write)
              ├─ Contributor on rg-azure-pipeline-lab (manage resources)
              ├─ User Access Administrator on rg-azure-pipeline-lab (assign MI roles)
              └─ Storage Blob Data Contributor on rg-azure-pipeline-lab (upload zip)
```

The package URL is **unsigned** — no SAS. The Function App's own managed identity has `Storage Blob Data Owner` on the SA, so it reads `release.zip` at warm-up with its own credential.

### One-time setup

1. `pwsh ./bootstrap/bootstrap.ps1` — creates the Terraform remote-state backend (run once per subscription).
2. `pwsh ./bootstrap/github_oidc.ps1` — creates the lab RG, the GitHub Actions app registration, two federated credentials, and the scoped role assignments.
3. Paste the three IDs the script emits into **GitHub repo Variables** (Settings → Secrets and variables → Actions → Variables):
   - `AZURE_CLIENT_ID`
   - `AZURE_TENANT_ID`
   - `AZURE_SUBSCRIPTION_ID`
4. Open a PR. The plan comment lands within ~90s.

## How to run locally

Local development still works the same way:

```bash
az login
terraform init
terraform plan -out=tfplan
terraform apply tfplan

# Deploy the function locally (CI does this for you on merge):
./bootstrap/deploy_function.sh

# End-of-session — pair every apply with a destroy:
terraform plan -destroy -out=tfplan.destroy
terraform apply tfplan.destroy
```

`bootstrap/deploy_function.sh` is the local-dev escape hatch — superseded by the `deploy_function` job in `terraform-apply.yml`, but kept for one-off Function App redeploys.

## What this lab signals

Event-driven architecture · managed identity / RBAC / OIDC federation · Terraform modules + remote state · GitHub Actions CI/CD · Azure Monitor.

## What this is NOT

Not the MncRydr cockpit. Not the classifier. Not production MSP tooling. **Synthetic ticket data only** — no real ticket IDs or hostnames.

## License

MIT.
