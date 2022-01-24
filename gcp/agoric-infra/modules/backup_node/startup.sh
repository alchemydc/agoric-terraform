#!/bin/bash

export HOME="/root"

# helpful packages
echo "Updating packages" | logger
apt update && apt -y upgrade
echo "Installing needed packages" | logger
apt install -y htop screen wget pigz file 

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
#
# render ANSI color codes properly
$EscapeControlCharactersOnReceive off
EOF

# ---- Restart rsyslogd
echo "Restarting rsyslogd" | logger
systemctl restart rsyslog

# native terraform for install ops-agent isn't working, so workaround
echo "Installing GCP ops-agent" | logger
curl -sSO https://dl.google.com/cloudagents/add-google-cloud-ops-agent-repo.sh
bash add-google-cloud-ops-agent-repo.sh --also-install

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
DATA_DIR=/home/agoric/.agoric
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

# add agoric user
echo "Adding agoric user" | logger
useradd -m agoric -s /bin/bash

# set perms on datadir for agoric user
echo "Adding setting perms on agoric user's home dir" | logger
chown -R agoric:agoric /home/agoric

# set perms on datadir for agoric user
echo "Adding setting perms on $DATA_DIR" | logger
chown -R agoric:agoric $DATA_DIR

# Optionally, remove existing chain data.
# note that ag0 unsafe-reset-all is more cosmonic
[[ ${reset_chain_data} == "true" ]] && echo "Removing existing blockchain data" | logger && rm -rf $DATA_DIR/data

# ---- Useful aliases ----
echo "Configuring aliases" | logger
echo "alias ll='ls -laF'" >> /etc/skel/.bashrc
echo "alias ll='ls -laF'" >> /root/.bashrc
echo "alias ll='ls -laF'" >> /home/agoric/.bashrc
echo "alias peers='curl -s 127.0.0.1:26657/net_info | grep n_peers'" >> /home/agoric/.bashrc
echo "alias agstatus='ag0 status | jq .'" >> /home/agoric/.bashrc

# fix vim
echo "Configuring vim" | logger
cat <<'EOF' >> '/etc/vim/vimrc.local'
set mouse-=a
syntax on
set background=dark
EOF

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

# FIXME:parameterize these as variables and expose properly via terraform
# presently used for local firewall rules, which really should be controlled by variables
#AGORIC_PROMETHEUS_HOSTNAME="prometheus.testnet.agoric.net"
#AGORIC_PROMETHEUS_IP="142.93.181.215"
#AGORIC_PROMETHEUS_IP=`$AGORIC_PROMETHEUS_HOSTNAME | cut -d ' ' -f 4`
# following will expose Agoric VM (SwingSet) metrics globally on tcp/94643
# see https://github.com/Agoric/agoric-sdk/blob/master/packages/cosmic-swingset/README-telemetry.md for more info
#OTEL_EXPORTER_PROMETHEUS_PORT=9464

# agoric SDK dependencies and installing disabled pending mainnet phase 1
# Download the nodesource PPA for Node.js
#echo "Installing nodejs and yarn" | logger
#curl https://deb.nodesource.com/setup_12.x |  bash

# Download the Yarn repository configuration
# See instructions on https://legacy.yarnpkg.com/en/docs/install/
#curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | apt-key add -
#echo "deb https://dl.yarnpkg.com/debian/ stable main" |  tee /etc/apt/sources.list.d/yarn.list

# Update Ubuntu to pickup the yarn repo
#apt update

# Install Node.js, Yarn, and build tools
# Install jq for formatting of JSON data
#apt install nodejs=12.* yarn build-essential jq git nftables -y
# build essential is required for both the Cosmos golang SDK base layer as well as the Agoric SDK
apt install build-essential jq git nftables -y

# Install correct Go version
# First remove any existing old Go installation
rm -rf /usr/local/go
echo "installing golang" | logger
curl https://dl.google.com/go/go1.15.7.linux-amd64.tar.gz |  tar -C/usr/local -zxvf -

