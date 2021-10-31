locals {
  attached_disk_name = "agoric-data"
  name_prefix = "${var.gcloud_project}-validator"
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

resource "google_compute_instance" "validator" {
  name         = "${local.name_prefix}-${count.index}"
  machine_type = var.instance_type

  deletion_protection = false

  count = var.validator_count

  tags = ["${var.agoric_env}-validator"]

  allow_stopping_for_update = true

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
      size = 10
    }
  }

  attached_disk {
    source      = google_compute_disk.validator[count.index].self_link
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

resource "google_compute_disk" "validator" {
  name  = "${local.name_prefix}-agoric-data-disk-${count.index}"
  count = var.validator_count

  #type = "pd-ssd"
  type = "pd-standard"      #disk I/O doesn't yet warrant SSD backed validators
  # in GB
  size                      = 100
  physical_block_size_bytes = 4096
}