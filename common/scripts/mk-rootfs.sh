#!/bin/bash -e

set -x

build_buildroot()
{
	check_config RK_BUILDROOT || false

	IMAGE_DIR="${1:-$RK_OUTDIR/buildroot}"

	BUILDROOT_VERSION=$(grep "export BR2_VERSION := " \
		"$RK_SDK_DIR/buildroot/Makefile" | xargs -n 1 | tail -n 1)

	message "=========================================="
	message "          Start building buildroot($BUILDROOT_VERSION)"
	message "=========================================="

	"$RK_SCRIPTS_DIR/mk-buildroot.sh" $RK_BUILDROOT_CFG "$IMAGE_DIR"

	[ -z "$RK_SECURITY" ] || "$RK_SCRIPTS_DIR/mk-security.sh" system \
		$RK_SECURITY_CHECK_METHOD $IMAGE_DIR/rootfs.$RK_ROOTFS_TYPE

	cat "$RK_LOG_DIR/post-rootfs.log"
	finish_build build_buildroot $@
}

build_yocto()
{
	check_config RK_YOCTO || false

	IMAGE_DIR="${1:-$RK_OUTDIR/yocto}"

	"$RK_SCRIPTS_DIR/check-yocto.sh"

	cd yocto
	rm -f build/conf/local.conf

	if [ "$RK_YOCTO_CFG_CUSTOM" ]; then
		if [ ! -r "build/conf/$RK_YOCTO_CFG" ]; then
			error "yocto/build/conf/$RK_YOCTO_CFG not exist!"
			return 1
		fi

		if [ "$RK_YOCTO_CFG" != local.conf ]; then
			ln -sf "$RK_YOCTO_CFG" build/conf/local.conf
		fi

		message "=========================================="
		message "          Start building for $RK_YOCTO_CFG"
		message "=========================================="
	else
		{
			echo "include include/common.conf"
			echo "include include/debug.conf"
			echo "include include/display.conf"
			echo "include include/multimedia.conf"
			echo "include include/audio.conf"

			if [ "$RK_WIFIBT_CHIP" ]; then
				echo "include include/wifibt.conf"
			fi

			if [ "$RK_YOCTO_CHROMIUM" ]; then
				echo "include include/browser.conf"
			fi

			echo
			echo "DISPLAY_PLATFORM := \"$RK_YOCTO_DISPLAY_PLATFORM\""

			echo
			echo "MACHINE = \"$RK_YOCTO_MACHINE\""
		} > build/conf/local.conf

		message "=========================================="
		message "          Start building for machine($RK_YOCTO_MACHINE)"
		message "=========================================="
	fi

	{
		echo "include include/rksdk.conf"
		echo

		if [ "$RK_CHIP" = "rk3288w" ]; then
			echo "MACHINE_FEATURES:append = \" rk3288w\""
		fi

		echo "PREFERRED_VERSION_linux-rockchip :=" \
			"\"$RK_KERNEL_VERSION_REAL%\""
		echo "LINUXLIBCVERSION := \"$RK_KERNEL_VERSION_REAL-custom%\""
		case "$RK_CHIP_FAMILY" in
			px30|rk3326|rk3562|rk3566_rk3568|rk3588)
				echo "MALI_VERSION := \"g13p0\"" ;;
		esac
	} > build/conf/rksdk_override.conf

	source oe-init-build-env build
	LANG=en_US.UTF-8 LANGUAGE=en_US.en LC_ALL=en_US.UTF-8 \
		bitbake core-image-minimal -C rootfs \
		-R conf/rksdk_override.conf

	ln -rsf "$PWD/latest/rootfs.img" "$IMAGE_DIR/rootfs.ext4"

	touch "$RK_LOG_DIR/post-rootfs.log"
	cat "$RK_LOG_DIR/post-rootfs.log"
	finish_build build_yocto $@
}

