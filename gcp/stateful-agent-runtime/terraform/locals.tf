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
    },
    var.telegram_adapter_enabled ? {
      TELEGRAM_BOT_TOKEN = var.telegram_bot_token_secret_id
    } : {}
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

  telegram_adapter_environment = {
    OPENCLAW_BASE_URL         = var.telegram_adapter_openclaw_base_url
    TELEGRAM_ALLOWED_CHAT_IDS = var.telegram_allowed_chat_ids
    TELEGRAM_BOT_TOKEN_FILE   = var.telegram_bot_token_file
  }

  telegram_adapter_environment_file = join("\n", [
    for env_name in sort(keys(local.telegram_adapter_environment)) :
    "${env_name}=${local.telegram_adapter_environment[env_name]}"
  ])

  telegram_adapter_package_files = {
    for file_name in sort(fileset("${path.module}/../telegram_adapter", "*.py")) :
    "telegram_adapter/${file_name}" => base64encode(file("${path.module}/../telegram_adapter/${file_name}"))
  }

  telegram_adapter_systemd_unit = templatefile("${path.module}/../systemd/openclaw-telegram-adapter.service.tftpl", {
    telegram_adapter_poll_interval_seconds = var.telegram_adapter_poll_interval_seconds
    telegram_adapter_working_directory     = var.telegram_adapter_working_directory
    telegram_bot_token_file                = var.telegram_bot_token_file
  })

  bootstrap_script = templatefile("${path.module}/../scripts/bootstrap-openclaw.sh.tftpl", {
    container_image_b64                      = base64encode(var.container_image)
    data_disk_device_name_b64                = base64encode(var.data_disk_device_name)
    openclaw_gid                             = var.openclaw_gid
    openclaw_runtime_dir_b64                 = base64encode(var.openclaw_runtime_dir)
    openclaw_state_dir_b64                   = base64encode(var.openclaw_state_dir)
    openclaw_uid                             = var.openclaw_uid
    openclaw_workspace_dir_b64               = base64encode(var.openclaw_workspace_dir)
    project_id_b64                           = base64encode(var.project_id)
    runtime_environment_b64                  = base64encode("${local.runtime_environment_file}\n")
    secret_project_id_b64                    = base64encode(local.secret_project_id)
    secret_map_json_b64                      = base64encode(jsonencode(local.runtime_secret_ids))
    service_state_exporter_enabled           = var.service_state_exporter_enabled
    service_state_exporter_group             = var.service_state_exporter_group
    service_state_exporter_package_files_b64 = base64encode(jsonencode(local.service_state_exporter_package_files))
    service_state_exporter_systemd_timer_b64 = base64encode(local.service_state_exporter_systemd_timer)
    service_state_exporter_systemd_unit_b64  = base64encode(local.service_state_exporter_systemd_unit)
    service_state_exporter_user              = var.service_state_exporter_user
    service_state_exporter_working_dir_b64   = base64encode(var.service_state_exporter_working_directory)
    state_mount_path_b64                     = base64encode(var.state_mount_path)
    systemd_unit_b64                         = base64encode(local.systemd_unit)
    telegram_adapter_enabled                 = var.telegram_adapter_enabled
    telegram_adapter_environment_b64         = base64encode("${local.telegram_adapter_environment_file}\n")
    telegram_adapter_package_files_b64       = base64encode(jsonencode(local.telegram_adapter_package_files))
    telegram_adapter_systemd_unit_b64        = base64encode(local.telegram_adapter_systemd_unit)
    telegram_adapter_working_dir_b64         = base64encode(var.telegram_adapter_working_directory)
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

check "telegram_adapter_requires_allowlist" {
  assert {
    condition     = !var.telegram_adapter_enabled || trimspace(var.telegram_allowed_chat_ids) != ""
    error_message = "telegram_allowed_chat_ids must be set before enabling the Telegram adapter."
  }
}

check "telegram_adapter_requires_token_mapping" {
  assert {
    condition     = !var.telegram_adapter_enabled || trimspace(var.telegram_bot_token_secret_id) != ""
    error_message = "telegram_bot_token_secret_id must be set before enabling the Telegram adapter."
  }
}
