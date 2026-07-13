# Agent DevBox Terraform Skeleton

This Terraform root defines a disposable GCP experiment VM for the DevClaw
Compose-to-Aspire prototype. It is intentionally limited to infrastructure and
base runtime prerequisites.

It does not install OpenClaw, DevClaw, GitHub credentials, a token broker, model
provider clients, or application source repositories.

## Architecture Boundary

The Agent DevBox is a standalone disposable execution sandbox for future
prototype work. It is separate from:

- the AI Operations Platform Stateful Agent Runtime in `gcp/stateful-agent-runtime/`;
- the existing AI Agent Host runtime;
- the Application Modernization Lab source repository.

The Application Modernization Lab repository is:

```text
https://github.com/DimitryZH/application-modernization-lab
```

Future DevClaw work may use a local checkout and worktrees on this VM, but this
skeleton does not clone that repository.

## What Terraform Manages

- Required Google API enablement resources.
- Dedicated custom-mode VPC and regional subnet.
- Cloud Router and Cloud NAT for private VM egress.
- IAP-only SSH firewall rule from `35.235.240.0/20`.
- Dedicated Compute Engine service account.
- Minimal IAM for logging and monitoring.
- Optional Artifact Registry reader binding.
- Named Secret Manager accessor bindings only.
- A private Ubuntu VM with no external IP.
- Shielded VM settings and OS Login metadata.
- Startup script wiring for base prerequisites.

## What Startup Manages

The startup script installs and validates only base prerequisites:

- OS packages and basic utilities;
- Docker Engine and Docker Compose plugin;
- Git;
- GitHub CLI binary, without authentication;
- .NET SDK;
- Node.js;
- proposed Linux users;
- base DevClaw experiment directories;
- non-secret bootstrap readiness marker.

## Intentionally Not Installed

- OpenClaw;
- DevClaw;
- GitHub credentials;
- GitHub App private keys;
- token broker;
- model-provider clients;
- source repository clones;
- systemd units for OpenClaw or DevClaw.

## Access Model

The VM has no public IP and no public application ingress. Operator access is
through IAP SSH and OS Login. Aspire Dashboard and OpenClaw UI access, when
added in later tasks, must use IAP or SSH tunnels rather than public ingress.

Example IAP SSH command is exposed as a Terraform output after apply.

## IAM Boundary

The VM service account receives only:

- `roles/logging.logWriter`;
- `roles/monitoring.metricWriter`;
- named Secret Manager `roles/secretmanager.secretAccessor` bindings for
  explicitly supplied secret references;
- optional Artifact Registry reader binding when enabled.

Do not grant Owner, Editor, Compute Admin, Service Account Admin, Secret Manager
Admin, or broad project write permissions.

## Variables

Start from `terraform.tfvars.example` and replace placeholders in a private
local `terraform.tfvars` file. Do not commit local tfvars, plans, state, secret
payloads, private keys, or credentials.

Important variables:

- `project_id`, `region`, `zone`;
- `name_prefix`;
- `subnet_cidr`;
- `machine_type`;
- `boot_disk_size_gb`, `boot_disk_type`;
- `operator_iam_members`;
- `secret_manager_secret_refs`;
- `dotnet_sdk_channel`;
- `nodejs_major_version`.

## Validation

Local-only checks:

```bash
terraform -chdir=gcp/agent-devbox fmt -recursive
terraform -chdir=gcp/agent-devbox fmt -check -recursive
terraform -chdir=gcp/agent-devbox init -backend=false
terraform -chdir=gcp/agent-devbox validate
bash -n gcp/agent-devbox/startup-script.sh.tftpl
bash -n gcp/agent-devbox/validation/validate-tools.sh
bash -n gcp/agent-devbox/validation/validate-runtime.sh
git diff --check
```

Do not run `terraform plan`, `terraform apply`, `terraform destroy`, `gcloud`
mutation commands, or GitHub mutation commands without a separate approval.

## Future Task Sequence

1. Review this skeleton.
2. Run local Terraform validation.
3. Create a reviewed Terraform plan in a later approved task.
4. Configure disposable GitHub repository protections in a later approved task.
5. Configure split GitHub credentials in a later approved task.
6. Apply VM infrastructure only after explicit approval.
7. Validate base runtime prerequisites.
8. Install OpenClaw and DevClaw only in later approved tasks.
9. Run documentation-only smoke tests before any Application Modernization Lab
   migration experiment.

## Destroy Implications

The first skeleton uses the boot disk for runtime and workspace state. VM reboot
preserves boot disk state. VM destroy removes local unpushed work. Pushed
branches and GitHub issue/PR state are the durable cross-VM boundary. A separate
workspace disk can be evaluated later if recovery requirements justify it.