build_debian()
{
	check_config RK_DEBIAN || false

	IMAGE_DIR="${1:-$RK_OUTDIR/debian}"
	ARCH=${RK_DEBIAN_ARCH:-armhf}

	"$RK_SCRIPTS_DIR/check-debian.sh"

	message "=========================================="
	message "          Start building $RK_DEBIAN_VERSION($ARCH)"
	message "=========================================="

	cd debian
	if [ ! -f linaro-$RK_DEBIAN_VERSION-alip-*.tar.gz ]; then
		RELEASE=$RK_DEBIAN_VERSION TARGET=desktop ARCH=$ARCH \
			./mk-base-debian.sh
		ln -sf linaro-$RK_DEBIAN_VERSION-alip-*.tar.gz \
			linaro-$RK_DEBIAN_VERSION-$ARCH.tar.gz
	fi

	VERSION=debug ARCH=$ARCH ./mk-rootfs-$RK_DEBIAN_VERSION.sh
	./mk-image.sh

	ln -rsf "$PWD/linaro-rootfs.img" "$IMAGE_DIR/rootfs.ext4"

	finish_build build_debian $@
}

ubuntu_install_package()
{
	message "=========================================="
	message "          Install package for Ubuntu"
	message "=========================================="

	sudo cp -rpvf ubuntu/base/packages/* ubuntu/base/temp/root/
	sudo mv *.deb  ubuntu/base/temp/root/

	sudo chroot ubuntu/base/temp /bin/bash -c "dpkg -i /root/linux-gpu-mali-wayland_1.2-g13p0-230620_arm64.deb"
	sudo chroot ubuntu/base/temp /bin/bash -c "dpkg -i /root/rockchip-mpp_1.5.0-9_arm64.deb"
	sudo chroot ubuntu/base/temp /bin/bash -c "dpkg -i /root/rockchip-mpp-sample_1.5.0-9_arm64.deb"
	sudo chroot ubuntu/base/temp /bin/bash -c "dpkg -i /root/rockchip-mpp-dev_1.5.0-9_arm64.deb"
	sudo chroot ubuntu/base/temp /bin/bash -c "dpkg -i /root/rockchip-rga_2.2.0-6_arm64.deb"
	sudo chroot ubuntu/base/temp /bin/bash -c "dpkg -i /root/rockchip-rga-sample_2.2.0-6_arm64.deb"
	sudo chroot ubuntu/base/temp /bin/bash -c "dpkg -i /root/rockchip-rga-dev_2.2.0-6_arm64.deb"
	sudo chroot ubuntu/base/temp /bin/bash -c "dpkg -i /root/gstreamer1.0-rockchip1_1.14-6_arm64.deb"
	sudo chroot ubuntu/base/temp /bin/bash -c "dpkg -i /root/camera-engine-rkaiq_0.3-5.0x4.1_arm64.deb"
	sudo chroot ubuntu/base/temp /bin/bash -c "dpkg -i /root/xwayland_22.1.1-1_arm64.deb"
	sudo chroot ubuntu/base/temp /bin/bash -c "dpkg -i /root/mutter-common_42.0-3ubuntu3_all.deb"
	sudo chroot ubuntu/base/temp /bin/bash -c "dpkg -i /root/mutter_42.0-3ubuntu3_arm64.deb"
	sudo chroot ubuntu/base/temp /bin/bash -c "dpkg -i /root/libmutter-10-0_42.0-3ubuntu3_arm64.deb"
	sudo chroot ubuntu/base/temp /bin/bash -c "dpkg -i /root/gir1.2-mutter-10_42.0-3ubuntu3_arm64.deb"
	sudo chroot ubuntu/base/temp /bin/bash -c "dpkg -i /root/gir1.2-mutter-10_42.0-3ubuntu3_arm64.deb"
	sudo chroot ubuntu/base/temp /bin/bash -c "dpkg -i /root/linux-image-rockchip-5.10_1.0_arm64.deb"
	sudo chroot ubuntu/base/temp /bin/bash -c "dpkg -i /root/linux-dtb-rockchip-5.10_1.0_arm64.deb"
	sudo chroot ubuntu/base/temp /bin/bash -c "dpkg -i /root/linux-headers-rockchip-5.10_1.0_arm64.deb"
	sudo chroot ubuntu/base/temp /bin/bash -c "rm -rf /root/*.deb"
}

ubuntu_config_services()
{
	message "=========================================="
	message "          Config services for Ubuntu"
	message "=========================================="

	local UBUNTU_PATH="ubuntu/base"
	local UBUNTU_ROOTFS_PATH="ubuntu/base/temp"

	# copy exec
	sudo cp -rpvf $UBUNTU_PATH/bin/resize2fs $UBUNTU_ROOTFS_PATH/etc/init.d/
	sudo cp -rpvf $UBUNTU_PATH/bin/bluetooth-namtso.sh $UBUNTU_ROOTFS_PATH/usr/local/bin/
	sudo cp -rpvf $UBUNTU_PATH/bin/fan_setup.sh $UBUNTU_ROOTFS_PATH/usr/local/bin/
	sudo cp -rpvf $UBUNTU_PATH/bin/fan.sh $UBUNTU_ROOTFS_PATH/usr/local/bin/
	sudo cp -rpvf $UBUNTU_PATH/bin/namtso_bluetooth_suspend.sh $UBUNTU_ROOTFS_PATH/usr/local/bin/
	sudo cp -rpvf $UBUNTU_PATH/bin/fix-dp-sound.sh $UBUNTU_ROOTFS_PATH/usr/local/bin/
	sudo cp -rpvf $UBUNTU_PATH/bin/fix-gdm-wayland.sh $UBUNTU_ROOTFS_PATH/usr/local/bin/
	sudo cp -rpvf $UBUNTU_PATH/bin/fix-gdm-wayland-hotplug.sh $UBUNTU_ROOTFS_PATH/usr/local/bin/
	

	#copy services
	sudo cp -rpvf $UBUNTU_PATH/services/* $UBUNTU_ROOTFS_PATH/lib/systemd/system/

	#enable services
	sudo chroot $UBUNTU_ROOTFS_PATH /bin/bash -c "systemctl --no-reload enable resize2fs.service"
	sudo chroot $UBUNTU_ROOTFS_PATH /bin/bash -c "systemctl --no-reload enable rockchip-isp.service"
	sudo chroot $UBUNTU_ROOTFS_PATH /bin/bash -c "systemctl --no-reload enable bluetooth-namtso.service"
	sudo chroot $UBUNTU_ROOTFS_PATH /bin/bash -c "systemctl --no-reload enable bluetooth-suspend.service"
	sudo chroot $UBUNTU_ROOTFS_PATH /bin/bash -c "systemctl --no-reload enable fan.service"
	# sudo chroot $UBUNTU_ROOTFS_PATH /bin/bash -c "systemctl --no-reload enable gdm3.service"
	sudo chroot $UBUNTU_ROOTFS_PATH /bin/bash -c "systemctl --no-reload enable fix-gdm-wayland.service"
	
	#disable services
	sudo chroot $UBUNTU_ROOTFS_PATH /bin/bash -c "systemctl --no-reload mask ondemand.service"
}

ubuntu_config_network()
{

	local NAMESERVER="1.0.0.1"
	local TZDATA=

	if [ -f /etc/timezone ]; then
    	TZDATA=`cat /etc/timezone`
	elif [ -L /etc/localtime ]; then
		TZDATA=$(readlink /etc/localtime | sed -ne 's|^.*/zoneinfo/||p')
	fi

	if [ -z "${TZDATA}" ]; then
		# Default to 'Etc/UTC'.
		TZDATA=Etc/UTC
	fi

	sudo rm -f ubuntu/base/temp/etc/network/interfaces
	message "Setup timezone to '$TZDATA'"
	echo $TZDATA | sudo tee ubuntu/base/temp/etc/timezone
	sudo ln -sf ../usr/share/zoneinfo/$TZDATA  ubuntu/base/temp/etc/localtime
	sudo chroot ubuntu/base/temp /bin/bash -c "dpkg-reconfigure -f noninteractive tzdata"

	date -u '+%Y-%m-%d %H:%M:%S' | sudo tee ubuntu/base/temp/etc/fake-hwclock.data

	# configure network manager
	sudo sed "s/managed=\(.*\)/managed=true/g" -i ubuntu/base/temp/etc/NetworkManager/NetworkManager.conf
	sudo sed "/dns/d" -i ubuntu/base/temp/etc/NetworkManager/NetworkManager.conf
	sudo sed "/rc-manager/d" -i ubuntu/base/temp/etc/NetworkManager/NetworkManager.conf
	sudo sed "s/\[main\]/\[main\]\ndns=default\nrc-manager=file/g" -i ubuntu/base/temp/etc/NetworkManager/NetworkManager.conf
	if [[ -n $NM_IGNORE_DEVICES ]]; then
		sudo mkdir -p ubuntu/base/temp/etc/NetworkManager/conf.d/
		cat <<-EOF > ubuntu/base/temp/etc/NetworkManager/conf.d/10-ignore-interfaces.conf
		[keyfile]
		unmanaged-devices=$NM_IGNORE_DEVICES
		EOF
	fi

	# nsswitch settings for sane DNS behavior: remove resolve, assure libnss-myhostname support
	sudo sed "s/hosts\:.*/hosts:          files mymachines dns myhostname/g" -i ubuntu/base/temp/etc/nsswitch.conf

	if [ -d ubuntu/base/temp/etc/resolvconf/resolv.conf.d ]; then
		echo "nameserver $NAMESERVER" | sudo tee ubuntu/base/temp/etc/resolvconf/resolv.conf.d/head
	fi

	sudo sed -i "s/#DNS=.*/DNS=$NAMESERVER/g" ubuntu/base/temp/etc/systemd/resolved.conf

	sudo cp -rpvf ubuntu/base/config/10-globally-managed-devices.conf ubuntu/base/temp/etc/NetworkManager/conf.d
}

