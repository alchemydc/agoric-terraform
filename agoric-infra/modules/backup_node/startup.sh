#!/bin/bash


# ---- Configure logrotate ----
echo "Configuring logrotate" | logger
cat <<'EOF' > '/etc/logrotate.d/rsyslog'
/var/log/syslog
/var/log/mail.info
/var/log/mail.warn
/var/log/mail.err
/var/log/mail.log
/var/log/daemon.log
/var/log/kern.log
/var/log/auth.log
/var/log/user.log
/var/log/lpr.log
/var/log/cron.log
/var/log/debug
/var/log/messages
{
        rotate 3
        daily
        missingok
        notifempty
        delaycompress
        compress
        sharedscripts
        postrotate
                #invoke-rc.d rsyslog rotate > /dev/null   # does not work on debian10
                kill -HUP `pidof rsyslogd`
        endscript
}
EOF

# ---- Tune rsyslog to avoid redundantly logging docker output
echo "Updating rsyslog.conf to avoid redundantly logging docker output"
cat <<'EOF' > /etc/rsyslog.conf
# /etc/rsyslog.conf configuration file for rsyslog
#
# For more information install rsyslog-doc and see
# /usr/share/doc/rsyslog-doc/html/configuration/index.html

#################
#### MODULES ####
#################

module(load="imuxsock") # provides support for local system logging
module(load="imklog")   # provides kernel logging support

###########################
#### GLOBAL DIRECTIVES ####
###########################

#
# Use traditional timestamp format.
# To enable high precision timestamps, comment out the following line.
#
$ActionFileDefaultTemplate RSYSLOG_TraditionalFileFormat

#
# Set the default permissions for all log files.
#
$FileOwner root
$FileGroup adm
$FileCreateMode 0640
$DirCreateMode 0755
$Umask 0022

#
# Where to place spool and state files
#
$WorkDirectory /var/spool/rsyslog

#
# Include all config files in /etc/rsyslog.d/
#
$IncludeConfig /etc/rsyslog.d/*.conf


###############
#### RULES ####
###############

#
# First some standard log files.  Log by facility.
#
auth,authpriv.*                 /var/log/auth.log
*.*;auth,authpriv.none          -/var/log/syslog
kern.*                          -/var/log/kern.log


#
# Some "catch-all" log files.
#
*.=debug;\
        auth,authpriv.none;\
        news.none;mail.none     -/var/log/debug
*.=info;*.=notice;*.=warn;\
        auth,authpriv.none;\
        cron,daemon.none;\
        mail,news.none          -/var/log/messages

#
# Emergencies are sent to everybody logged in.
#
*.emerg                         :omusrmsg:*
EOF

# ---- Restart rsyslogd
echo "Restarting rsyslogd"
systemctl restart rsyslog

# ---- Create backup script
echo "Creating chaindata backup script" | logger
cat <<'EOF' > /root/backup.sh
#!/bin/bash
# This script stops the agoric p2p/consensus daemon, tars up the chaindata (with gzip compression), and copies it to GCS.
# The 'chaindata' GCS bucket has versioning enabled, so if a corrupted tarball is uploaded, an older version can be selected for restore.
# This takes quit some time, and takes quite a bit of local disk.
# The rsync variant (below) is more efficient, but tarballs are more portable.
set -x

echo "Starting chaindata backup" | logger
systemctl stop ag-chain-cosmos.service
sleep 5
# FIXME: not sure if anything else in .ag-chain-cosmos/data can be backed up to speed bootstrapping of new nodes
tar -C /root/.ag-chain-cosmos/data -zcvf /root/.ag-chain-cosmos/backup/chaindata.tgz ag-cosmos-chain-state
gsutil cp /root/.ag-chain-cosmos/backup/chaindata.tgz gs://${gcloud_project}-chaindata
rm -f /root/.ag-chain-cosmos/backup/chaindata.tgz
echo "Chaindata backup completed" | logger
sleep 3
systemctl start ag-chain-cosmos.service
EOF
chmod u+x /root/backup.sh

# ---- Create rsync backup script
echo "Creating rsync chaindata backup script" | logger
cat <<'EOF' > /root/backup_rsync.sh
#!/bin/bash
# This script stops agoric p2p/consensus daemon, and uses rsync to copy chaindata to GCS.
set -x

echo "Starting rsync chaindata backup" | logger
systemctl stop ag-chain-cosmos.service
sleep 5
gsutil -m rsync -d -r /root/.ag-chain-cosmos/data/ag-cosmos-chain-state chaindata gs://${gcloud_project}-chaindata-rsync
echo "rsync chaindata backup completed" | logger
sleep 3
systemctl start ag-chain-cosmos.service
EOF
chmod u+x /root/backup_rsync.sh

# ---- Add backups to cron
# note that this will make the backup_node geth unavailable during the backup, which is why
# we run this on a dedicated backup node now instead of the attestation service txnode
cat <<'EOF' > /root/backup.crontab
# m h  dom mon dow   command
# backup full tarball once a day at 00:57
57 0 * * * /root/backup.sh > /dev/null 2>&1
# backup via rsync run every six hours at 00:17 past the hour
17 */6 * * * /root/backup_rsync.sh > /dev/null 2>&1
EOF
/usr/bin/crontab /root/backup.crontab

