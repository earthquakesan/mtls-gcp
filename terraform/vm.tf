# 10. Provision Test VM
resource "google_compute_instance" "test_vm" {
  count        = var.environment == "dev" ? 1 : 0
  name         = "mtls-test-client"
  machine_type = "e2-micro"
  zone         = var.zones[0]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
    }
  }

  network_interface {
    network    = google_compute_network.vpc.0.id
    subnetwork = google_compute_subnetwork.lb_subnet.0.id
  }

  metadata_startup_script = "apt-get update && apt-get install -y curl"

  service_account {
    scopes = ["cloud-platform"]
  }
}
