# Service-State Monitoring Baseline

This module includes the service-state monitoring baseline for the private
Stateful VM runtime.

Imported components:

- bounded systemd service-state checker
- Cloud Monitoring metric writer
- service-state runner
- monitoring tests and requirements
- service-state exporter systemd service and timer templates
- Terraform exporter wiring
- disabled-by-default service-state alert policy skeleton

Default behavior:

- exporter deployment is disabled
- live Cloud Monitoring writes are disabled
- alert policy creation is disabled
- alert delivery is disabled
- notification channels are not configured

The approved service target for this import is `openclaw.service`. Additional
services should be added only with the module that owns those services.

The checker does not read logs, environment variables, secret files, process
command lines, or application payloads.
