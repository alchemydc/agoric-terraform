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
    validator           = 0
    backup_node         = 1
  }
}

variable instance_types {
  description = "The instance type for each component"
  type        = map(string)

  default = {
    validator           = "n2d-standard-2"
    #backup_node         = "e2-medium"
    #backup_node         = "t2d-standard-1"
    #backup_node         = "n2d-standard-2"
    backup_node         = "t2d-standard-1"
  }
}

# e2-medium: 2vCPU, 4G RAM: $26mo [shared cpu]
# t2d-standard-1: 1vCPU, 4G RAM: $32/mo [dedicated EPYC cpu]
# t2d-standard-2: 2vCPU, 8G RAM: $63/mo [dedicated EPYC cpu]
# n2d-standard-2: 2vCPU, 8G RAM: $51/mo [dedicated EPYC cpu]
# note no n2d-standard-1 available


variable "boot_disk_size" { 
  type = number
  description = "Size (in GB) of the ephemeral boot disk used for all instances"
  default = 10
}

variable "data_disk_size" { 
  type = number
  description = "Size (in GB) of the persistent data disk used for all instances"
  default = 250
}

variable "cloud_image" {
  type = string
  description = "image to use for creating compute instances"
  default = "debian-cloud/debian-11"
}

variable network_name {
  description = "The name of the new VPC network created"
  type        = string
  default = "agoric-network"
}

variable agoric_env {
  description = "The Agoric network to connect with"
  type        = string
  default = "mainnet0"
}

variable network_uri {
  description = "The URI for the Agoric network we are connecting to"
  type        = string
  default     = "https://main.agoric.net"
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
    repository = "https://github.com/Agoric/ag0"
    tag        = "agoric-upgrade-5"
  }
}

variable validator_name {
  type        = string
  description = "The validator Name"
  default     = "YourValidatorMoniker"
}

variable backup_node_name {
  type        = string
  description = "The backup node Name / moniker"
  default     = "YourBackupNodeMoniker"
}

variable reset_chain_data {
  type        = bool
  description = "Specifies if the existing chain data should be removed while creating the instance"
  default     = false    #will restore chaindata from GCS if available
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

    tf_executed_block = {
      description = "Executed block"
       filter      = "resource.type=gce_instance AND \"executed block\""
    }
    
    tf_inbound_peer_rejected_auth_failure = {
      description = "Inbound peer rejected due to auth failure"
       filter      = "resource.type=gce_instance AND \"Inbound Peer rejected\" AND \"auth failure: secret conn failed\" OR \"auth failure: handshake failed\""
    }

    tf_inbound_peer_rejected_filtered = {
      description = "Inbound peer rejected due to filtered [eg duplicate conn]"
       filter      = "resource.type=gce_instance AND \"Inbound Peer rejected\" AND \"filtered CONN\" AND \"duplicate CONN\""
    }

    tf_consensus_timeouts = {
      description = "Time out from consensus module"
       filter      = "resource.type=gce_instance AND \"Timed out\" AND \"consensus\""
    }

    #tf_validator_not_elected = {
    #  description = "Validator failed to be elected"
    #  filter = "resource.type=gce_instance \"Validator Election Results\" AND \"\\\"elected\\\":\\\"false\\\"\" AND NOT \"tx-node\""
    #}

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