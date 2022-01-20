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

resource "google_compute_firewall" "agoric_rpc_firewall" {
  name    = "${var.agoric_env}-agoric-rpc-firewall"
  network = var.network_name

  target_tags = concat(local.firewall_target_tags_backup_node)

  allow {
    protocol = "tcp"
    ports    = ["26657"]
  }
}

resource "google_compute_firewall" "agoric_telemetry_firewall" {
  name    = "${var.agoric_env}-agoric-telemetry-firewall"
  network = var.network_name

  target_tags = concat(local.firewall_target_tags_validator, local.firewall_target_tags_backup_node)

  # allow connections to the prometheus ports from the VPC as well as from prometheus.testnet.agoric.net
  
  source_ranges = concat([data.google_compute_subnetwork.agoric.ip_cidr_range], ["142.93.181.215/32"])

  allow {
    protocol = "tcp"
    ports    = ["9464"]
  }

  allow {
    protocol = "tcp"
    ports    = ["26660"]
  }
  allow {
    protocol = "tcp"
    ports    = ["9100"]
  }
}

module "backup_node" {
  source = "./modules/backup_node"
  # variables
  block_time                            = var.block_time
  agoric_env                            = var.agoric_env
  gcloud_project                        = var.gcloud_project
  gcloud_zone                           = var.gcloud_zone
  instance_type                         = var.instance_types["backup_node"]
  boot_disk_size                        = var.boot_disk_size
  data_disk_size                        = var.data_disk_size
  cloud_image                           = var.cloud_image
  agoric_node_release_repository        = var.agoric_node_release_repository
  agoric_node_release_tag               = var.agoric_node_release_tag
  network_id                            = var.network_id
  network_name                          = var.network_name
  validator_name                        = var.validator_name
  backup_node_name                      = var.backup_node_name
  network_uri                           = var.network_uri
  backup_node_count                     = var.backup_node_count
  prometheus_exporter_tarball           = var.prometheus_exporter_tarball
  service_account_scopes                = var.service_account_scopes
}

module "validator" {
  source = "./modules/validator"
  # variables
  block_time                            = var.block_time
  agoric_env                            = var.agoric_env
  gcloud_project                        = var.gcloud_project
  instance_type                         = var.instance_types["validator"]
  boot_disk_size                        = var.boot_disk_size
  data_disk_size                        = var.data_disk_size
  cloud_image                           = var.cloud_image
  agoric_node_release_repository        = var.agoric_node_release_repository
  agoric_node_release_tag               = var.agoric_node_release_tag
  network_id                            = var.network_id
  network_name                          = var.network_name
  validator_count                       = var.validator_count
  reset_chain_data                      = var.reset_chain_data
  validator_name                        = var.validator_name
  network_uri                           = var.network_uri
  prometheus_exporter_tarball           = var.prometheus_exporter_tarball
  service_account_scopes                = var.service_account_scopes
}

 
#module "agent_policy" {
#  source     = "terraform-google-modules/cloud-operations/google//modules/agent-policy"
#  version    = "~> 0.1.0"
#
#  project_id = var.gcloud_project
#  policy_id  = "ops-agents-policy"
#  agent_rules = [
#    {
#      type               = "ops-agent"
#      version            = "current-major"
#      package_state      = "installed"
#      enable_autoupgrade = true
#    },
#  ]
#  #group_labels = [
#  #  {
#  #    env = "mainnet0"
#  #    role = "validator"
#  #  }
#  #]
#  os_types = [
#    {
#      short_name = "debian"
#      version    = "11"
#    },
#  ]
#}
