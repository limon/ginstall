#!/bin/bash
MOUNT_POINT=/mnt/gentoo
EFI_PART=/dev/sda1
SWAP_PART=/dev/sda2
BTRFS_PART=/dev/sda3
BTRFS_ROOT_SUBVOL=gentoo
SUBVOLS="home opt srv var"
STAGE3_TARBALL="https://mirrors.bfsu.edu.cn/gentoo/releases/amd64/autobuilds/current-stage3-amd64-systemd/stage3-amd64-systemd-20200906T214503Z.tar.xz"

function yes_or_terminate {
	printf "$1?(y\N): "
	read yn
	case $yn in
		[Yy]* ) ;;
		* ) exit;;
	esac
}

function terminate {
	echo $1
	exit
}

function list_params {
	echo "EFI_PART=$EFI_PART"
	echo "SWAP_PART=$SWAP_PART"
	echo "BTRFS_PART=$BTRFS_PART"
	echo "BTRFS_ROOT_SUBVOL=$BTRFS_ROOT_SUBVOL"
	echo "Separate subvolumes: $SUBVOLS"
}

function check_partition_type {
	if ! blkid $EFI_PART | grep -q TYPE=\"vfat\"; then
		terminate "EFI partition wrong"
	fi

	if ! blkid $SWAP_PART | grep -q TYPE=\"swap\"; then
		terminate "Swap partition wrong"
	fi

	if ! blkid $BTRFS_PART | grep -q TYPE=\"btrfs\"; then
		terminate "Btrfs root partition wrong"
	fi
}

function gen_fstab {
	EFI_UUID=$(blkid $EFI_PART | grep -Po ' UUID="\K[0-9A-Za-z-]+')
	echo "UUID=$EFI_UUID     	/boot/efi 	vfat      	rw,noatime,fmask=0022,dmask=0022,codepage=437,iocharset=iso8859-1,shortname=mixed,utf8,errors=remount-ro	0 2" > /tmp/fstab

	BTRFS_UUID=$(blkid $BTRFS_PART | grep -Po ' UUID="\K[0-9A-Za-z-]+')
	echo "UUID=$BTRFS_UUID /         	btrfs     	rw,noatime,ssd,space_cache,compress=zstd,subvol=gentoo/@	0 0" >> /tmp/fstab

	for dir in ${SUBVOLS[@]}
	do
		echo "UUID=$BTRFS_UUID /$dir         	btrfs     	rw,noatime,ssd,space_cache,compress=zstd,subvol=gentoo/$dir	0 0" >> /tmp/fstab
	done

	SWAP_UUID=$(blkid $SWAP_PART | grep -Po ' UUID="\K[0-9A-Za-z-]+')
	echo "UUID=$SWAP_UUID                       none  swap   defaults  0 0" >> /tmp/fstab
}

list_params
check_partition_type
gen_fstab
cat /tmp/fstab
yes_or_terminate "continue"
echo "Installing..."
echo 

if mount | grep -q $MOUNT_POINT
then
	yes_or_terminate "/mnt/gentoo already mounted, umount to continue"
	umount $MOUNT_POINT/boot/efi
	umount -l $MOUNT_POINT/dev
	umount -l $MOUNT_POINT/sys
	umount -l $MOUNT_POINT/proc
	for dir in ${SUBVOLS[@]}
	do
		umount $MOUNT_POINT/$dir
	done
	umount $MOUNT_POINT
fi

mkdir $MOUNT_POINT 2> /dev/null
mount $BTRFS_PART $MOUNT_POINT
rmdir $MOUNT_POINT/$BTRFS_ROOT_SUBVOL 2> /dev/null

if [ -d $MOUNT_POINT/$BTRFS_ROOT_SUBVOL ]; then
	yes_or_terminate "Old Gentoo system exists, remove it"
	yes_or_terminate "ARE YOU SURE?"
	rm -rf $MOUNT_POINT/$BTRFS_ROOT_SUBVOL
fi
btrfs subvolume create $MOUNT_POINT/$BTRFS_ROOT_SUBVOL
btrfs subvolume create $MOUNT_POINT/$BTRFS_ROOT_SUBVOL/@
for dir in ${SUBVOLS[@]}
do
	btrfs subvolume create $MOUNT_POINT/$BTRFS_ROOT_SUBVOL/$dir
done

umount $MOUNT_POINT
mount $BTRFS_PART $MOUNT_POINT -o subvol=$BTRFS_ROOT_SUBVOL/@

for dir in ${SUBVOLS[@]}
do
	mkdir $MOUNT_POINT/$dir
	mount $BTRFS_PART $MOUNT_POINT/$dir -o subvol=$BTRFS_ROOT_SUBVOL/$dir
done
chattr +C $MOUNT_POINT/var
mkdir -p $MOUNT_POINT/boot/efi
mount $EFI_PART $MOUNT_POINT/boot/efi
#swapon $SWAP_PART 2> /dev/null

pushd $MOUNT_POINT
wget $STAGE3_TARBALL
tar xpvf stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner
popd

#cp make.conf $MOUNT_POINT /etc/portage/make.conf
cat <<EOF >> $MOUNT_POINT/etc/portage/make.conf
GENTOO_MIRRORS="https://mirrors.bfsu.edu.cn/gentoo"
ACCEPT_KEYWORDS="~amd64"
EOF

mkdir -p $MOUNT_POINT/etc/portage/repos.conf
cp $MOUNT_POINT/usr/share/portage/config/repos.conf $MOUNT_POINT/etc/portage/repos.conf/gentoo.conf
sed -i -e 's/sync-rsync-verify-metamanifest = yes/sync-rsync-verify-metamanifest = no/' -e 's/sync-uri.*/sync-uri = rsync:\/\/mirrors.bfsu.edu.cn\/gentoo-portage\//' $MOUNT_POINT/etc/portage/repos.conf/gentoo.conf

cp --dereference /etc/resolv.conf $MOUNT_POINT/etc/
mount --types proc /proc /mnt/gentoo/proc
mount --rbind /sys /mnt/gentoo/sys
mount --make-rslave /mnt/gentoo/sys
mount --rbind /dev /mnt/gentoo/dev
mount --make-rslave /mnt/gentoo/dev

cp ${BASH_SOURCE%/*}/setup.sh $MOUNT_POINT
chmod +x $MOUNT_POINT/setup.sh
cp /tmp/fstab $MOUNT_POINT/etc/fstab
cp ${BASH_SOURCE%/*}/config.sh $MOUNT_POINT/root

chroot /mnt/gentoo /bin/bash /setup.sh
