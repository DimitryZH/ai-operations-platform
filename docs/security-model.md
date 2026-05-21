# Security Model

## Overview

The platform follows a least-privilege operational model focused on operational analysis rather than infrastructure mutation.

The default platform philosophy is:

- read-only first
- operator-controlled remediation
- immutable deployments
- externalized secrets
- isolated runtime components

---

# Core Principles

## Read-Only Operations

Default operational access includes:

- Cloud Logging Viewer
- Monitoring Viewer
- GKE read-only access
- Cloud Asset Viewer

The platform should not perform destructive operations automatically.

---

# IAM Design

Each runtime component uses:

- dedicated service accounts
- minimal IAM permissions
- isolated credentials
- environment-specific bindings

---

# Secret Management

Sensitive values are stored in:

- Google Secret Manager

Secrets should never be:

- hardcoded
- committed to Git
- embedded in Terraform state

---

# Runtime Isolation

Cloud Run provides:

- immutable container deployments
- isolated runtime execution
- managed infrastructure
- centralized audit visibility

---

# Future Security Areas

Planned future improvements:

- image signing
- workload identity
- policy guardrails
- agent permission boundaries
- audit event correlation