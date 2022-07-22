#!/bin/bash

export HOME="/root"

# helpful packages
echo "Updating packages" | logger
apt update && apt -y upgrade
echo "Installing needful packages" | logger
apt install -y htop screen wget file

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
/var/log/google-cloud-ops-agent/subagents/logging-module.log
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
mkdir -vp $DATA_DIR
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

# drop ssh public key in ~/agoric/.ssh/authorized_keys and set perms
mkdir -vp /home/agoric/.ssh
echo "${ssh_public_key}" > /home/agoric/.ssh/authorized_keys
chmod 600 /home/agoric/.ssh/authorized_keys
chown agoric:agoric /home/agoric/.ssh/authorized_keys

# ---- Update sudoers to allow agoric user full sudo without password
echo "Updating sudoers to allow agoric user full sudo without password" | logger
cat << 'EOF' >> /etc/sudoers
agoric ALL=(ALL) NOPASSWD: ALL
EOF

# Optionally, remove existing chain data.
# note that ag0 unsafe-reset-all is more cosmonic
[[ ${reset_chain_data} == "true" ]] && rm -rf $DATA_DIR/data

# ---- Useful aliases ----
echo "Configuring aliases" | logger
echo "alias ll='ls -laF'" >> /etc/skel/.bashrc
echo "alias ll='ls -laF'" >> /root/.bashrc
echo "alias ll='ls -laF'" >> /home/agoric/.bashrc
echo "alias peers='curl -s 127.0.0.1:26657/net_info | grep n_peers'" >> /home/agoric/.bashrc
echo "alias status='ag0 status | jq .'" >> /home/agoric/.bashrc
echo "alias ll='ls -laF'" >> /home/agoric/.bashrc

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

