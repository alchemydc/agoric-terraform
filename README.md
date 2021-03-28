# agoric-terraform
Terraform module for creating and managing Agoric infrastructure

## Overview

[Terraform](https://www.terraform.io) is a tool by Hashicorp that allows developers to treat _"infrastructure as code"_, easying the management and repeatibility of the infrastructure.  

Infrastructure and all kind of cloud resources are defined in modules, and Terraform creates/changes/destroys resources when changes are applied.

Inside the [agoric-infra](./agoric-infra) folder you will find a module (and submodules) to create the setup for running an Agoric Validator on Google Cloud Platform. The following resources can be created via these modules:

- `validator` module for deploying a Validator which peers with Agoric nodes over the p2p network and participates in consensus
- `backup-node` for deploying a full node which is used to create regular backups of chain data to Google Cloud Storage (GCS) without disturbing the Validator.  These backups can be used to bootstrap additional validators or full nodes without waiting for p2p sync, and can be very useful for disaster recovery.

The validator and backup-node services expose metrics for collection via Prometheus or similar.  See [docs/metrics.md](./docs/metrics.md) for more info.

## Stackdriver Logging, Monitoring and Alerting
Support for GCP's Stackdriver platform has been added, which makes it easy to get visibility into how your Agoric validator stack is performing.

## Quick start
1. Clone this repo
  ```console
  git clone https://github.com/alchemydc/agoric-terraform.git
  ```
2. Install dependencies
   OSX (assumes [Brew](https://brew.sh/) is installed):
   ```console
   brew update && brew install terraform google-cloud-sdk
   ```

   Linux
   Install [Google Cloud SDK](https://cloud.google.com/sdk/docs/install#linux)

   Install Terraform
   ```console
   sudo apt update && sudo apt install terraform
   ```

3. Authenticate the gcloud SDK
   ```console
  gcloud auth login
  ```
  This will spawn a browser window and use Oauth to authenticate the gcloud sdk to your GCP account.

4. Run bootstrap.sh
   ```console
    ./bootstrap.sh
   ```
   This will create a template gcloud.env for you.

5. Edit gcloud.env and set
    * 'TF_VAR_project' to the name of the GCP project to create
    * 'TF_VAR_org_id' to your gcloud org ID, which can be found by running `gcloud organizations list`
    * 'TF_VAR_billing_account' to your gcloud billing account, which can be found by running `gcloud beta billing accounts list`

6. Run bootstrap.sh again to initialize your new GCP project and enable appropriate API's
    ```console
    ./bootstrap.sh
    ```

    Note that when this completes, you need to `source gcloud.env` again in order to import the newly created GCP service account which terraform will use.

7. Set project, region and zone in terraform.tfvars

8. Initialize terraform
    `terraform init`

9. Use terraform to deploy Agoric infrastructure
    `terraform apply`


