# 2. VPC and Subnets
resource "google_compute_network" "vpc" {
  count                   = var.environment == "dev" ? 1 : 0
  name                    = var.vpc_name
  auto_create_subnetworks = false
  depends_on              = [google_project_service.services]
}

resource "google_compute_subnetwork" "lb_subnet" {
  count         = var.environment == "dev" ? 1 : 0
  name          = var.subnet_name
  ip_cidr_range = "10.0.0.0/24"
  region        = var.region
  network       = google_compute_network.vpc.0.id
}

resource "google_compute_subnetwork" "proxy_only_subnet" {
  count         = var.environment == "dev" ? 1 : 0
  name          = "proxy-only-subnet"
  ip_cidr_range = "10.129.0.0/23"
  region        = var.region
  purpose       = "GLOBAL_MANAGED_PROXY"
  role          = "ACTIVE"
  network       = google_compute_network.vpc.0.id
}

# 3. Firewall Rules
resource "google_compute_firewall" "allow_ssh_iap" {
  count   = var.environment == "dev" ? 1 : 0
  name    = "allow-ssh-iap"
  network = google_compute_network.vpc.0.name
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  source_ranges = ["35.235.240.0/20"]
}

resource "google_compute_firewall" "allow_lb_health_check" {
  count   = var.environment == "dev" ? 1 : 0
  name    = "allow-lb-health-check"
  network = google_compute_network.vpc.0.name
  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }
  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
}

resource "google_compute_firewall" "allow_proxy_only_subnet" {
  count   = var.environment == "dev" ? 1 : 0
  name    = "allow-proxy-only-subnet"
  network = google_compute_network.vpc.0.name
  allow {
    protocol = "tcp"
    ports    = ["80", "443", "8080"]
  }
  source_ranges = [google_compute_subnetwork.proxy_only_subnet.0.ip_cidr_range]
}
