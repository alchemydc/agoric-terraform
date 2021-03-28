provider "google" {
  project = var.google["project"]
  region  = var.google["region"]
  zone    = var.google["zone"]
}

resource "google_project_service" "compute" {
  project                    = var.google["project"]
  service                    = "compute.googleapis.com"
  disable_dependent_services = true
  disable_on_destroy         = false
}

resource "google_project_service" "db" {
  project                    = var.google["project"]
  service                    = "sqladmin.googleapis.com"
  disable_dependent_services = true
  disable_on_destroy         = false
}

resource "google_compute_network" "agoric_network" {
  name = var.network_name
  timeouts {
    delete = "15m"
  }
}

data "google_compute_subnetwork" "agoric_subnetwork" {
  name       = google_compute_network.agoric_network.name
  region     = var.google["region"]
  depends_on = [google_compute_network.agoric_network]
}

resource "google_compute_router" "router" {
  name    = "${var.agoric_env}-celo-router"
  region  = data.google_compute_subnetwork.agoric_subnetwork.region
  network = google_compute_network.celo_network.self_link

  bgp {
    asn = 64514
  }
}

resource "google_compute_router_nat" "nat" {
  name                               = "${var.agoric_env}-agoric-router-nat"
  router                             = google_compute_router.router.name
  region                             = google_compute_router.router.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = false
    filter = "ERRORS_ONLY"
  }
}

module "agoric_cluster" {
  source             = "agoric-infra/"
  network_depends_on = [google_compute_network.agoric_network]

  gcloud_project          = var.google["project"]
  gcloud_region           = var.google["region"]
  gcloud_zone             = var.google["zone"]
  network_name            = google_compute_network.agoric_network.name
  celo_env                = var.agoric_env
  instance_types          = var.instance_types
  service_account_scopes  = var.service_account_scopes

  stackdriver_logging_exclusions = var.stackdriver_logging_exclusions
  stackdriver_logging_metrics    = var.stackdriver_logging_metrics
  
  backup_node_count   = var.replicas["backup_node"]
  validator_count     = var.replicas["validator"]

  validator_signer_account_addresses = var.validator_signer_accounts["account_addresses"]
  validator_signer_private_keys      = var.validator_signer_accounts["private_keys"]
  validator_signer_account_passwords = var.validator_signer_accounts["account_passwords"]

  validator_name = var.validator_name

  reset_chain_data = var.reset_chain_data

  agoric_node_github_repository         = var.agoric_node_release["repository"]
  agoric_node_github_tag                = var.agoric_node_release["tag"]
  network_id                            = var.network_id
  block_time                            = var.block_time
  
}

resource "google_logging_project_exclusion" "logging_exclusion" {
  for_each = var.stackdriver_logging_exclusions
  
  name            = each.key                    #maybe make this a random_id to ensure no naming conflicts
  description     = each.value["description"]
  filter          = each.value["filter"]
}

resource "random_id" "stackdriver_logging_exclusions" {
  for_each = var.stackdriver_logging_exclusions
    byte_length = 4
}

resource "random_id" "stackdriver_logging_metrics" {
  for_each = var.stackdriver_logging_metrics
    byte_length = 4
}

resource "google_logging_metric" "logging_metric" {
  for_each = var.stackdriver_logging_metrics
    name        = each.key
    description = each.value["description"]
    filter = each.value["filter"]
    metric_descriptor {
      metric_kind  = "DELTA"
      value_type   = "INT64"
      display_name = each.value["description"]
    }
}

resource "google_logging_metric" "distribution_blocks_ingested" {
  name   = "tf_eth_blocks_ingested"
  description = "Ethereum blocks ingested"
  filter = "resource.type=\"gce_instance\" AND \"Imported new chain segment\""
  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "DISTRIBUTION"
    unit        = "blocks"
    display_name = "Blocks Ingested"
  }
  value_extractor = "REGEXP_EXTRACT(jsonPayload.message, \"\\\"blocks\\\":(\\\\d+)\")"
  bucket_options {
    explicit_buckets {
      bounds = [0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,40,60,80,100,120,140,160,180,200,400,500,600,700,800,900,1000,1200,1400,1600,1800,2000,2200,2400,2600,2800,3000,3500,4000,5000]
    }
  }
}

resource "google_storage_bucket" "chaindata_bucket" {
  name = "${var.google["project"]}-chaindata"
  location = "US"

  lifecycle_rule {
    condition {
      num_newer_versions = 10  # keep 10 copies of chaindata backups (use `gsutil ls -la $bucket` to see versioned objects)
    }
    action {
      type = "Delete"
    }
  }

  versioning {
      enabled = true
    }
}

resource "google_storage_bucket_iam_binding" "chaindata_binding_write" {
  bucket = "${var.google["project"]}-chaindata"
  role = "roles/storage.objectCreator"
  members = [
    "serviceAccount:${var.GCP_DEFAULT_SERVICE_ACCOUNT}",
  ]
}

resource "google_storage_bucket_iam_binding" "chaindata_binding_read" {
  bucket = "${var.google["project"]}-chaindata"
  role = "roles/storage.objectViewer"
  members = [
    "serviceAccount:${var.GCP_DEFAULT_SERVICE_ACCOUNT}",
  ]
}

resource "google_storage_bucket" "chaindata_rsync_bucket" {
  name = "${var.google["project"]}-chaindata-rsync"
  location = "US"

}

resource "google_storage_bucket_iam_binding" "chaindata_rsync_binding_write" {
  bucket = "${var.google["project"]}-chaindata-rsync"
  role = "roles/storage.objectCreator"
  members = [
    "serviceAccount:${var.GCP_DEFAULT_SERVICE_ACCOUNT}",
  ]
}

resource "google_storage_bucket_iam_binding" "chaindata_rsync_binding_read" {
  bucket = "${var.google["project"]}-chaindata-rsync"
  role = "roles/storage.objectViewer"
  members = [
    "serviceAccount:${var.GCP_DEFAULT_SERVICE_ACCOUNT}",
  ]
}
