# agoric-terraform
Terraform module for creating and managing Agoric infrastructure.  Presently GCP is supported.  AWS support is not yet implemented in this project.  Take a look at [this project](https://github.com/novy4/agoric-tools) for AWS support in the meantime.

## Overview

[Terraform](https://www.terraform.io) is a tool by Hashicorp that allows developers to treat _"infrastructure as code"_, which makes the management and repeatibility of the infrastructure much easier.  

Infrastructure and all kinds of cloud resources (such as firewalls) are defined in modules, and Terraform creates/changes/destroys resources when changes are applied.

Inside the [agoric-infra](./agoric-infra) folder you will find a module (and submodules) to create the infastructure required for running an Agoric Validator on Google Cloud Platform. The following resources can be created via these modules:

- `validator` module for deploying a Validator which peers with Agoric nodes over the p2p network and participates in consensus.
- `backup-node` for deploying a full node which is used to create regular backups of chain data to Google Cloud Storage (GCS) without disturbing the Validator.  These backups can be used to bootstrap additional validators or full nodes without waiting for p2p sync, and can be very useful for disaster recovery.

The validator and backup-node services expose metrics for collection via Prometheus or similar.  See [docs/metrics.md](./docs/metrics.md) for more info.

## Stackdriver Logging, Monitoring and Alerting
Support for GCP's Stackdriver platform has been enabled, which makes it easy to get visibility into how your Agoric validator stack is performing.

## Quick start
1. Clone this repo
  ```console
  git clone https://github.com/alchemydc/agoric-terraform.git
  ```
2. Install dependencies
   * OSX
     (assumes [Brew](https://brew.sh/) is installed):
     ```console
     brew update && brew install terraform google-cloud-sdk
     ```

   * Linux
     * Install [Google Cloud SDK](https://cloud.google.com/sdk/docs/install#linux)

     * Install Terraform
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


## Troubleshooting
* If you get "Error retrieving IAM policy for storage bucket" errors from Terraform, these are likely due to a race condition. Simply re-run terraform apply.

* `Error: Incompatible provider version

  Provider registry.terraform.io/hashicorp/google v3.61.0 does not have a
  package available for your current platform, darwin_arm64.`

  Apple Mac arm64 (M1) users presently will not be able to use Terraform to deploy infrastructure on GCP until the arm64 release of this provider is cut, which is expected any day now (as of 29 March 2021)

## Stackdriver Monitoring Dashboard
There presently is no support for creating Stackdriver monitoring dashboards via Terraform So instead we have use the gcloud cli to import the dashboard from a json file

`gcloud monitoring dashboards create --config-from-file=dashboards/hud.json`

## Known Issues
* Firewall is created in GCP VPC.  Host based rules (nftables) are also created (to /etc/nftables.conf) are and now activated by default, so check these if you're having weird issues.
* Consensus Key management (backup/restore/etc) is now implemented naively via shell scripts and rsync.  For production usage use a [KMS](https://github.com/iqlusioninc/tmkms?utm_source=pocket_mylist)
* Secrets management is not yet implmemented.  For now sensitive data is stored locally in terraform.tfvars, so it's not checked into git.  However, any secrets will be in the clear in the instance metadata, which is suboptimal.  Longer term we should look at Vault or similar for secrets management.


## Cheatsheet
* How many peers am I connected to? `curl -s 127.0.0.1:26657/net_info  | grep n_peers`
* Restore key from mnemonic: `ag0 keys add $KEY_NAME --recover`
* See node status: `ag0 status | jq .`
* Check out the [explorer](https://https://agoric.bigdipper.live/)
* Unjail your validator: `ag0 tx slashing unjail --broadcast-mode=block --from=$YOUR_agoric1address --chain-id=agoric-3 --gas=auto --gas-adjustment=1.4`
* Run the node interactively (rather than from systemd): `ag0 start`
* See remote peers: `curl -s 127.0.0.1:26657/net_info | jq .result.peers | grep remote`
* Check your balance: `ag0 query bank balances `ag0 keys show -a $YOUR_KEY_NAME`
* Send funds: `ag-chain-cosmos tx bank send --chain-id agoric-3 --keyring-dir ~/.ag0 "$FROM_KEY_NAME" "$TO_KEY_NAME" 1uagstake
* Edit your validator details after creation: `ag0 tx staking edit-validator --from "$KEY_NAME" --chain-id "agoric-3" --moniker "YourValidatorMoniker" --website "https://yoursite.org" --details "your_details" --keyring-dir ~/.ag0/
* expand disk to accomodate ever growing blockchain:
  * `gcloud compute disks resize $DISK_NAME --size 300G --region $REGION` 
  * on node: `sudo resize2fs /dev/sdb` 
* See how much voting power has supported an upgrade: `agoric@agoric-mainnet-validator-0:~$ curl -s localhost:26657/consensus_state | jq -r ".result.round_state.height_vote_set[0].prevotes_bit_array"`

## Credit
To [Javier Cortejoso](https://github.com/jcortejoso) at Clabs who created the [framework](https://github.com/alchemydc/celo-monorepo/tree/master/packages/terraform-modules-public) upon which this code is based.
