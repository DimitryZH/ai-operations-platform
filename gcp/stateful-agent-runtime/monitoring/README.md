# Service-State Monitoring

This package contains the service-state monitoring baseline for the private
Stateful VM runtime.

It reads bounded `systemctl show` metadata for approved services, builds
service-state metric payloads, and can write those metrics to Cloud Monitoring
only when explicitly invoked with `--write`.

Default approved service:

- `openclaw.service`

The Terraform and systemd wiring keep the exporter disabled by default. Live
Cloud Monitoring writes require both:

- `service_state_exporter_enabled = true`
- `service_state_exporter_live_writes_enabled = true`

Alert policy creation is also disabled by default and does not configure
notification routing.
