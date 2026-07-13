locals {
  labels = merge(
    {
      project     = "ai-operations-platform"
      component   = "agent-devbox"
      environment = "experiment"
      owner       = "platform"
      purpose     = "devclaw-prototype"
      managed_by  = "terraform"
    },
    var.labels
  )

  secret_project_id = coalesce(var.secret_project_id, var.project_id)
  operator_members  = setunion(var.operator_iam_members, var.admin_iam_members)

  secret_access_bindings = {
    for secret_ref in var.secret_manager_secret_refs :
    secret_ref => {
      project   = startswith(secret_ref, "projects/") ? split("/", secret_ref)[1] : local.secret_project_id
      secret_id = startswith(secret_ref, "projects/") ? split("/", secret_ref)[3] : secret_ref
    }
  }

  startup_script = templatefile("${path.module}/startup-script.sh.tftpl", {
    dotnet_sdk_channel     = var.dotnet_sdk_channel
    nodejs_major_version   = var.nodejs_major_version
    validation_runtime_b64 = filebase64("${path.module}/validation/validate-runtime.sh")
    validation_tools_b64   = filebase64("${path.module}/validation/validate-tools.sh")
  })
}

check "artifact_registry_inputs" {
  assert {
    condition = (
      !var.artifact_registry_reader_enabled ||
      (
        var.artifact_registry_project_id != null &&
        var.artifact_registry_location != null &&
        var.artifact_registry_repository_id != null
      )
    )
    error_message = "Artifact Registry project, location, and repository ID are required when artifact_registry_reader_enabled is true."
  }
}