# ---- Create restore script
echo "Creating chaindata restore script" | logger
cat <<'EOF' > /root/restore.sh
#!/bin/bash
set -x

# test to see if chaindata exists in bucket
gsutil -q stat gs://${gcloud_project}-chaindata/chaindata.tgz
if [ $? -eq 0 ]
then
  #chaindata exists in bucket
  mkdir -p /root/.ag-chain-cosmos/data
  mkdir -p /root/.ag-chain-cosmos/restore
  echo "downloading chaindata from gs://${gcloud_project}-chaindata/chaindata.tgz" | logger
  gsutil cp gs://${gcloud_project}-chaindata/chaindata.tgz /root/.ag-chain-cosmos/restore/chaindata.tgz
  echo "stopping agoric p2p/consensus daemon to untar chaindata" | logger
  systemctl stop ag-chain-cosmos.service
  sleep 3
  echo "untarring chaindata" | logger
  tar zxvf /root/.ag-chain-cosmos/restore/chaindata.tgz --directory /root/.ag-chain-cosmos/data/ag-cosmos-chain-state
  echo "removing chaindata tarball" | logger
  rm -rf /root/.ag-chain-cosmos/restore/chaindata.tgz
  sleep 3
  echo "starting ag-chain-cosmos.service" | logger
  systemctl start ag-chain-cosmos.service
  else
    echo "No chaindata.tgz found in bucket gs://${gcloud_project}-chaindata, aborting warp restore" | logger
  fi
EOF
chmod u+x /root/restore.sh

# ---- Create rsync restore script
echo "Creating rsync chaindata restore script" | logger
cat <<'EOF' > /root/restore_rsync.sh
#!/bin/bash
set -x

# test to see if chaindata exists in the rsync chaindata bucket
gsutil -q stat gs://${gcloud_project}-chaindata-rsync/CURRENT
if [ $? -eq 0 ]
then
  #chaindata exists in bucket
  echo "stopping ag-chain-cosmos.service" | logger
  systemctl stop ag-chain-cosmos.service
  echo "downloading chaindata via rsync from gs://${gcloud_project}-chaindata-rsync" | logger
  mkdir -p /root/.ag-chain-cosmos/data/ag-cosmos-chain-state
  gsutil -m rsync -d -r gs://${gcloud_project}-chaindata-rsync /root/.ag-chain-cosmos/data/ag-cosmos-chain-state
  echo "restarting ag-chain-cosmos.service" | logger
  sleep 3
  systemctl start ag-chain-cosmos.service
  else
    echo "No chaindata found in bucket gs://${gcloud_project}-chaindata-rsync, aborting warp restore" | logger
  fi
EOF
chmod u+x /root/restore_rsync.sh

# ---- Useful aliases ----
echo "Configuring aliases" | logger
echo "alias ll='ls -laF'" >> /etc/skel/.bashrc
echo "alias ll='ls -laF'" >> /root/.bashrc
echo "alias gattach='docker exec -it geth geth attach'" >> /etc/skel/.bashrc

# ---- Install Stackdriver Agent
echo "Installing Stackdriver agent" | logger
curl -sSO https://dl.google.com/cloudagents/add-monitoring-agent-repo.sh
bash add-monitoring-agent-repo.sh
apt update -y
apt install -y stackdriver-agent
systemctl restart stackdriver-agent

# ---- Install Fluent Log Collector
echo "Installing google fluent log collector agent" | logger
curl -sSO https://dl.google.com/cloudagents/add-logging-agent-repo.sh
bash add-logging-agent-repo.sh
apt update -y
apt install -y google-fluentd
apt install -y google-fluentd-catch-all-config-structured
systemctl restart google-fluentd

