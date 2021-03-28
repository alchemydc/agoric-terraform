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

variable instance_types {
  description = "The instance type for each component"
  type        = map(string)

  default = {
    validator           = "n1-standard-1"
    backup_node         = "n1-standard-1"
  }
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

variable validator_signer_account_addresses {
  type        = list(string)
  description = "Array with the Validator etherbase account addresses"
}

variable validator_signer_private_keys {
  type        = list(string)
  description = "Array with the Validator etherbase account private keys"
}

variable validator_signer_account_passwords {
  type        = list(string)
  description = "Array with the Validator etherbase account passwords"
}

variable reset_chain_data {
  type        = bool
  description = "Specifies if the existing chain data should be removed while creating the instance"
}



variable validator_name {
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