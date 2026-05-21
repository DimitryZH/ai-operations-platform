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

The primary runtime model is based on Google Cloud Run with Terraform-managed infrastructure.

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

- Cloud Run
- Artifact Registry
- Secret Manager
- Cloud Scheduler
- Pub/Sub

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
- future multi-cloud integrations

## Long-Term Direction

The platform is intended to evolve toward:

- multi-agent orchestration
- operational memory
- adaptive troubleshooting workflows
- AI-assisted operational governance
- centralized cloud operations intelligence