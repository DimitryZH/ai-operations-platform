locals {
  labels = merge(
    {
      project    = "ai-operations-platform"
      component  = "stateful-agent-runtime"
      env        = "prototype"
      managed_by = "terraform"
    },
    var.labels
  )

  network_self_link    = var.create_network ? google_compute_network.openclaw[0].self_link : var.network_self_link
  subnetwork_self_link = var.create_network ? google_compute_subnetwork.openclaw[0].self_link : var.subnetwork_self_link

  artifact_registry_project_id = coalesce(var.artifact_registry_project_id, var.project_id)
  secret_project_id            = coalesce(var.secret_project_id, var.project_id)

  iap_iam_members = setunion(var.operator_iam_members, var.admin_iam_members)

  runtime_secret_ids = merge(
    var.runtime_secret_ids,
    var.github_pr_secret_id == null ? {} : {
      GITHUB_PR_TOKEN = var.github_pr_secret_id
    }
  )

  runtime_environment = merge(
    {
      PORT                                     = tostring(var.openclaw_port)
      OPENCLAW_CONFIG_PATH                     = "${var.openclaw_runtime_dir}/openclaw.json"
      OPENCLAW_CONTROL_UI_ALLOWED_ORIGINS_JSON = var.openclaw_control_ui_allowed_origins_json
      OPENCLAW_CONTROL_UI_ENABLED              = tostring(var.openclaw_control_ui_enabled)
      OPENCLAW_PLUGIN_ENTRIES_JSON = jsonencode(
        var.openclaw_admin_http_rpc_enabled
        ? {
          "admin-http-rpc" = {
            enabled = true
          }
        }
        : {}
      )
      OPENCLAW_GATEWAY_AUTH_MODE = "token"
      OPENCLAW_GATEWAY_BIND      = "lan"
      OPENCLAW_GITHUB_MODE       = var.openclaw_github_mode
      OPENCLAW_GOOGLE_MODEL_ID   = var.openclaw_google_model_id
      OPENCLAW_OPENAI_MODEL_ID   = var.openclaw_openai_model_id
      OPENCLAW_PRIMARY_MODEL     = var.openclaw_primary_model
      OPENCLAW_RUNTIME_DIR       = var.openclaw_runtime_dir
      OPENCLAW_STATE_DIR         = var.openclaw_state_dir
      OPENCLAW_WORKSPACE_DIR     = var.openclaw_workspace_dir
    },
    {
      for env_name, _ in local.runtime_secret_ids :
      "${env_name}_FILE" => "/run/openclaw/secrets/${env_name}"
    }
  )

  runtime_environment_file = join("\n", [
    for env_name in sort(keys(local.runtime_environment)) :
    "${env_name}=${local.runtime_environment[env_name]}"
  ])

  systemd_unit = templatefile("${path.module}/../systemd/openclaw.service.tftpl", {
    container_image  = var.container_image
    openclaw_gid     = var.openclaw_gid
    openclaw_port    = var.openclaw_port
    openclaw_uid     = var.openclaw_uid
    state_mount_path = var.state_mount_path
  })

  bootstrap_script = templatefile("${path.module}/../scripts/bootstrap-openclaw.sh.tftpl", {
    container_image_b64        = base64encode(var.container_image)
    data_disk_device_name_b64  = base64encode(var.data_disk_device_name)
    openclaw_gid               = var.openclaw_gid
    openclaw_runtime_dir_b64   = base64encode(var.openclaw_runtime_dir)
    openclaw_state_dir_b64     = base64encode(var.openclaw_state_dir)
    openclaw_uid               = var.openclaw_uid
    openclaw_workspace_dir_b64 = base64encode(var.openclaw_workspace_dir)
    project_id_b64             = base64encode(var.project_id)
    runtime_environment_b64    = base64encode("${local.runtime_environment_file}\n")
    secret_project_id_b64      = base64encode(local.secret_project_id)
    secret_map_json_b64        = base64encode(jsonencode(local.runtime_secret_ids))
    state_mount_path_b64       = base64encode(var.state_mount_path)
    systemd_unit_b64           = base64encode(local.systemd_unit)
  })
}

check "existing_network_inputs" {
  assert {
    condition     = var.create_network || (var.network_self_link != null && var.subnetwork_self_link != null)
    error_message = "network_self_link and subnetwork_self_link are required when create_network is false."
  }
}

check "controlled_github_pr_mode" {
  assert {
    condition     = var.openclaw_github_mode != "pr" || var.github_pr_secret_id != null
    error_message = "github_pr_secret_id is required when openclaw_github_mode is pr."
  }
}

check "persistent_paths_under_mount" {
  assert {
    condition = (
      startswith(var.openclaw_state_dir, "${var.state_mount_path}/") &&
      startswith(var.openclaw_workspace_dir, "${var.state_mount_path}/")
    )
    error_message = "openclaw_state_dir and openclaw_workspace_dir must remain under state_mount_path."
  }
}