# Update environment variables to include go
echo "Creating .profile for agoric user to put go in path" | logger
cat <<'EOF' >> /home/agoric/.profile
export GOROOT=/usr/local/go
export GOPATH=$HOME/go
export GO111MODULE=on
export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin
EOF
chown agoric:agoric /home/agoric/.profile

# Create agoric install script
# note that EOF is *not* quoted here so that the bash env variables will get expanded
# terraform env vars *are* expanded even when using 'cat << 'EOF' .... 

echo "Creating /home/agoric/install_agoric.sh" | logger
cat << EOF >> /home/agoric/install_agoric.sh
#!/bin/bash
set -ex

. /home/agoric/.profile
cd \$DATA_DIR
rm -rf \$DATA_DIR/ag0
git clone ${agoric_node_release_repository} -b ${agoric_node_release_tag} ag0
cd ag0
make build
make install
EOF

chmod u+x /home/agoric/install_agoric.sh
chown agoric:agoric /home/agoric/install_agoric.sh

echo "Running /home/agoric/install_agoric.sh, which checks out ag0 from github and builds it" | logger
sudo -u agoric /home/agoric/install_agoric.sh

echo "agoric ag0 installed" | logger
sudo -u agoric -i ag0 version --long | logger

# Create agoric configurator script
echo "Creating /home/agoric/configure_agoric.sh" | logger
cat << EOF >> /home/agoric/configure_agoric.sh
#!/bin/bash
set -x

DATA_DIR="/home/agoric/.agoric"
. /home/agoric/.profile

cd \$DATA_DIR
# check for existing configured installation
if [ -e "\$DATA_DIR/data/blockstore.db" ]; then
  echo "Existing agoric chaindata found, skipping unsafe-reset-all"
  echo "Setting moniker to ${backup_node_name} in config.toml"
  sed -i.bak "s/^moniker = .*/moniker = \"${backup_node_name}\"/" \$DATA_DIR/config/config.toml
  echo "Updating external_address to 'tcp://${backup_node_external_address}:26656' in config.toml" | logger
  sed -i.bak "s/^external_address = .*/external_address = \"tcp:\/\/${backup_node_external_address}:26656\"/" \$DATA_DIR/config/config.toml
  echo "Skipping download of genesis.json and ag0 unsafe-reset-all"
  exit 0;
fi

# no chaindata found on disk, so perform a fresh init and configure
# First, get the network config for the current network.
curl ${network_uri}/network-config > chain.json
# Set chain name to the correct value
chainName=\$(jq -r .chainName < chain.json)
echo "chainName: \$chainName"
echo "Removing old genesis (if necessary)"
rm -fv \$DATA_DIR/config/genesis.json 
echo "Initializing chain"
ag0 init --chain-id \$chainName ${backup_node_name}
# Download the genesis file
echo "Downloading genesis"
curl ${network_uri}/genesis.json > \$DATA_DIR/config/genesis.json 
# Reset the state of your validator.
echo "Deleting chaindata and resetting everything: ag0 unsafe-reset-all"
ag0 unsafe-reset-all
# Set peers variable to the correct value
echo "Setting initial peers and seeds in config.toml from downloaded network-config"
peers=\$(jq '.peers | join(",")' < chain.json)
# Set seeds variable to the correct value.
seeds=\$(jq '.seeds | join(",")' < chain.json)
# Replace the seeds and persistent_peers values
sed -i.bak -e "s/^seeds *=.*/seeds = \$seeds/; s/^persistent_peers *=.*/persistent_peers = \$peers/" \$DATA_DIR/config/config.toml
# set publicly routable p2p addr in config.toml
echo "Setting publicly reachable p2p addr in config.toml"
echo "Updating external_address to \"tcp://${backup_node_external_address}:26656\" in config.toml" | logger
sed -i.bak "s/^external_address = .*/external_address = \"tcp:\/\/${backup_node_external_address}:26656\"/" \$DATA_DIR/config/config.toml
echo "Setting fastsync to v2 in config.toml" | logger
sed -i.bak 's/^version = "v[0-1]"/version = "v2"/' \$DATA_DIR/config/config.toml
EOF

