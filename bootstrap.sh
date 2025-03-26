#!/bin/ash

set -eu

# Install base
apk update
apk add openrc
rc-update add devfs boot
rc-update add procfs boot
rc-update add sysfs boot
rc-update add networking default
rc-update add local default

# Install TTY
apk add agetty

# Setting up shell
apk add shadow bash bash-completion
chsh -s /bin/bash
echo -e "luckfox\nluckfox" | passwd
apk del -r shadow

# Install SSH
apk add openssh
rc-update add sshd default

# Extra stuff
apk add mtd-utils-ubi bottom nano ca-certificates curl

# DHCP server
apk add mtd-utils-ubi dnsmasq
rc-update add dnsmasq default

# Timezone
#rc-update add ntpd

apk add tzdata
cp /usr/share/zoneinfo/Europe/Berlin /etc/localtime
apk del tzdata

# Syslog
apk add busybox-openrc
rc-update add syslog boot

# Clear apk cache
rm -rf /var/cache/apk/*

# Packaging rootfs
for d in bin etc lib sbin usr; do tar c "$d" | tar x -C /extrootfs; done
for dir in dev proc root run sys var oem userdata; do mkdir /extrootfs/${dir}; done
