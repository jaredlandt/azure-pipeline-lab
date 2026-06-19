# azure-pipeline-lab

Event-driven ticket pipeline on Azure — Terraform-provisioned, GitHub Actions-deployed, managed-identity-secured. **No long-lived secrets anywhere in the repo or in Azure.**

The portfolio companion to [`azure-terraform-lab`](https://github.com/jaredlandt/azure-terraform-lab): that one is the first move (a VM, apply / destroy); this one is the second (modules, remote state, event loop, CI/CD, observability).

Inspired by the *infrastructure pattern* of [MncRydr](https://github.com/jaredlandt/MncRydr) — a Windows Sandbox-hosted ticket-triage cockpit. This repo lifts the plumbing (filesystem watcher → state store → dashboard) and rebuilds it cloud-native (blob trigger → Table Storage → Azure Monitor workbook). It does **not** rebuild the cockpit, the classifier, or the mesh.

## Status

Phases 0–5 complete. Roadmap: [Lab 2 — Ticket Pipeline on Azure](https://app.notion.com/p/Lab-2-Ticket-Pipeline-on-Azure-37b02ef2def0815fa6b9e37a56f151ae).

## What it provisions

```
                ┌─────────────────────────────────────────────────────────┐
                │  Resource group  rg-azure-pipeline-lab                  │
                │  (created by bootstrap, NOT Terraform — see below)      │
                │                                                         │
   ticket ──►   │  ┌──────────────────────────────────────────────┐       │
   (blob)       │  │  Storage account  st<name><random>           │       │
                │  │   ├ inbox            (blob trigger source)   │       │
                │  │   ├ in-process                                │       │
                │  │   ├ completed                                 │       │
                │  │   ├ failed                                    │       │
                │  │   ├ function-package (release.zip from CI)   │       │
                │  │   └ tickets table   (route_ticket writes)    │       │
                │  │                                              │       │
                │  │   shared_access_key_enabled = false          │       │
                │  └──────────────────────────────────────────────┘       │
                │            ▲                ▲                            │
                │            │ MI auth        │ MI auth                    │
                │            │                │                            │
                │  ┌─────────┴───────┐  ┌────┴────────────────┐            │
                │  │ Function App    │  │ App Insights        │            │
                │  │ Linux Y1 (Y1)   │  │ + Log Analytics WS  │            │
                │  │ Python 3.11     │──► (instrumented)      │            │
                │  │ system-assigned │  │                     │            │
                │  │ MI              │  │ Workbook:           │            │
                │  │ blob trigger    │  │  ingest / failures  │            │
                │  │ (route_ticket)  │  │  / p50 p95 p99      │            │
                │  └─────────────────┘  └─────────────────────┘            │
                └─────────────────────────────────────────────────────────┘

   GitHub Actions ──OIDC──► Entra ID app ──scoped roles──► above
   (no secrets)             (no client secret)
```

Roughly 17 Azure resources. The trip from ticket-drop to `tickets` table row is ~1 second. The trip from PR-merge to deployed code is ~6 minutes.

## How to run

### One-time setup (per Azure subscription + GitHub repo)

```bash
# 1. State backend (rg-tfstate, storage account, blob versioning, RBAC).
pwsh ./bootstrap/bootstrap.ps1

# 2. Lab RG + Entra app registration + federated credentials + scoped roles.
#    Optional flag grants the local user data-plane access for smoke tests.
pwsh ./bootstrap/github_oidc.ps1 -GrantLocalUserDataPlane

# 3. The script emits three `gh variable set` commands — copy-paste them
#    while inside the repo's working directory. `gh` is cwd-aware so the
#    variables land on the right repo automatically (Phase 4 lesson: paste
#    the values manually into the wrong sibling repo and the workflow
#    fails opaquely).
```

After step 3 the CI/CD loop is live. Open a PR → plan-as-comment within ~90s. Merge → apply + function deploy within ~6 min.

### Local development

The local loop still works the same way — useful for debugging Terraform changes without burning a CI run.

```bash
az login
terraform init
terraform plan -out=tfplan
terraform apply tfplan

# Deploy the function locally (CI does this on merge — script is the
# local-dev escape hatch; it produces a 1-hour SAS URL whereas CI uses
# the cleaner unsigned-URL + MI-auth pattern).
./bootstrap/deploy_function.sh

# Smoke test the round trip:
az storage blob upload --auth-mode login \
  --account-name $(terraform output -raw storage_account_name) \
  --container-name inbox \
  --name ticket-smoke.json \
  --file ticket-smoke.json

# End-of-session — pair every apply with a destroy:
terraform plan -destroy -out=tfplan.destroy
terraform apply tfplan.destroy
```

### Destroy via CI

A `workflow_dispatch`-triggered destroy workflow lives at `.github/workflows/terraform-destroy.yml`. Use when you don't have the local toolchain handy — type `yes` into the confirmation input and the same OIDC SP tears it all down.

## CI/CD architecture

Two workflows live in `.github/workflows/`:

- **`terraform-plan.yml`** — runs on every PR to `main`. Init, fmt-check, validate, plan with `-detailed-exitcode`, post a sticky comment containing the full plan in a collapsed `<details>` block. Comment updates in-place on workflow re-runs.
- **`terraform-apply.yml`** — runs on push to `main`. Apply, then a dependent job zips `function_app/`, vendors Linux Python wheels, uploads `release.zip` to the `function-package` container, sets `WEBSITE_RUN_FROM_PACKAGE` to the **unsigned** blob URL (Function MI authenticates the read), restarts the host, probes status.

Auth is **OIDC federation to Entra ID**. The flow:

```
GitHub Actions (workflow run)
  └─ requests OIDC token (subject = repo:<org>/<repo>:<trigger>)
     └─ Entra ID app registration (federated credential matches subject)
        └─ Service principal assumes scoped roles:
           ├ Storage Blob Data Contributor on rg-tfstate (state read/write)
           ├ Contributor on rg-azure-pipeline-lab (manage resources)
           ├ User Access Administrator on rg-azure-pipeline-lab (assign MI roles)
           └ Storage Blob Data Contributor on rg-azure-pipeline-lab (upload zip)
```

There is no client secret. There is no SAS URL in the run-from-package setting. There is no storage account key. With `shared_access_key_enabled = false`, account keys don't exist as an auth surface at all.

## Observability

`modules/observability/` provisions one Azure Monitor workbook against the function's Application Insights instance. Three tiles + a markdown intro, all KQL against the `requests` table for the `route_ticket` blob trigger:

- **Ticket ingest** (column chart, per hour, last 24h)
- **Failure rate** (time chart, hourly totals + failed counts + failure %)
- **Duration** (time chart, p50 / p95 / p99 in ms)

Open it from the portal: Application Insights instance → Workbooks → Public → "azure-pipeline-lab — pipeline health". Workbook resource ID is also exposed as `terraform output workbook_id`.

## Architecture decisions worth knowing

- **The lab RG is owned by bootstrap, NOT Terraform.** Phase 4's scoped-SP design needs the RG to exist before the SP can be scoped to it. Terraform reads it as a `data` source. This is the production pattern: long-lived "platform" resources (RGs, networks, key vaults) live in a bootstrap stack with separate state; "workload" resources live in the team stack.
- **The state backend uses AAD auth, not keys.** `use_azuread_auth = true` in `backend.tf`; `storage_use_azuread = true` on the provider; `shared_access_key_enabled = false` on the storage account. The whole repo runs on identities, not credentials.
- **`lifecycle { ignore_changes = [app_settings] }`** on the Function App. Terraform owns the *infrastructure*; the CI deploy step owns `WEBSITE_RUN_FROM_PACKAGE`. Without the ignore, every Terraform apply would wipe the deployment pointer. This split is the standard production pattern for separating IaC from code-deploy concerns.
- **Storage account names use a random suffix.** Globally unique across all of Azure, so any fork can apply without colliding. State carries the suffix; re-applies in one workspace are stable.
- **App Insights is mandatory on Linux consumption.** No SCM site means no `az webapp log tail`. Without App Insights, debugging is "guess from `state: Running`." Brought forward from Phase 5 to Phase 3 for that reason; the workbook is the Phase 5 polish on top.
- **Network Watcher RG isn't auto-created here.** Lab 1's mystery `NetworkWatcherRG` showed up because creating a NIC in a region triggers regional Network Watcher auto-provisioning. This lab has no NIC (consumption-tier Function is fully managed networking), so it doesn't surface.

## What this is NOT

- Not the MncRydr cockpit. Not the classifier. Not the mesh. Not production MSP tooling.
- **Synthetic ticket data only.** No real ticket IDs. No real hostnames. No real client identifiers. The boundary MncRydr maintains is not negotiable.
- Not zero-cost: ~$0.05/mo if you forget to destroy (App Insights at default sampling on a noisy function is the leak). End every session with `destroy`.

## License

MIT.