chmod u+x /home/agoric/configure_agoric.sh
chown agoric:agoric /home/agoric/configure_agoric.sh

echo "Configuring agoric" | logger
sudo -u agoric /home/agoric/configure_agoric.sh

# agoric SDK not yet enabled, so skipping
#echo "Install and build Agoric Javascript packages" | logger
#yarn install
#yarn build

#echo "Install and build Agoric Cosmos SDK support" | logger
#cd packages/cosmic-swingset && make

# test to see agoric SDK is correctly installed
#echo "testing to see agoric SDK is correctly installed" | logger
#ag-chain-cosmos version --long
#agd version --long

#backup state file
#cp $DATA_DIR/data/priv_validator_state.json /root/
#restore chain data from tarball
#/root/restore.sh
# restore state file
#cp -vf /root/priv_validator_state.json $DATA_DIR/data/priv_validator_state.json


echo "Setting up ag0 service in systemd" | logger
tee <<EOF >/dev/null /etc/systemd/system/ag0.service
[Unit]
Description=Agoric Cosmos daemon
After=network-online.target

[Service]
User=agoric
#Environment="OTEL_EXPORTER_PROMETHEUS_PORT=9464"
#Environment="SLOGFILE=$DATA_DIR/${validator_name}-${agoric_node_release_tag}-chain.slog"
ExecStart=/home/agoric/go/bin/ag0 start --log_level=info
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

                # permit SSH and cosmos p2p traffic from anywhere
                tcp dport { 22, 26656 } ct state new accept

                # permit prometheus access to telemetry ports but ONLY from agoric
                #ip saddr $AGORIC_PROMETHEUS_IP tcp dport { 9464, 9100, 26660} ct state new accept

                # accept neighbour discovery otherwise IPv6 connectivity breaks.
                #ip6 nexthdr icmpv6 icmpv6 type { nd-neighbor-solicit,  nd-router-advert, nd-neighbor-advert } accept

                # count and drop any other traffic
                counter drop
        }
}
EOF

echo "Enabling firewall" | logger
systemctl enable nftables.service
systemctl start nftables.service

#echo "configuring telemetry services" | logger
#echo "telemetry: swingset enabled at on tcp/9464 and tendermint enabled on tcp/26660"
#sed -i "s/prometheus = false/prometheus = true/" $DATA_DIR/config/config.toml

# start via systemd
echo "Setting ag0 to run from systemd" | logger
echo "systemctl status ag0" | logger
 systemctl enable ag0
 systemctl daemon-reload
 systemctl start ag0

echo "install completed, chain syncing" | logger
echo "for sync status: ag0 status | jq .SyncInfo"
echo "or check stackdriver logs for this instance"

# ---- Update sudoers to allow agoric user to control the ag0 service
echo "Updating sudoers to allow agoric user to control the ag0 service" | logger
cat << 'EOF' >> /etc/sudoers
agoric ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart ag0.service,/usr/bin/systemctl stop ag0.service,/usr/bin/systemctl start ag0.service,/usr/bin/systemctl status ag0.service
EOF

# ---- Create chaindata tarball backup script
echo "Creating chaindata tarball backup script" | logger
cat <<'EOF' > /home/agoric/backup_chaindata_tarball.sh
#!/bin/bash
# This script stops the agoric cosmos ag0 p2p/consensus daemon, tars up the chaindata (with gzip compression), and copies it to GCS.
# The 'chaindata' GCS bucket has versioning enabled, so if a corrupted tarball is uploaded, an older version can be selected for restore.
# This takes quit some time, and takes quite a bit of local disk.
# The rsync variant (below) is more efficient, but tarballs are more portable.
set -x

