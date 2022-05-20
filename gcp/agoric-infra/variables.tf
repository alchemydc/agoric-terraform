variable block_time {
  type        = number
  description = "Number of seconds between each block"
}

variable agoric_env {
  type        = string
  description = "Name of the Agoric environment"
}

variable gcloud_project {
  type        = string
  description = "Name of the Google Cloud project to use"
}

variable gcloud_backup_project {
  description = "GCP backup project"
  type = string
  default = "MY_BACKUP_PROJECT_NAME"
}

variable instance_types {
  description = "The instance type for each component"
  type        = map(string)
}

variable "boot_disk_size" { 
  type = number
  description = "Size (in GB) of the ephemeral boot disk used for all instances"
}

variable "data_disk_size" { 
  type = number
  description = "Size (in GB) of the persistent data disk used for all instances"
}

variable "cloud_image" {
  type = string
  description = "image to use for creating compute instances"
}

variable agoric_node_release_repository {
  type        = string
  description = "Repository of the Agoric release"
}

variable agoric_node_release_tag {
  type        = string
  description = "Tag of the geth docker image"
}

variable network_id {
  type        = number
  description = "The network ID number"
}

variable network_name {
  type        = string
  description = "The name of the network to use"
}

variable network_uri {
  type        = string
  description = "The URI of the network to use"
}

variable backup_node_count {
  type        = number
  description = "Number of backup_nodes to create"
}

variable validator_count {
  type        = number
  description = "Number of validators to create"
}

# New vars
variable gcloud_region {
  type        = string
  description = "Name of the Google Cloud region to use"
}

variable gcloud_zone {
  type        = string
  description = "Name of the Google Cloud zone to use"
}

variable reset_chain_data {
  type        = bool
  description = "Specifies if the existing chain data should be removed while creating the instance"
}

variable validator_name {
  type        = string
  description = "The validator Name / moniker"
}

variable backup_node_name {
  type        = string
  description = "The validator Name / moniker"
}

variable "stackdriver_logging_exclusions" {
  description = "List of objects that define logs to exclude on stackdriver"
  type = map(object({
    description  = string
    filter       = string
  }))
}

variable "stackdriver_logging_metrics" {
  description = "List of objects that define COUNT (DELTA) logging metric filters to apply to Stackdriver to graph and alert on useful signals"
  type        = map(object({
    description = string
    filter      = string
  }))
}

variable "service_account_scopes" {
  description = "Scopes to apply to the service account which all nodes in the cluster will inherit"
  type        = list(string)
}

variable prometheus_exporter_tarball {
  type        = string
  description = "URI to download the prometheus node exporter from"
}