# ---- Setup swap
echo "Setting up swapfile" | logger
fallocate -l 1G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
swapon -s

# ---- Set Up Persistent Disk ----

# gives a path similar to `/dev/sdb`
DISK_PATH=$(readlink -f /dev/disk/by-id/google-${attached_disk_name})
DATA_DIR=/root/.ag-chain-cosmos

echo "Setting up persistent disk ${attached_disk_name} at $DISK_PATH..."

DISK_FORMAT=ext4
CURRENT_DISK_FORMAT=$(lsblk -i -n -o fstype $DISK_PATH)

echo "Checking if disk $DISK_PATH format $CURRENT_DISK_FORMAT matches desired $DISK_FORMAT..."

# If the disk has already been formatted previously (this will happen
# if this instance has been recreated with the same disk), we skip formatting
if [[ $CURRENT_DISK_FORMAT == $DISK_FORMAT ]]; then
  echo "Disk $DISK_PATH is correctly formatted as $DISK_FORMAT"
else
  echo "Disk $DISK_PATH is not formatted correctly, formatting as $DISK_FORMAT..."
  mkfs.ext4 -m 0 -F -E lazy_itable_init=0,lazy_journal_init=0,discard $DISK_PATH
fi

# Mounting the volume
echo "Mounting $DISK_PATH onto $DATA_DIR"
mkdir -p $DATA_DIR
DISK_UUID=$(blkid $DISK_PATH | cut -d '"' -f2)
echo "UUID=$DISK_UUID     $DATA_DIR   auto    discard,defaults    0    0" >> /etc/fstab
mount $DATA_DIR

# Remove existing chain data
[[ ${reset_chain_data} == "true" ]] && rm -rf $DATA_DIR/.ag-chain-cosmos/data
#mkdir -p $DATA_DIR/account

# ---- Install Docker ----

#echo "Installing Docker..." | logger
#apt update -y && apt upgrade -y
#apt install -y apt-transport-https ca-certificates curl software-properties-common gnupg2 htop screen
#curl -fsSL https://download.docker.com/linux/debian/gpg | apt-key add -
#add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/debian $(lsb_release -cs) stable"
#apt update -y && apt upgrade -y
#apt install -y docker-ce
#apt upgrade -y
#systemctl start docker

# ---- Config /etc/screenrc ----
echo "Configuring /etc/screenrc" | logger
cat <<'EOF' >> '/etc/screenrc'
bindkey -k k1 select 1  #  F1 = screen 1
bindkey -k k2 select 2  #  F2 = screen 2
bindkey -k k3 select 3  #  F3 = screen 3
bindkey -k k4 select 4  #  F4 = screen 4
bindkey -k k5 select 5  #  F5 = screen 5
bindkey -k k6 select 6  #  F6 = screen 6
bindkey -k k7 select 7  #  F7 = screen 7
bindkey -k k8 select 8  #  F8 = screen 8
bindkey -k k9 select 9  #  F9 = screen 9
bindkey -k F1 prev      # F11 = prev
bindkey -k F2 next      # F12 = next
EOF

#echo "Configuring Docker..." | logger
#cat <<'EOF' > '/etc/docker/daemon.json'
#{
#  "log-driver": "json-file",
#  "log-opts": {
#    "max-size": "10m",
#    "max-file": "3",
#    "mode": "non-blocking"
#  }
#}
#EOF

#echo "Restarting docker" | logger
#systemctl restart docker

# ---- Set Up and Run Geth ----
#
#echo "Configuring Geth" | logger
#
#GETH_NODE_DOCKER_IMAGE=${geth_node_docker_image_repository}:${geth_node_docker_image_tag}
#
#echo "Pulling geth..."
#docker pull $GETH_NODE_DOCKER_IMAGE

#IN_MEMORY_DISCOVERY_TABLE_FLAG=""
#[[ ${in_memory_discovery_table} == "true" ]] && IN_MEMORY_DISCOVERY_TABLE_FLAG="--use-in-memory-discovery-table"

# Load configuration to files
#mkdir -p $DATA_DIR/account
#
#echo -n '${rid}' > $DATA_DIR/replica_id
#echo -n '${ip_address}' > $DATA_DIR/ipAddress
#