WORKING_DIR='/home/agoric/.agoric'
SYSTEMCTL='/usr/bin/systemctl'

echo "Starting chaindata backup" | logger
sudo $SYSTEMCTL stop ag0.service
sleep 5

mkdir -p $WORKING_DIR/backup

echo "Tarring up chaindata to $WORKING_DIR/backup/chaindata.tgz" | logger
# backup only the data for now, not the config
#tar -I "pigz --fast" -C $WORKING_DIR -cvf $WORKING_DIR/backup/chaindata.tgz data config
tar -I "pigz --fast" -C $WORKING_DIR -cvf $WORKING_DIR/backup/chaindata.tgz data

echo "Copying tarball to GCS bucket gs://${gcloud_project}-chaindata" | logger
gsutil -m cp $WORKING_DIR/backup/chaindata.tgz gs://${gcloud_project}-chaindata

echo "Removing tarball from local fs" | logger
rm -f $WORKING_DIR/backup/chaindata.tgz
echo "Chaindata backup completed" | logger
sleep 3
sudo $SYSTEMCTL start ag0.service
EOF
chown agoric:agoric /home/agoric/backup_chaindata_tarball.sh
chmod u+x /home/agoric/backup_chaindata_tarball.sh

# ---- Create chaindata rsync backup script
echo "Creating chaindata rsync backup script" | logger
cat <<'EOF' > /home/agoric/backup_chaindata_rsync.sh
#!/bin/bash
# This script stops agoric p2p/consensus daemon, and uses rsync to copy chaindata to GCS.
set -x

WORKING_DIR='/home/agoric/.agoric'
SYSTEMCTL='/usr/bin/systemctl'

echo "Starting rsync chaindata backup" | logger
sudo $SYSTEMCTL stop ag0.service
sleep 5
echo "Backing up chaindata via rsync" | logger
gsutil -m rsync -d -r $WORKING_DIR/data  gs://${gcloud_project}-chaindata-rsync/data
echo "rsync chaindata backup completed" | logger
sleep 3
sudo $SYSTEMCTL start ag0.service
EOF
chown agoric:agoric /home/agoric/backup_chaindata_rsync.sh
chmod u+x /home/agoric/backup_chaindata_rsync.sh

# ----- Create snapshot backup script
cat << EOF > /home/agoric/backup_snapshot.sh
#!/bin/bash
# This script stops ag0, deletes snapshots from GCS, and then snapshots the
# persistent disk containing the chaindata (and configuration!)
set -x

SYSTEMCTL='/usr/bin/systemctl'

echo "Deleting snapshots" | logger
echo 'y' | gcloud compute snapshots delete ${data_disk_name}-snapshot-latest 
echo "Stopping Agoric Cosmos consensus daemon"

sudo \$SYSTEMCTL stop ag0.service
sleep 5
echo "Taking snapshot of persistent chaindata disk" | logger
gcloud compute disks snapshot ${data_disk_name} --snapshot-names=${data_disk_name}-snapshot-latest --zone=${gcloud_zone}
sleep 3
echo "Starting Agoric Cosmos consensus daemon" | logger
sudo \$SYSTEMCTL start ag0.service
EOF
chown agoric:agoric /home/agoric/backup_snapshot.sh
chmod u+x /home/agoric/backup_snapshot.sh

# ---- Add backups to cron
# note that this will make the backup_node ag0 unavailable during the backup, which is why
# we run this on a dedicated backup node now 
cat <<'EOF' > /home/agoric/backup.crontab
# backup snapshot once a day at 00:57
57 0 * * * /home/agoric/backup_snapshot.sh 2>&1 | /usr/bin/logger
# m h  dom mon dow   command
# full tarball is unwieldy, so is now run only manually as required
# backup full tarball once a week at 04:20
#20 4 * * SUN /home/agoric/backup_chaindata_tarball.sh > /dev/null 2>&1
# backup via rsync run once a week at 00:07 past the hour
07 0 * * SAT /home/agoric/backup_chaindata_rsync.sh > /dev/null 2>&1
EOF

