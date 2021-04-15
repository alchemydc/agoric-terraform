variable block_time {
  type        = number
  description = "Number of seconds between each block"
}

variable agoric_env {
  type        = string
  description = "Name of the agoric environment"
}

variable gcloud_project {
  type        = string
  description = "Name of the Google Cloud project to use"
}

variable instance_type {
  description = "The instance type"
  type        = string
  default     = "n1-standard-1"
}

variable agoric_node_release_repository {
  type        = string
  description = "Repository of the agoric release"
}

variable agoric_node_release_tag {
  type        = string
  description = "Tag of the agoric release"
}

variable network_id {
  type        = number
  description = "The network ID number"
}

variable network_name {
  type        = string
  description = "Name of the GCP network the node VM is in"
}

variable network_uri {
  type        = string
  description = "URI for the Agoric network"
}

variable validator_count {
  type        = number
  description = "Number of validators to create"
}

variable reset_chain_data {
  type        = bool
  description = "Specifies if the existing chain data should be removed while creating the instance"
  default     = true
}

variable validator_max_peers {
  type        = number
  description = "Max number of peers to connect with"
  default     = 120
}

variable validator_name {
  type        = string
  description = "The validator Name"
}

variable service_account_scopes {
  type        = list(string)
  description = "Scopes to apply to the service account which all nodes in the cluster will inherit"
}