#cat <<EOF >/etc/systemd/system/geth.service
#[Unit]
#Description=Docker Container %N
#Requires=docker.service
#After=docker.service
#
#[Service]
#Restart=always
#ExecStart=/usr/bin/docker run \\
#  --rm \\
#  --name geth \\
#  --net=host \\
#  -v $DATA_DIR:$DATA_DIR \\
#  --entrypoint /bin/sh \\
#  $GETH_NODE_DOCKER_IMAGE -c "\\
#    geth \\
#      --nousb \\
#      --maxpeers ${max_peers} \\
#      --rpc \\
#      --rpcapi=eth,net,web3 \\
#      --networkid=${network_id} \\
#      --syncmode=full \\
#      --consoleformat=json \\
#      --consoleoutput=stdout \\
#      --verbosity=${geth_verbosity} \\
#      --nat=extip:${ip_address} \\
#      --metrics \\
#      --pprof \\
#      $IN_MEMORY_DISCOVERY_TABLE_FLAG \\
#      --light.serve 0 \\
#  "
#ExecStop=/usr/bin/docker stop -t 60 %N

#[Install]
#WantedBy=default.target
#EOF

#echo "Adding DC to docker group" | logger
#usermod -aG docker dc

# --- run restore script
# this script tries to restore chaindata from a GCS hosted tarball.
# if the chaindata doesn't exist on GCS, geth will start normal (slow) p2p sync
#echo "Attempting to restore chaindata from backup tarball"
#bash /root/restore.sh

# todo: add some logic to look at the chaindata tarball bucket versus the rsync bucket and pick the best one.
# for now we try both, with rsync taking precedence b/c it runs last.

# --- run rsync restore script
# this script tries to restore chaindata from a GCS hosted bucket via rsync.
# if the chaindata doesn't exist on GCS, geth will start normal (slow) p2p sync, perhaps boosted by what the tarball provided
#echo "Attempting to restore chaindata from backup via rsync"
#bash /root/restore_rsync.sh

#echo "Starting Geth"
#systemctl daemon-reload
#systemctl enable geth.service


# FIXME:parameterize these as variables and expose properly via terraform
GIT_BRANCH="@agoric/sdk@2.15.1"
MONIKER="ElectricCoinCo"    # fixme
BASE_URI="https://testnet.agoric.net"
AGORIC_PROMETHEUS_HOSTNAME="prometheus.testnet.agoric.net"
#AGORIC_PROMETHEUS_IP="142.93.181.215"
AGORIC_PROMETHEUS_IP=`$AGORIC_PROMETHEUS_HOSTNAME | cut -d ' ' -f 4`
# following will expose Agoric VM (SwingSet) metrics globally on tcp/94643
# see https://github.com/Agoric/agoric-sdk/blob/master/packages/cosmic-swingset/README-telemetry.md for more info
export OTEL_EXPORTER_PROMETHEUS_PORT=9464

# refresh packages and update all
sudo apt update && sudo apt upgrade -y

# Download the nodesource PPA for Node.js
curl https://deb.nodesource.com/setup_12.x | sudo bash

# Download the Yarn repository configuration
# See instructions on https://legacy.yarnpkg.com/en/docs/install/
curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | sudo apt-key add -
echo "deb https://dl.yarnpkg.com/debian/ stable main" | sudo tee /etc/apt/sources.list.d/yarn.list

# Update Ubuntu
sudo apt update

# Install Node.js, Yarn, and build tools
# Install jq for formatting of JSON data
sudo apt install nodejs=12.* yarn build-essential jq git nftables -y

# remove unneeded packages
sudo apt -y autoremove

# First remove any existing old Go installation
sudo rm -rf /usr/local/go

# Install correct Go version
curl https://dl.google.com/go/go1.15.7.linux-amd64.tar.gz | sudo tar -C/usr/local -zxvf -

# Update environment variables to include go
cat <<'EOF' >>$HOME/.profile
export GOROOT=/usr/local/go
export GOPATH=$HOME/go
export GO111MODULE=on
export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin
EOF
source $HOME/.profile

git clone https://github.com/Agoric/agoric-sdk -b ${GIT_BRANCH}
cd agoric-sdk

# Install and build Agoric Javascript packages
yarn install
yarn build

# Install and build Agoric Cosmos SDK support
cd packages/cosmic-swingset && make

# test to see agoric SDK is correctly installed
echo "testing to see agoric SDK is correctly installed"
ag-chain-cosmos version --long

mkdir ~/validator
cd ~/validator

# First, get the network config for the current network.
curl ${BASE_URI}/network-config > chain.json
# Set chain name to the correct value
chainName=`jq -r .chainName < chain.json`
# Confirm value: should be something like agoricdev-N.
echo $chainName

