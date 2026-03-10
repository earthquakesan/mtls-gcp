# 1. Enable APIs
resource "google_project_service" "services" {
  for_each = var.environment == "dev" ? toset([
    "compute.googleapis.com",
    "container.googleapis.com",
    "networkservices.googleapis.com",
    "certificatemanager.googleapis.com",
    "networksecurity.googleapis.com",
  ]) : []
  service            = each.key
  disable_on_destroy = false
}