ubuntu_config_misc()
{
	local UBUNTU_PATH="ubuntu/base"
	local UBUNTU_ROOTFS_PATH="ubuntu/base/temp"

	# mount
	sudo chroot $UBUNTU_ROOTFS_PATH /bin/bash -c "mkdir -p /userdata"
	sudo chroot $UBUNTU_ROOTFS_PATH /bin/bash -c "mkdir -p /oem"
	sudo cp -rpvf $UBUNTU_PATH/config/fstab $UBUNTU_ROOTFS_PATH/etc/

	# dtbo
	sudo mkdir -p $UBUNTU_ROOTFS_PATH/boot/overlays/rk3588-namtso-a10-3588.dtb.overlays
	sudo touch $UBUNTU_ROOTFS_PATH/boot/overlays/rk3588-namtso-a10-3588.dtb.overlay.env
	echo "fdt_overlays=" | sudo tee $UBUNTU_ROOTFS_PATH/boot/overlays/rk3588-namtso-a10-3588.dtb.overlay.env
	sudo cp -rf kernel/arch/arm64/boot/dts/rockchip/overlays/*.dtbo  $UBUNTU_ROOTFS_PATH/boot/overlays/rk3588-namtso-a10-3588.dtb.overlays

	#uEnv
	sudo cp -rpvf $UBUNTU_PATH/config/uEnv.txt $UBUNTU_ROOTFS_PATH/boot/

	# wifi & bt
	sudo cp -rpvf $UBUNTU_PATH/firmware/wlan/* $UBUNTU_ROOTFS_PATH/lib/firmware/
	sudo cp -rpvf $UBUNTU_PATH/bin/brcm_patchram_plus-arm64 $UBUNTU_ROOTFS_PATH/usr/local/bin/
	sudo cp -rpvf $UBUNTU_PATH/bin/brcm_patchram_plus-armhf $UBUNTU_ROOTFS_PATH/usr/local/bin/
	sudo cp -rpvf $UBUNTU_PATH/bin/hciattach-arm64 $UBUNTU_ROOTFS_PATH/usr/local/bin/hciattach
	sudo cp -rpvf $UBUNTU_PATH/bin/hciattach-armhf $UBUNTU_ROOTFS_PATH/usr/local/bin/

	# udev
	sudo cp -rpvf $UBUNTU_PATH/config/udev/rules.d/* $UBUNTU_ROOTFS_PATH/etc/udev/rules.d/

	# audio
	sudo cp -rpvf $UBUNTU_PATH/config/audio/asound.state $UBUNTU_ROOTFS_PATH/var/lib/alsa/
	sudo cp -rpvf $UBUNTU_PATH/config/audio/default.pa.jammy.a10-3588.5.10 $UBUNTU_ROOTFS_PATH/etc/pulse/

	#gdm
	sudo sed -i 's/#WaylandEnable=.*/WaylandEnable=true/g' $UBUNTU_ROOTFS_PATH/etc/gdm3/custom.conf
	echo "$UBUNTU_ROOTFS_PATH/usr/sbin/gdm3" | sudo tee $UBUNTU_ROOTFS_PATH/etc/X11/default-display-manager
	sudo chroot $UBUNTU_ROOTFS_PATH /bin/bash -c "DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true dpkg-reconfigure gdm3"

	#dp sound
	sudo cp -R $UBUNTU_PATH/config/desktop/.config $UBUNTU_ROOTFS_PATH/etc/skel

	#setting
	sudo cp -R $UBUNTU_PATH/config/desktop/.local $UBUNTU_ROOTFS_PATH/etc/skel
}

