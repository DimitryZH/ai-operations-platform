locals {
  resource_name                    = "${var.name_prefix}-${var.environment}"
  service_account_environment      = substr(var.environment, 0, 15)
  control_plane_service_account_id = "sre-cp-${local.service_account_environment}-run"
  scheduler_service_account_id     = "sre-cp-${local.service_account_environment}-sched"
  labels = {
    application = "sre-control-plane"
    environment = var.environment
    managed_by  = "terraform"
  }
  database_secret_id = "${local.resource_name}-database-url"
  sre_replay_provider_declarations = {
    scenario_id = "approved-stage-frontend-slo-v1"
    kubernetes = {
      provider   = "kubernetes"
      mode       = "sanitized_replay"
      cluster    = "sre-platform-staging"
      namespaces = ["online-shop-stage"]
      resources = [
        "analysisruns.argoproj.io",
        "events",
        "ingresses.networking.k8s.io",
        "pods",
        "rollouts.argoproj.io",
        "services",
      ]
      verbs = ["get", "list"]
    }
    prometheus = {
      provider    = "prometheus"
      mode        = "sanitized_replay"
      query_names = ["slo:burn_rate_5m", "slo:error_ratio_5m", "stage_ingress_request_rate_5m"]
      query_allowlist = [
        "slo:burn_rate_5m",
        "slo:error_ratio_5m",
        "sum(rate(nginx_ingress_controller_requests{exported_namespace=\"online-shop-stage\",status!=\"\"}[5m]))",
      ]
    }
    gitops = {
      provider   = "gitops"
      mode       = "sanitized_replay"
      repository = "DimitryZH/sre-platform"
      ref        = "main"
      paths = [
        "charts/platform/templates/break-ingress.yaml",
        "charts/platform/templates/frontend-ingress.yaml",
        "charts/platform/templates/frontend-rollout.yaml",
        "charts/platform/templates/frontend-slo-check-analysis-template.yaml",
        "environments/stage/argocd/apps/online-shop-stage.yaml",
        "environments/stage/values/platform.yaml",
      ]
      actions = ["read_file"]
    }
    recovery_observation = {
      provider             = "recovery_observation"
      mode                 = "sanitized_replay"
      optional             = true
      actions              = ["observe_status"]
      claims_live_recovery = false
    }
  }
}
