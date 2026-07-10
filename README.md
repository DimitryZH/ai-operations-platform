# AI Operations Platform

AI-powered operational platform for GCP and GKE environments focused on observability, incident analysis, rollout diagnostics, delivery governance, and cloud operations assistance.

The platform is designed as a modular, extensible AI operations layer that integrates operational agents, reusable skills, platform adapters, and workflow orchestration into a single cloud-native runtime.

This platform evolved from the earlier `ai-agent-host` infrastructure foundation project.

The current foundation is GCP-first and starts with a private Stateful VM
runtime plus a lightweight platform context lifecycle scaffold.

---

## Overview

The AI Operations Platform provides a centralized operational intelligence layer for modern cloud engineering environments.

Core areas:

- Observability analysis
- Incident triage
- Rollout diagnostics
- Kubernetes operational analysis
- FinOps operational insights
- AI-assisted cloud operations
- Explicit operational context lifecycle management

---

## Architecture

```text
                   AI Operations Platform
                              │
                ┌─────────────┼─────────────┐
                │             │             │
          Operational     Workflow      Platform
             Agents      Orchestration   Adapters
                │             │             │
                └────── Shared Context ────┘
                              │
     ┌──────────────┬─────────┼──────────┬──────────────┐
     │              │         │          │              │
 Cloud Logging   GKE API  Prometheus  GitHub API  Cloud Monitoring
```

---

## Repository Structure

```text
ai-operations-platform/
├── app/
├── agents/
├── skills/
├── platforms/
├── workflows/
├── terraform/
├── docs/
└── .github/workflows/
```

---

## Documentation

- [Architecture](docs/architecture.md)
- [Security Model](docs/security-model.md)
- [Operating Model](docs/operating-model.md)
- [Context Lifecycle Foundation](platform/context/README.md)
- [Backup & Restore](docs/backup-restore.md)
- [Roadmap](docs/roadmap.md)

---

## Supported Platforms & Integrated Projects

### SRE Platform
- Argo Rollouts
- Prometheus
- GitOps workflows

### GCP Secure Delivery Platform
- Cloud Build
- Cloud Deploy
- Binary Authorization

### CI Build Platform
- Self-hosted runners
- Ephemeral build infrastructure

### FinOps Assessment Platform
- Operational cost analysis
- Resource scanning
- Optimization reporting

---

## Deployment Model

```text
GitHub Actions
        ↓
Build Container
        ↓
Artifact Registry
        ↓
GCP Stateful VM Runtime
        ↓
Operational Runtime
```

---

## Long-Term Vision

The platform is intended to evolve into a centralized AI-powered operational intelligence layer for cloud engineering environments.
