#!/bin/bash
source /etc/profile

emerge-webrsync
emerge --sync
eselect news read
eselect profile set default/linux/amd64/17.1/systemd

echo "Asia/Shanghai" > /etc/timezone
emerge --config sys-libs/timezone-data

cat << EOF > /etc/locale.gen
en_US.UTF-8 UTF-8
zh_CN.UTF-8 UTF-8
EOF
locale-gen

cat << EOF > /etc/env.d/02locale
LANG="en_US.UTF-8"
EOF

env-update

#emerge sys-kernel/gentoo-kernel-bin grub zstd
emerge gentoo-sources grub zstd linux-firmware

pushd /usr/src/linux
cp /config.nv .config
make -j16
make modules_install
make install

grub-install
grub-mkconfig -o /boot/grub/grub.cfg

cp /make.conf /etc/portage/make.conf

echo "Set root password"
passwd

exit
