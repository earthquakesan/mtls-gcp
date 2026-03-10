output "lb_ip" {
  value = var.environment == "dev" ? google_compute_address.lb_ip.0.address : null
}

output "vm_ssh_command" {
  value = var.environment == "dev" ? "gcloud compute ssh ${google_compute_instance.test_vm.0.name} --zone=${google_compute_instance.test_vm.0.zone} --tunnel-through-iap" : null
}