build_ubuntu22_04()
{
    IMAGE_DIR="${1:-$RK_OUTDIR/ubuntu22.04}"

	message "=========================================="
	message "          Start building for Ubuntu"
	message "=========================================="

    if [ ! -d ubuntu ]; then
        message "ubuntu dir not exist"
        return
    fi

    if [ ! -f ubuntu/base/ubuntu-base-22.04-base-arm64.tar.gz ]; then
        message "ubuntu/base/ubuntu-base-22.04-base-arm64.tar.gz not exist"
        return
    fi

	cp ubuntu/base/config/headers-debian-byteshift.patch /tmp

	source "$RK_SCRIPTS_DIR/kernel-helper"
	$KMAKE bindeb-pkg KDEB_PKGVERSION=1.0 LOCAL_VERSION=-rockchip-5.10 KBUILD_DEBARCH=arm64 DEBFULLNAME=Namtso DEBEMAIL=hello@namtso.com CONFIG_SHELL=bash KDEB_COMPRESS=xz
	rm -rf *.buildinfo *.changes

    if [ ! -d ubuntu/base/temp ]; then
        #sudo rm -rf ubuntu/base/temp
		mkdir -p ubuntu/base/temp
		sudo tar -xzf ubuntu/base/ubuntu-base-22.04-base-arm64.tar.gz -C ubuntu/base/temp
		sudo cp -rpvf /usr/bin/qemu-aarch64-static ubuntu/base/temp/usr/bin/
		echo "nameserver 1.0.0.1" | sudo tee ubuntu/base/temp/etc/resolv.conf
    fi

	sudo cp -rpvf ubuntu/base/config/sources.list ubuntu/base/temp/etc/apt/sources.list
	sudo cp -rpvf ubuntu/base/script/chroot_script.sh ubuntu/base/temp/tmp/
	sudo cp -rpvf ubuntu/base/script/RUNME.sh ubuntu/base/temp/tmp/

	if grep "ubuntu/base/temp/sys" /proc/mounts; then
		sudo umount ubuntu/base/temp/sys
	fi

	if grep "ubuntu/base/temp/run" /proc/mounts; then
		sudo umount ubuntu/base/temp/run
	fi

	if grep "ubuntu/base/temp/proc" /proc/mounts; then
		sudo umount ubuntu/base/temp/proc
	fi

	if grep "ubuntu/base/temp/dev/pts" /proc/mounts; then
		sudo umount ubuntu/base/temp/dev/pts
	fi

	if grep "ubuntu/base/temp/dev" /proc/mounts; then
		sudo umount ubuntu/base/temp/dev
	fi


	sudo mount -t devtmpfs chdev ubuntu/base/temp/dev
	sudo mount -t proc chproc    ubuntu/base/temp/proc
	sudo mount -t sysfs chsys    ubuntu/base/temp/sys
	sudo mount -t devpts chpts   ubuntu/base/temp/dev/pts
	sudo mount -t tmpfs chrun    ubuntu/base/temp/run

	# local chroot_cmd="; ; apt -y upgrade; apt install -y vim; apt-get install -y gnome; \
	# 				 apt-get install -y  gnome; exit"
	sudo chroot ubuntu/base/temp /bin/bash -c "apt-get -y  update"
	sudo chroot ubuntu/base/temp /bin/bash -c "DEBIAN_FRONTEND=noninteractive  apt-get -y --show-progress -o DPKG::Progress-Fancy=1 upgrade"
	sudo chroot ubuntu/base/temp /bin/bash -c "apt-get -y  install sudo locales"

	sudo chroot ubuntu/base/temp /bin/bash -c "locale-gen en_US.UTF-8"
	sudo chroot ubuntu/base/temp /bin/bash -c "update-locale LANG=en_US.UTF-8 LANGUAGE=en_US.UTF-8 LC_MESSAGES=en_US.UTF-8"

    sudo chroot ubuntu/base/temp /bin/bash -c "/tmp/chroot_script.sh"
	sudo chroot ubuntu/base/temp /bin/bash -c "/tmp/RUNME.sh"

	ubuntu_install_package
	ubuntu_config_services
	ubuntu_config_network
	ubuntu_config_misc

    sudo umount ubuntu/base/temp/sys
	sudo umount ubuntu/base/temp/run
	sudo umount ubuntu/base/temp/proc
	sudo umount ubuntu/base/temp/dev/pts
    sudo umount ubuntu/base/temp/dev
	

    if [ -d ubuntu/base/rootfs ]; then
        sudo rm -rf ubuntu/base/rootfs
    fi

	if [ -f ubuntu/base/ubuntu_22.04.img ]; then
		rm -rf ubuntu/base/ubuntu_22.04.img
	fi

    mkdir -p ubuntu/base/rootfs
    dd if=/dev/zero of=ubuntu/base/ubuntu_22.04.img bs=1M count=6000
    mkfs.ext4 ubuntu/base/ubuntu_22.04.img
    sudo mount ubuntu/base/ubuntu_22.04.img ubuntu/base/rootfs/
    sudo cp -rfp ubuntu/base/temp/*  ubuntu/base/rootfs
    sudo umount ubuntu/base/rootfs/
    e2fsck -p -f ubuntu/base/ubuntu_22.04.img
    resize2fs  -M ubuntu/base/ubuntu_22.04.img


    ln -rsf ubuntu/base/ubuntu_22.04.img "$IMAGE_DIR/rootfs.ext4"

    finish_build build_ubuntu22_04 $@
}

# Hooks

usage_hook()
{
	echo -e "buildroot-config[:<config>]       \tmodify buildroot defconfig"
	echo -e "bconfig[:<config>]                \talias of buildroot-config"
	echo -e "buildroot-make[:<arg1>:<arg2>]    \trun buildroot make"
	echo -e "bmake[:<arg1>:<arg2>]             \talias of buildroot-make"
	echo -e "rootfs[:<rootfs type>]            \tbuild default rootfs"
	echo -e "buildroot                         \tbuild buildroot rootfs"
	echo -e "yocto                             \tbuild yocto rootfs"
	echo -e "debian                            \tbuild debian rootfs"
	echo -e "ubuntu                            \tbuild ubuntu rootfs"
}

clean_hook()
{
	rm -rf yocto/build/tmp yocto/build/*cache
	rm -rf debian/binary

	if check_config RK_BUILDROOT &>/dev/null; then
		rm -rf buildroot/output/$RK_BUILDROOT_CFG
	fi

	rm -rf "$RK_OUTDIR/buildroot"
	rm -rf "$RK_OUTDIR/yocto"
	rm -rf "$RK_OUTDIR/ubuntu"
	rm -rf  ubuntu/base/temp
	rm -rf  ubuntu/base/ubuntu_22.04.img
	rm -rf "$RK_OUTDIR/debian"
	rm -rf "$RK_OUTDIR/rootfs"
	rm -rf "$RK_FIRMWARE_DIR/rootfs.img"
}

INIT_CMDS="default buildroot debian yocto ubuntu"
init_hook()
{
	load_config RK_ROOTFS
	check_config RK_ROOTFS &>/dev/null || return 0

	# Priority: cmdline > custom env
	if [ "$1" != default ]; then
		export RK_ROOTFS_SYSTEM=$1
		notice "Using rootfs system($RK_ROOTFS_SYSTEM) from cmdline"
	elif [ "$RK_ROOTFS_SYSTEM" ]; then
		export RK_ROOTFS_SYSTEM=${RK_ROOTFS_SYSTEM//\"/}
		notice "Using rootfs system($RK_ROOTFS_SYSTEM) from environment"
	else
		return 0
	fi

	ROOTFS_CONFIG="RK_ROOTFS_SYSTEM=\"$RK_ROOTFS_SYSTEM\""
	ROOTFS_UPPER=$(echo $RK_ROOTFS_SYSTEM | tr 'a-z' 'A-Z')
	ROOTFS_CHOICE="RK_ROOTFS_SYSTEM_$ROOTFS_UPPER"
	if ! grep -q "^$ROOTFS_CONFIG$" "$RK_CONFIG"; then
		if ! grep -wq "$ROOTFS_CHOICE" "$RK_CONFIG"; then
			error "$RK_ROOTFS_SYSTEM not supported!"
			return 1
		fi

		sed -i -e "/RK_ROOTFS_SYSTEM/d" "$RK_CONFIG"
		echo "$ROOTFS_CONFIG" >> "$RK_CONFIG"
		echo "$ROOTFS_CHOICE=y" >> "$RK_CONFIG"
		"$RK_SCRIPTS_DIR/mk-config.sh" olddefconfig &>/dev/null
	fi
}

PRE_BUILD_CMDS="buildroot-config bconfig buildroot-make bmake"
pre_build_hook()
{
	check_config RK_ROOTFS || false

	case "$1" in
		buildroot-make | bmake)
			check_config RK_BUILDROOT || false

			shift
			"$RK_SCRIPTS_DIR/mk-buildroot.sh" \
				$RK_BUILDROOT_CFG make $@
			finish_build buildroot-make $@
			;;
		buildroot-config | bconfig)
			BUILDROOT_BOARD="${2:-"$RK_BUILDROOT_CFG"}"

			[ "$BUILDROOT_BOARD" ] || return 0

			TEMP_DIR=$(mktemp -d)
			unset BUILDROOT_OUTPUT_DIR
			make -C "$RK_SDK_DIR/buildroot" O="$TEMP_DIR" \
				"${BUILDROOT_BOARD}_defconfig" menuconfig
			"$RK_SDK_DIR/buildroot/build/update_defconfig.sh" \
				"$BUILDROOT_BOARD" "$TEMP_DIR"
			rm -rf "$TEMP_DIR"

			finish_build $@
			;;
	esac
}

BUILD_CMDS="rootfs buildroot debian yocto ubuntu"
build_hook()
{
	check_config RK_ROOTFS || false

	if [ -z "$1" -o "$1" = rootfs ]; then
		ROOTFS=${RK_ROOTFS_SYSTEM:-buildroot}
	else
		ROOTFS=$1
	fi

	ROOTFS_IMG=rootfs.${RK_ROOTFS_TYPE}
	ROOTFS_DIR="$RK_OUTDIR/$ROOTFS"
	IMAGE_DIR="$ROOTFS_DIR/images"

	message "=========================================="
	message "          Start building rootfs($ROOTFS)"
	message "=========================================="

	case "$ROOTFS" in
		yocto | debian | buildroot | ubuntu) ;;
		*) usage ;;
	esac

	rm -rf "$ROOTFS_DIR" "$RK_OUTDIR/rootfs"
	mkdir -p "$IMAGE_DIR"
	ln -rsf "$ROOTFS_DIR" "$RK_OUTDIR/rootfs"

	touch "$ROOTFS_DIR/.stamp_build_start"
	case "$ROOTFS" in
		yocto) build_yocto "$IMAGE_DIR" ;;
		debian) build_debian "$IMAGE_DIR" ;;
		buildroot) build_buildroot "$IMAGE_DIR" ;;
		ubuntu) build_ubuntu22_04 "$IMAGE_DIR" ;;
	esac
	touch "$ROOTFS_DIR/.stamp_build_finish"

	if [ ! -f "$IMAGE_DIR/$ROOTFS_IMG" ]; then
		error "There's no $ROOTFS_IMG generated..."
		exit 1
	fi

	if [ "$RK_ROOTFS_INITRD" ]; then
		"$RK_SCRIPTS_DIR/mk-ramboot.sh" "$ROOTFS_DIR" \
			"$IMAGE_DIR/$ROOTFS_IMG" "$RK_BOOT_FIT_ITS"
		ln -rsf "$ROOTFS_DIR/ramboot.img" "$RK_FIRMWARE_DIR/boot.img"
	elif [ "$RK_SECURITY_CHECK_SYSTEM_ENCRYPTION" -o \
		"$RK_SECURITY_CHECK_SYSTEM_VERITY" ]; then
		ln -rsf "$IMAGE_DIR/security_system.img" \
			"$RK_FIRMWARE_DIR/rootfs.img"
	else
		ln -rsf "$IMAGE_DIR/$ROOTFS_IMG" "$RK_FIRMWARE_DIR/rootfs.img"
	fi

	finish_build build_rootfs $@
}

source "${RK_BUILD_HELPER:-$(dirname "$(realpath "$0")")/../build-hooks/build-helper}"

case "${1:-rootfs}" in
	buildroot-config | bconfig | buildroot-make | bmake) pre_build_hook $@ ;;
	buildroot | debian | yocto | ubuntu) init_hook $@ ;&
	*) build_hook $@ ;;
esac