# do NOT enable crontab on the validator itself.  we'll want to run this from the backup node
# disabled temporarily for testing
#sudo -u agoric /usr/bin/crontab /home/agoric/backup.crontab

# ---- Create restore chaindata from tarball script
echo "Creating chaindata tarball restore script" | logger
cat <<'EOF' > /home/agoric/restore_chaindata_tarball.sh
#!/bin/bash
set -ex

WORKING_DIR='/home/agoric/.agoric'
SYSTEMCTL='/usr/bin/systemctl'

echo "Starting chaindata restore from GCS tarball" | logger

## test to see if chaindata exists in bucket
echo "Checking for presence of chaindata tarball in GCS" | logger
gsutil -q stat gs://${gcloud_project}-chaindata/chaindata.tgz
if [ $? -eq 0 ]
then
  #chaindata exists in bucket
  echo "Found chaindata tarball in GCS" | logger
  mkdir -p $WORKING_DIR/restore
  mkdir -p $WORKING_DIR/data  
  echo "downloading chaindata from gs://${gcloud_project}-chaindata/chaindata.tgz" | logger
  gsutil -m cp gs://${gcloud_project}-chaindata/chaindata.tgz $WORKING_DIR/restore/chaindata.tgz
  echo "stopping agoric p2p/consensus daemon to untar chaindata" | logger
  sudo $SYSTEMCTL stop ag0.service
  sleep 5
  echo "untarring chaindata" | logger
  tar zxvf $WORKING_DIR/restore/chaindata.tgz --directory $WORKING_DIR
  echo "removing chaindata tarball" | logger
  rm -rf $WORKING_DIR/restore/chaindata.tgz
  sleep 5
  echo "Starting agoric p2p/consensus daemon" | logger
  sudo $SYSTEMCTL start ag0.service
  else
    echo "No chaindata.tgz found in bucket gs://${gcloud_project}-chaindata, aborting restore" | logger
  fi
EOF
chown agoric:agoric /home/agoric/restore_chaindata_tarball.sh
chmod u+x /home/agoric/restore_chaindata_tarball.sh

# ---- Create rsync chaindata restore script
echo "Creating rsync chaindata restore script" | logger
cat <<'EOF' > /home/agoric/restore_chaindata_rsync.sh
#!/bin/bash
set -x

WORKING_DIR='/home/agoric/.agoric'
SYSTEMCTL='/usr/bin/systemctl'

# test to see if chaindata exists in the rsync chaindata bucket
gsutil -q stat gs://${gcloud_project}-chaindata-rsync/data/priv_validator_state.json
if [ $? -eq 0 ]
then
  #chaindata exists in bucket
  echo "stopping agoric p2p/consensus daemon to rsync chaindata" | logger
  sudo $SYSTEMCTL stop ag0.service
  echo "downloading blockchain data via rsync from gs://${gcloud_project}-chaindata-rsync/data" | logger
  mkdir -p $WORKING_DIR/data
  gsutil -m rsync -d -r gs://${gcloud_project}-chaindata-rsync/data $WORKING_DIR/data
  echo "restarting ag0.service" | logger
  sleep 5
  echo "Starting agoric p2p/consensus daemon" | logger
  sudo $SYSTEMCTL start ag0.service
  else
    echo "No chaindata found in bucket gs://${gcloud_project}-chaindata-rsync, aborting warp restore" | logger
  fi
EOF
chmod u+x /home/agoric/restore_chaindata_rsync.sh
chown agoric:agoric /home/agoric/restore_chaindata_rsync.sh


