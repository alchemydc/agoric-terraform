#!/bin/bash

export HOME="/root"

# helpful packages
echo "Updating packages" | logger
apt update && apt -y upgrade
echo "Installing htop and screen" | logger
apt install -y htop screen wget

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
echo "Updating rsyslog.conf to avoid redundantly logging docker output" | logger
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
$EscapeControlCharactersOnReceive off
EOF

# ---- Restart rsyslogd
echo "Restarting rsyslogd" | logger
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
mkdir -p /root/.ag-chain-cosmos/backup
# backup only the data for now, not the config
#tar -C /root/.ag-chain-cosmos -zcvf /root/.ag-chain-cosmos/backup/chaindata.tgz data config
tar -C /root/.ag-chain-cosmos -zcvf /root/.ag-chain-cosmos/backup/chaindata.tgz data
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
# will backup config via rsync, since it's easy to selectively restore it or not
gsutil -m rsync -d -r /root/.ag-chain-cosmos/config  gs://${gcloud_project}-chaindata-rsync/config
gsutil -m rsync -d -r /root/.ag-chain-cosmos/data  gs://${gcloud_project}-chaindata-rsync/data
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

# do NOT enable crontab on the validator itself.  we'll want to run this from the backup node
# so as not to interrupt consensus service on the validator node.
#/usr/bin/crontab /root/backup.crontab

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
  mkdir -p /root/.ag-chain-cosmos/config
  mkdir -p /root/.ag-chain-cosmos/restore
  echo "downloading chaindata from gs://${gcloud_project}-chaindata/chaindata.tgz" | logger
  gsutil cp gs://${gcloud_project}-chaindata/chaindata.tgz /root/.ag-chain-cosmos/restore/chaindata.tgz
  echo "stopping agoric p2p/consensus daemon to untar chaindata" | logger
  systemctl stop ag-chain-cosmos.service
  sleep 3
  echo "untarring chaindata" | logger
  tar zxvf /root/.ag-chain-cosmos/restore/chaindata.tgz --directory /root/.ag-chain-cosmos
  echo "removing chaindata tarball" | logger
  rm -rf /root/.ag-chain-cosmos/restore/chaindata.tgz
  sleep 3
  # echo re-enable this after ensuring we can cleanly restarted daemon with restored data
  #echo "starting ag-chain-cosmos.service" | logger
  #systemctl start ag-chain-cosmos.service
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
gsutil -q stat gs://${gcloud_project}-chaindata-rsync/data/priv_validator_state.json
if [ $? -eq 0 ]
then
  #chaindata exists in bucket
  echo "stopping ag-chain-cosmos.service" | logger
  systemctl stop ag-chain-cosmos.service
  #echo "downloading chaindata via rsync from gs://${gcloud_project}-chaindata-rsync/config" | logger
  #mkdir -p /root/.ag-chain-cosmos/config
  #gsutil -m rsync -d -r gs://${gcloud_project}-chaindata-rsync /root/.ag-chain-cosmos/config
  mkdir -p /root/.ag-chain-cosmos/data
  gsutil -m rsync -d -r gs://${gcloud_project}-chaindata-rsync/data /root/.ag-chain-cosmos/data
  echo "restarting ag-chain-cosmos.service" | logger
  sleep 3
  systemctl start ag-chain-cosmos.service
  else
    echo "No chaindata found in bucket gs://${gcloud_project}-chaindata-rsync, aborting warp restore" | logger
  fi
EOF
chmod u+x /root/restore_rsync.sh

# ---- Create restore validator keys from rsync script
echo "Creating rsync validator keys restore script" | logger
cat <<'EOF' > /root/restore_validator_keys_rsync.sh
#!/bin/bash
set -x

# test to see if chaindata exists in the rsync chaindata bucket
gsutil -q stat gs://${gcloud_project}-chaindata-rsync/config/priv_validator_key.json
if [ $? -eq 0 ]
then
  #validator key exists in bucket
  echo "stopping ag-chain-cosmos.service" | logger
  systemctl stop ag-chain-cosmos.service
  echo "downloading validator keys from gs://${gcloud_project}-chaindata-rsync/config" | logger
  mkdir -p /root/.ag-chain-cosmos/config
  gsutil cp gs://${gcloud_project}-chaindata-rsync/config/priv_validator_key.json /root/.ag-chain-cosmos/config/
  gsutil cp gs://${gcloud_project}-chaindata-rsync/config/node_key.json /root/.ag-chain-cosmos/config/
  echo "to interactively restoring private key from mnemonic, "
  echo "ag-cosmos-helper keys add $KEY_NAME --recover"
  echo "and then"
  echo "ag-chain-cosmos init --chain-id ${agoric_node_release_tag} ${validator_name}"
  
  echo "do not forget to restart ag-chain-cosmos after importing keys, with 'systemctl start ag-chain-cosmos'"
  #echo "restarting ag-chain-cosmos.service" | logger
  #sleep 3
  #systemctl start ag-chain-cosmos.service
  else
    echo "No validator keys found in bucket gs://${gcloud_project}-chaindata-rsync, aborting restore" | logger
  fi
