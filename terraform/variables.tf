variable "project_id" {
  description = "The GCP Project ID"
  type        = string
}

variable "region" {
  description = "The GCP Region"
  type        = string
  default     = "europe-west3"
}

variable "environment" {
  description = "The environment name (e.g., dev, prod)"
  type        = string
}

variable "zones" {
  description = "The zones for GKE and NEGs"
  type        = list(string)
  default     = ["europe-west3-a", "europe-west3-b", "europe-west3-c"]
}

variable "vpc_name" {
  default = "mtls-demo-vpc"
}

variable "subnet_name" {
  default = "mtls-lb-subnet"
}

variable "cluster_name" {
  default = "mtls-gke-cluster"
}
