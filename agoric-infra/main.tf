provider "google" {
  project = var.gcloud_project
  region  = var.gcloud_region
  zone    = var.gcloud_zone
}

locals {
  firewall_target_tags_validator           = ["${var.agoric_env}-validator"]
  firewall_target_tags_backup_node         = ["${var.agoric_env}-backup-node"]
}

# Dummy variable for network dependency
variable network_depends_on {
  type    = any
  default = null
}

data "google_compute_network" "agoric" {
  name       = var.network_name
  depends_on = [var.network_depends_on]
}

data "google_compute_subnetwork" "agoric" {
  name       = var.network_name
  region     = var.gcloud_region
  depends_on = [var.network_depends_on]
}

# GCP resources
resource "google_compute_firewall" "ssh_firewall" {
  name    = "${var.agoric_env}-ssh-firewall"
  network = var.network_name

  target_tags = concat(
                  local.firewall_target_tags_validator,
                  local.firewall_target_tags_backup_node
                )

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

resource "google_compute_firewall" "agoric_p2p_firewall" {
  name    = "${var.agoric_env}-agoric-p2p-firewall"
  network = var.network_name

  target_tags = concat(local.firewall_target_tags_validator, local.firewall_target_tags_backup_node)

  allow {
    protocol = "tcp"
    ports    = ["26656"]
  }
}

resource "google_compute_firewall" "agoric_telemetry_firewall" {
  name    = "${var.agoric_env}-agoric-telemetry-firewall"
  network = var.network_name

  target_tags = concat(local.firewall_target_tags_validator, local.firewall_target_tags_backup_node)

  #source_ranges = 142.93.181.215    # prometheus.testnet.agoric.net   # todo: make var
  # allow connections to the prometheus ports from the VPC as well as from prometheus.testnet.agoric.net
  source_ranges = concat([data.google_compute_subnetwork.agoric.ip_cidr_range], 142.93.181.215

  allow {
    protocol = "tcp"
    ports    = ["9464"]
  }

  allow {
    protocol = "tcp"
    ports    = ["26660"]
  }
}

module "backup_node" {
  source = "./modules/backup_node"
  # variables
  block_time                            = var.block_time
  agoric_env                            = var.agoric_env
  gcloud_project                        = var.gcloud_project
  instance_type                         = var.instance_types["backup_node"]
  agoric_node_release_repository        = var.agoric_node_release_repository
  agoric_node_release_tag               = var.agoric_node_release_tag
  network_id                            = var.network_id
  network_name                          = var.network_name
  backup_node_count                     = var.backup_node_count
  service_account_scopes                = var.service_account_scopes
}

module "validator" {
  source = "./modules/validator"
  # variables
  block_time                            = var.block_time
  agoric_env                            = var.agoric_env
  gcloud_project                        = var.gcloud_project
  instance_type                         = var.instance_types["validator"]
  agoric_node_release_repository        = var.agoric_node_release_repository
  agoric_node_release_tag               = var.agoric_node_release_tag
  network_id                            = var.network_id
  network_name                          = var.network_name
  validator_count                       = var.validator_count
  reset_chain_data                      = var.reset_chain_data
  validator_name                     = var.validator_name
  validator_signer_account_addresses = var.validator_signer_account_addresses
  validator_signer_account_passwords = var.validator_signer_account_passwords
  validator_signer_private_keys      = var.validator_signer_private_keys
  service_account_scopes             = var.service_account_scopes
}
