terraform {
  backend "gcs" {
    bucket = "ai-operations-platform-507220-sre-control-plane-tfstate"
    prefix = "sre-control-plane/staging"
  }
}
