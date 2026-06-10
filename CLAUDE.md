# azure-pipeline-lab — Claude Code Instructions

## What this repo is
Event-driven ticket pipeline on Azure. Terraform-provisioned. Modules + remote state from day one. GitHub Actions deploys via OIDC. Companion to `azure-terraform-lab`.

## Scope discipline
- **Plumbing, not cockpit.** Phase 3 stub function is ~30 lines: blob trigger → Table Storage row → move blob to `completed`. No classification, no mesh, no dashboard logic.
- **Synthetic data only.** Nothing from `MncRydr/Data/` or `MncRydr/Code/Runbooks/`. Real ticket IDs and client hostnames stay home.
- **Apply/destroy discipline.** End every session with `terraform destroy` and a portal glance. Same rule as Lab 1.

## Terraform workflow
- Plan-file pattern: `terraform plan -out=tfplan` → `terraform apply tfplan`. Never blind `apply -auto-approve` against cloud.
- Remote state lives in Azure Storage (provisioned by `bootstrap/bootstrap.ps1`). The backend block points there from day one.
- Validation blocks on every variable. Lab 1 lesson: missing validation reads as ISSUE, not NIT.

## Cost
- Consumption-tier function + storage = pennies/mo.
- App Insights default sampling on a noisy function is the leak vector. Set daily cap.
- Subscription budget: `lab-monthly-10` ($10/mo, alerts at 50/80/100% to j.landt@icloud.com).

## Quota traps inherited from Lab 1
- B-series sunset, Basv2/Bsv2/Bpsv2 = 0 trial quota. Functions on consumption tier sidestep VM quotas entirely.

## Review gate
`/review` writes `.last-review` (gitignored). Push only after review is fresh against HEAD.
