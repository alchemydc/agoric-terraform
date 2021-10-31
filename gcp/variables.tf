# Provide the next vars with a vars-file or modifying the default value
variable google {
  description = "The GCP Data"
  type        = map(string)

  default = {
    #update these in terraform.tfvars
    project = "MY_PROJECT_NAME"
    region  = "MY_REGION"
    zone    = "MY_ZONE"
  }
}

variable replicas {
  description = "The replica number for each component"
  type        = map(number)

  default = {
    validator           = 1 
    backup_node         = 0 
  }
}

variable instance_types {
  description = "The instance type for each component"
  type        = map(string)

  default = {
    validator           = "n1-standard-4"
    backup_node         = "n1-standard-4"
  }
}

variable network_name {
  description = "The name of the new VPC network created"
  type        = string

  default = "agoric-network"
}

variable agoric_env {
  description = "The Agoric network to connect with"
  type        = string

  default = "mainnet"
}

variable network_uri {
  description = "The URI for the Agoric network we are connecting to"
  type        = string
  default     = "https://testnet.agoric.net"
}

variable network_id {
  description = "The agoric network ID"
  type        = number
  default     = 31337
}

variable agoric_node_release {
  description = "The Agoric release"
  type        = map(string)

  default = {
    repository = "https://github.com/Agoric/agoric-sdk"
    tag        = "agorictest-17"
  }
}

variable validator_name {
  type        = string
  description = "The validator Name"
  default     = "YourValidator"
}

variable node_name {
  type        = string
  description = "The node Name /moniker"
  default     = "YourMoniker"
}

variable reset_chain_data {
  type        = bool
  description = "Specifies if the existing chain data should be removed while creating the instance"
  default     = true    #will restore chaindata from GCS if available
}

variable block_time {
  description = "The network block time (s)"
  type        = number
  default     = 5
}

variable "stackdriver_logging_exclusions" {
  description = "List of objects that define logs to exclude on stackdriver"
  type = map(object({
    description  = string
    filter       = string
  }))

  default = {
    tf_gcm_infinite = {
      description  = "Ignore stackdriver agent errors re: infinite values"
      filter       = "resource.type = gce_instance AND \"write_gcm: can not take infinite value\""
    }
  
    tf_gcm_swap = {
      description  = "Ignore stackdriver agent errors re: swap percent/value"
      filter       = "resource.type = gce_instance AND \"write_gcm: wg_typed_value_create_from_value_t_inline failed for swap/percent/value! Continuing\""
    }

    tf_gcm_invalid_time = {
      description  = "Ignore stackdriver agent errors related to timing"
      filter       = "resource.type = gce_instance AND \"write_gcm: Unsuccessful HTTP request 400\" AND \"The start time must be before the end time\""
    }

    tf_gcm_transmit_unique_segments = {
      description  = "Ignore stackdriver agent errors re: transmit_unique_segments"
      filter       = "resource.type = gce_instance AND \"write_gcm: wg_transmit_unique_segment\""
    }

    tf_ver_certs = {
      description  = "Ignore Eth peer flapping warnings caused by peers disconnecting naturally when exceeding max_peers"
      filter       = "resource.type = gce_instance AND \"Error sending all version certificates\""
    }
  
    tf_peer_conns = {
      description  = "Ignore Eth peer connections. Constant flux"
      filter       = "resource.type = gce_instance AND \"Ethereum peer connected\""
    }
  }
}

variable "stackdriver_logging_metrics" {
  description = "List of objects that define COUNT (DELTA) logging metric filters to apply to Stackdriver to graph and alert on useful signals"
  type        = map(object({
    description = string
    filter      = string
  }))

  default = {

    tf_eth_handshake_failed = {
      description = "Ethereum peer handshake failed"
       filter      = "resource.type=gce_instance AND \"Ethereum handshake failed\""
    }

    tf_eth_genesis_mismatch = {
      description = "Client with different genesis block attempted connection"
      filter      = "resource.type=gce_instance AND \"Genesis mismatch\""
    }

    tf_eth_block_ingested = {
      description = "Ethereum block(s) ingested"
      filter      = "resource.type=gce_instance AND \"blocks\" AND \"Imported new chain segment\""
    }

    # note that this log isn't firing anymore on successfully proposing a block (on 1.1.0) FIXME
    tf_eth_block_mined = {
      description = "Block mined"
      filter = "resource.type=gce_instance AND \"Successfully sealed new block\""
    }

    tf_eth_block_signed = {
      description = "Block signed"
      filter = "resource.type=gce_instance AND \"Commit new mining work\""
    }

    tf_eth_commit_old_block = {
      description = "Committed seal on old block"
      filter = "resource.type=gce_instance AND \"Would have sent a commit message for an old block\""
    }

    tf_validator_not_elected = {
      description = "Validator failed to be elected"
      filter = "resource.type=gce_instance \"Validator Election Results\" AND \"\\\"elected\\\":\\\"false\\\"\" AND NOT \"tx-node\""
    }

  }
}


variable "service_account_scopes" {
  description = "Scopes to apply to the service account which all nodes in the cluster will inherit"
  type        = list(string)

  #scope reference: https://cloud.google.com/sdk/gcloud/reference/alpha/compute/instances/set-scopes#--scopes
  #verify scopes: curl --silent --connect-timeout 1 -f -H "Metadata-Flavor: Google" http://169.254.169.254/computeMetadata/v1/instance/service-accounts/default/scopes
  default = [
    "https://www.googleapis.com/auth/monitoring.write",
    "https://www.googleapis.com/auth/logging.write",
    "https://www.googleapis.com/auth/cloud-platform"         #this gives r/w to all storage buckets, which is overly broad
    ]
}

variable "GCP_DEFAULT_SERVICE_ACCOUNT" {
  description = "gcp default service account for project, $projectid-compute@developer.gserviceaccount.com"
  type = string
}

variable prometheus_exporter_tarball {
  type        = string
  description = "URI to download the prometheus node exporter from"
  default = "https://github.com/prometheus/node_exporter/releases/download/v1.1.2/node_exporter-1.1.2.linux-amd64.tar.gz"
}