locals {
  attached_disk_name = "agoric-data-tmp"
  name_prefix = "${var.gcloud_project}-validator"
  snapshot = "${var.gcloud_project}-backup-node-agoric-data-disk-0-snapshot-latest" 
}

resource "google_compute_address" "validator" {
  name         = "${local.name_prefix}-address-${count.index}"
  address_type = "EXTERNAL"

  count = var.validator_count

  lifecycle {
    create_before_destroy = true
  }
}

resource "google_compute_address" "validator_internal" {
  name         = "${local.name_prefix}-internal-address-${count.index}"
  address_type = "INTERNAL"
  purpose      = "GCE_ENDPOINT"

  count = var.validator_count
}

resource "google_compute_disk" "validator-tmp" {
  name = "${local.attached_disk_name}-${count.index}"
  type = "pd-standard"    # use type = "pd-ssd" if I/O performance is insufficient
  size = var.data_disk_size
  snapshot = "${local.snapshot}"
  count = var.validator_count
}

resource "google_compute_instance" "validator" {
  name         = "${local.name_prefix}-${count.index}"
  machine_type = var.instance_type

  deletion_protection = true

  count = var.validator_count

  tags = ["${var.agoric_env}-validator"]

  labels = {
      env = "${var.agoric_env}"
      role = "validator"
  }

  allow_stopping_for_update = false

  boot_disk {
    initialize_params {
      image = var.cloud_image
      size = var.boot_disk_size
    }
  }

  attached_disk {
    source      = google_compute_disk.validator-tmp[count.index].self_link
    device_name = local.attached_disk_name
  }

  network_interface {
    network    = var.network_name
    network_ip = google_compute_address.validator_internal[count.index].address
    access_config {
      nat_ip = google_compute_address.validator[count.index].address
    }
  }

  metadata_startup_script = templatefile(
    format("%s/startup.sh", path.module), {
      attached_disk_name : local.attached_disk_name,
      block_time : var.block_time,
      agoric_node_release_repository : var.agoric_node_release_repository,
      agoric_node_release_tag : var.agoric_node_release_tag,
      network_uri : var.network_uri,
      ip_address : google_compute_address.validator[count.index].address,
      max_peers : var.validator_max_peers,
      network_id : var.network_id,
      validator_name : var.validator_name,
      gcloud_project : var.gcloud_project,
      reset_chain_data : var.reset_chain_data,
      rid : count.index,
      prometheus_exporter_tarball : var.prometheus_exporter_tarball,
      validator_external_address : google_compute_address.validator[count.index].address
    }
  )
  
  service_account {
    scopes = var.service_account_scopes
  }
}

resource "random_id" "validator" {
  count = var.validator_count
  byte_length = 2
}