# Replace <your_moniker> with the public name of your node.
# NOTE: The `--home` flag (or `AG_CHAIN_COSMOS_HOME` environment variable) determines where the chain state is stored.
# By default, this is `$HOME/.ag-chain-cosmos`.
ag-chain-cosmos init --chain-id $chainName ${MONIKER}

# Download the genesis file
curl ${BASE_URI}/genesis.json > $HOME/.ag-chain-cosmos/config/genesis.json 
# Reset the state of your validator.
ag-chain-cosmos unsafe-reset-all

# Set peers variable to the correct value
peers=$(jq '.peers | join(",")' < chain.json)
# Set seeds variable to the correct value.
seeds=$(jq '.seeds | join(",")' < chain.json)
# Confirm values, each should be something like "077c58e4b207d02bbbb1b68d6e7e1df08ce18a8a@178.62.245.23:26656,..."
echo $peers
echo $seeds
# Fix `Error: failed to parse log level`
sed -i.bak 's/^log_level/# log_level/' $HOME/.ag-chain-cosmos/config/config.toml
# Replace the seeds and persistent_peers values
sed -i.bak -e "s/^seeds *=.*/seeds = $seeds/; s/^persistent_peers *=.*/persistent_peers = $peers/" $HOME/.ag-chain-cosmos/config/config.toml

echo "Setting up ag-chain-cosmos service in systemd"
sudo tee <<EOF >/dev/null /etc/systemd/system/ag-chain-cosmos.service
[Unit]
Description=Agoric Cosmos daemon
After=network-online.target

[Service]
User=$USER
Environment="OTEL_EXPORTER_PROMETHEUS_PORT=9464"
ExecStart=$HOME/go/bin/ag-chain-cosmos start --log_level=warn
Restart=on-failure
RestartSec=3
LimitNOFILE=4096

[Install]
WantedBy=multi-user.target
EOF

echo "Configuring firewall rules"
sudo tee <<EOF >/dev/null /etc/nftables.conf
#!/usr/sbin/nft -f

flush ruleset

table inet filter {
        chain input {
                type filter hook input priority 0;

                # accept any localhost traffic
                iif lo accept

                # accept traffic originated from us
                ct state established,related accept

                # activate the following line to accept common local services
                tcp dport { 22, 26656 } ct state new accept

                # permit prometheus access to telemetry ports but ONLY from agoric
                ip saddr $AGORIC_PROMETHEUS_IP tcp dport { 9464, 26660} ct state new accept

                # accept neighbour discovery otherwise IPv6 connectivity breaks.
                #ip6 nexthdr icmpv6 icmpv6 type { nd-neighbor-solicit,  nd-router-advert, nd-neighbor-advert } accept

                # count and drop any other traffic
                counter drop
        }
}
EOF

echo "Enabling firewall"
sudo systemctl enable nftables.service
sudo systemctl start nftables.service

# Check the contents of the file, especially User, Environment and ExecStart lines
cat /etc/systemd/system/ag-chain-cosmos.service

# configure telemetry
echo "telemetry: swingset enabled at on tcp/9464 and tendermint enabled on tcp/26660"
sed -i "s/prometheus = false/prometheus = true/" $HOME/.ag-chain-cosmos/config/config.toml

# start from console
echo "to start from console: "
echo "ag-chain-cosmos start --log_level=warn"

# start via systemd
echo "Setting ag-chain-cosmos to run from systemd"
echo "systemctl status ag-chain-cosmos"
sudo systemctl enable ag-chain-cosmos
sudo systemctl daemon-reload
sudo systemctl start ag-chain-cosmos

echo "install completed, chain syncing"
echo "for sync status: ag-cosmos-helper status 2>&1 | jq .SyncInfo"

#echo "Now you need to interactively create keys"
#echo "ag-cosmos-helper keys add <your-key-name>"
#echo "To see a list of wallets on your node run: ag-cosmos-helper keys list"
#echo "Tap the faucet: !faucet delegate agoric1... [nb: use agoric address, not pubkey]"
#echo "check balance as follows: "
#echo "ag-cosmos-helper query bank balances `ag-cosmos-helper keys show -a <your-key-name>`"
#echo "follow instructions here to finish registering validator: https://github.com/Agoric/agoric-sdk/wiki/Validator-Guide"

#echo "also don't forget to `source $HOME/.profile`"




#--- remove compilers
echo "Removing compilers" | logger
sudo apt remove -y build-essential gcc make linux-compiler-gcc-8-x86 cpp
sudo apt -y autoremove