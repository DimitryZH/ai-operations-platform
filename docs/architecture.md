# Architecture

## Overview

AI Operations Platform is a cloud-native operational intelligence layer designed for GCP and GKE environments.

The platform combines:

- AI operational agents
- reusable operational skills
- workflow orchestration
- platform adapters
- observability integrations
- cloud-native infrastructure
- explicit operational context lifecycle management

The current foundation is GCP-first and starts from a private Stateful VM
runtime with Terraform-managed infrastructure. Platform context is documented
separately under `platform/context/`.

---

# High-Level Architecture

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
 
# Core Components

## Runtime Layer

Primary runtime services:

- GCP Stateful VM runtime
- Artifact Registry
- Secret Manager
- Compute Engine
- IAP

## Operational Agents

The platform supports multiple operational agents:

- Observability Agent
- Incident Agent
- Rollout Analysis Agent
- FinOps Agent
- Delivery Governance Agent

## Skills

Skills provide reusable operational capabilities:

- GCP logging access
- GKE diagnostics
- Prometheus queries
- rollout analysis
- GitHub operational context

## Platform Adapters

Adapters allow integration with multiple environments:

- GCP/GKE
- Docker environments
- future platform integrations

## Long-Term Direction

The platform is intended to evolve toward:

- multi-agent orchestration
- operational memory
- adaptive troubleshooting workflows
- AI-assisted operational governance
- centralized cloud operations intelligence