EOF
chmod u+x /root/restore_validator_keys_rsync.sh


# ---- Useful aliases ----
echo "Configuring aliases" | logger
echo "alias ll='ls -laF'" >> /etc/skel/.bashrc
echo "alias ll='ls -laF'" >> /root/.bashrc
echo "alias ag-status='ag-cosmos-helper status 2>&1 | jq .'" >> /root/.bashrc
echo "alias ag-status='ag-cosmos-helper status 2>&1 | jq .'" >> /etc/skel/.bashrc

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

echo "Setting up persistent disk ${attached_disk_name} at $DISK_PATH..." | logger

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
echo "Mounting $DISK_PATH onto $DATA_DIR" | logger
mkdir -p $DATA_DIR
DISK_UUID=$(blkid $DISK_PATH | cut -d '"' -f2)
echo "UUID=$DISK_UUID     $DATA_DIR   auto    discard,defaults    0    0" >> /etc/fstab
mount $DATA_DIR

# Remove existing chain data
[[ ${reset_chain_data} == "true" ]] && rm -rf $DATA_DIR/data

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

# warp restore scripts disabled until they're tested w/ the agoric chaindata format
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

# FIXME:parameterize these as variables and expose properly via terraform
# presently used for local firewall rules, which really should be controlled by variables
AGORIC_PROMETHEUS_HOSTNAME="prometheus.testnet.agoric.net"
AGORIC_PROMETHEUS_IP="142.93.181.215"
#AGORIC_PROMETHEUS_IP=`$AGORIC_PROMETHEUS_HOSTNAME | cut -d ' ' -f 4`
# following will expose Agoric VM (SwingSet) metrics globally on tcp/94643
# see https://github.com/Agoric/agoric-sdk/blob/master/packages/cosmic-swingset/README-telemetry.md for more info
OTEL_EXPORTER_PROMETHEUS_PORT=9464

# refresh packages and update all
apt update && apt upgrade -y

# Download the nodesource PPA for Node.js
echo "Installing nodejs and yarn" | logger
curl https://deb.nodesource.com/setup_14.x |  bash

# Download the Yarn repository configuration
# See instructions on https://legacy.yarnpkg.com/en/docs/install/
curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | apt-key add -
echo "deb https://dl.yarnpkg.com/debian/ stable main" |  tee /etc/apt/sources.list.d/yarn.list

# Update Ubuntu to pickup the yarn repo
apt update

# Install Node.js, Yarn, and build tools
# Install jq for formatting of JSON data
apt install nodejs=14.* yarn build-essential jq git nftables -y

# First remove any existing old Go installation
 rm -rf /usr/local/go

# Install correct Go version
echo "installing golang" | logger
curl https://dl.google.com/go/go1.15.7.linux-amd64.tar.gz |  tar -C/usr/local -zxvf -

# Update environment variables to include go
cat <<'EOF' >> $HOME/.profile
export GOROOT=/usr/local/go
export GOPATH=$HOME/go
export GO111MODULE=on
export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin
EOF
. $HOME/.profile

echo "checking out Agoric release from github" | logger
cd $DATA_DIR
git clone ${agoric_node_release_repository} -b ${agoric_node_release_tag}
cd agoric-sdk

echo "Install and build Agoric Javascript packages" | logger
yarn install
yarn build

echo "Install and build Agoric Cosmos SDK support" | logger
cd packages/cosmic-swingset && make

# test to see agoric SDK is correctly installed
echo "testing to see agoric SDK is correctly installed" | logger
ag-chain-cosmos version --long

cd $DATA_DIR
# First, get the network config for the current network.
curl ${network_uri}/network-config > chain.json
# Set chain name to the correct value
chainName=`jq -r .chainName < chain.json`
# Confirm value: should be something like agoricdev-N.
echo $chainName

# Replace <your_moniker> with the public name of your node.
# NOTE: The `--home` flag (or `AG_CHAIN_COSMOS_HOME` environment variable) determines where the chain state is stored.
# By default, this is `$HOME/.ag-chain-cosmos`.
#ag-chain-cosmos init --chain-id $chainName $MONIKER
ag-chain-cosmos init --chain-id $chainName ${validator_name}

# Download the genesis file
curl ${network_uri}/genesis.json > $DATA_DIR/config/genesis.json 
# Reset the state of your validator.
ag-chain-cosmos unsafe-reset-all

#backup state file
#cp $DATA_DIR/data/priv_validator_state.json /root/
#restore chain data from tarball
#/root/restore.sh
# restore state file
#cp -vf /root/priv_validator_state.json $DATA_DIR/data/priv_validator_state.json

# Set peers variable to the correct value
peers=$(jq '.peers | join(",")' < chain.json)
# Set seeds variable to the correct value.
seeds=$(jq '.seeds | join(",")' < chain.json)
# Confirm values, each should be something like "077c58e4b207d02bbbb1b68d6e7e1df08ce18a8a@178.62.245.23:26656,..."
echo $peers
echo $seeds
# Fix `Error: failed to parse log level`
#sed -i.bak 's/^log_level/# log_level/' $HOME/.ag-chain-cosmos/config/config.toml
sed -i.bak 's/^log_level/# log_level/' $DATA_DIR/config/config.toml
# Replace the seeds and persistent_peers values
#sed -i.bak -e "s/^seeds *=.*/seeds = $seeds/; s/^persistent_peers *=.*/persistent_peers = $peers/" $HOME/.ag-chain-cosmos/config/config.toml
sed -i.bak -e "s/^seeds *=.*/seeds = $seeds/; s/^persistent_peers *=.*/persistent_peers = $peers/" $DATA_DIR/config/config.toml

# set publicly reachable p2p addr in config.toml
sed -i.bak 's/external_address = ""/#external_address = ""/' $DATA_DIR/config/config.toml
echo "# external address to advertise to p2p network \n" >> $DATA_DIR/config/config.toml
echo "external_address = \"tcp://${validator_external_address}:26656\"" >> $DATA_DIR/config/config.toml

echo "Setting up ag-chain-cosmos service in systemd" | logger
tee <<EOF >/dev/null /etc/systemd/system/ag-chain-cosmos.service
[Unit]
Description=Agoric Cosmos daemon
After=network-online.target

[Service]
User=root
Environment="OTEL_EXPORTER_PROMETHEUS_PORT=9464"
Environment="SLOGFILE=$DATA_DIR/${validator_name}-${agoric_node_release_tag}-chain.slog"
ExecStart=/root/go/bin/ag-chain-cosmos start --log_level=info
Restart=on-failure
RestartSec=3
LimitNOFILE=4096

[Install]
WantedBy=multi-user.target
EOF

echo "Configuring firewall rules" | logger
 tee <<EOF >/dev/null /etc/nftables.conf
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
                ip saddr $AGORIC_PROMETHEUS_IP tcp dport { 9464, 9100, 26660} ct state new accept

                # accept neighbour discovery otherwise IPv6 connectivity breaks.
                #ip6 nexthdr icmpv6 icmpv6 type { nd-neighbor-solicit,  nd-router-advert, nd-neighbor-advert } accept

                # count and drop any other traffic
                counter drop
        }
}
EOF

# disabling lost based firewall for testing
#echo "Enabling firewall" | logger
#systemctl enable nftables.service
#systemctl start nftables.service

echo "configuring telemetry services" | logger
echo "telemetry: swingset enabled at on tcp/9464 and tendermint enabled on tcp/26660"
sed -i "s/prometheus = false/prometheus = true/" $DATA_DIR/config/config.toml

# start via systemd
echo "Setting ag-chain-cosmos to run from systemd" | logger
echo "systemctl status ag-chain-cosmos"
 systemctl enable ag-chain-cosmos
 systemctl daemon-reload
 systemctl start ag-chain-cosmos

# install prometheus node exporter
mkdir -p $HOME/prometheus
cd $HOME/prometheus
wget ${prometheus_exporter_tarball}
tar xvfz node_exporter-*.*-amd64.tar.gz
cd node_exporter-*.*-amd64
./node_exporter &    # fixme do this with systemd, and run as not root!

#--- remove compilers
#echo "Removing compilers and unnecessary packages" | logger
# apt remove -y build-essential gcc make linux-compiler-gcc-8-x86 cpp
# apt -y autoremove

# reinstall fluentd which is getting removed by something
# ---- Install Fluent Log Collector
echo "Installing google fluent log collector agent" | logger
#curl -sSO https://dl.google.com/cloudagents/add-logging-agent-repo.sh
#bash add-logging-agent-repo.sh
apt install -y google-fluentd
apt install -y google-fluentd-catch-all-config-structured
systemctl restart google-fluentd

echo "install completed, chain syncing" | logger
echo "for sync status: ag-cosmos-helper status 2>&1 | jq .SyncInfo"
echo "or check stackdriver logs for this instance"


