#!/bin/bash -e

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

UBUNTU_PATH="ubuntu/base"
UBUNTU_ROOTFS_PATH_22_04="ubuntu/base/temp_22_04"
UBUNTU_ROOTFS_PATH_24_04="ubuntu/base/temp_24_04"

ubuntu_install_package()
{
	message "=========================================="
	message "          Install package for Ubuntu"
	message "=========================================="

	sudo cp -rpvf $UBUNTU_PATH/packages/* $1/root/
	sudo mv *.deb $1/root/

	if [ "$1" = "$UBUNTU_ROOTFS_PATH_22_04" ]; then
		sudo chroot $1 /bin/bash -c "dpkg -i /root/linux-gpu-mali-wayland_1.2-g13p0-230620_arm64.deb"
		sudo chroot $1 /bin/bash -c "dpkg -i /root/xwayland_22.1.1-1_arm64.deb"
		sudo chroot $1 /bin/bash -c "dpkg -i /root/mutter-common_42.0-3ubuntu3_all.deb"
		sudo chroot $1 /bin/bash -c "dpkg -i /root/mutter_42.0-3ubuntu3_arm64.deb"
		sudo chroot $1 /bin/bash -c "dpkg -i /root/libmutter-10-0_42.0-3ubuntu3_arm64.deb"
		sudo chroot $1 /bin/bash -c "dpkg -i /root/gir1.2-mutter-10_42.0-3ubuntu3_arm64.deb"
		sudo chroot $1 /bin/bash -c "dpkg -i /root/gir1.2-mutter-10_42.0-3ubuntu3_arm64.deb"
	fi

	sudo chroot $1 /bin/bash -c "dpkg -i /root/rockchip-mpp_1.5.0-9_arm64.deb"
	sudo chroot $1 /bin/bash -c "dpkg -i /root/rockchip-mpp-sample_1.5.0-9_arm64.deb"
	sudo chroot $1 /bin/bash -c "dpkg -i /root/rockchip-mpp-dev_1.5.0-9_arm64.deb"
	sudo chroot $1 /bin/bash -c "dpkg -i /root/rockchip-rga_2.2.0-6_arm64.deb"
	sudo chroot $1 /bin/bash -c "dpkg -i /root/rockchip-rga-sample_2.2.0-6_arm64.deb"
	sudo chroot $1 /bin/bash -c "dpkg -i /root/rockchip-rga-dev_2.2.0-6_arm64.deb"
	sudo chroot $1 /bin/bash -c "dpkg -i /root/gstreamer1.0-rockchip1_1.14-6_arm64.deb"
	
	sudo chroot $1 /bin/bash -c "dpkg -i /root/camera-engine-rkaiq_0.3-5.0x4.1_arm64.deb"
	sudo chroot $1 /bin/bash -c "dpkg -i /root/linux-image-rockchip-5.10_1.0_arm64.deb"
	sudo chroot $1 /bin/bash -c "dpkg -i /root/linux-dtb-rockchip-5.10_1.0_arm64.deb"
	sudo chroot $1 /bin/bash -c "dpkg -i /root/linux-headers-rockchip-5.10_1.0_arm64.deb"
	sudo chroot $1 /bin/bash -c "rm -rf /root/*.deb"
}

ubuntu_config_services()
{
	message "=========================================="
	message "          Config services for Ubuntu"
	message "=========================================="

	# copy exec
	sudo cp -rpvf $UBUNTU_PATH/bin/resize2fs $1/etc/init.d/
	sudo cp -rpvf $UBUNTU_PATH/bin/bluetooth-namtso.sh $1/usr/local/bin/
	sudo cp -rpvf $UBUNTU_PATH/bin/fan_setup.sh $1/usr/local/bin/
	sudo cp -rpvf $UBUNTU_PATH/bin/fan.sh $1/usr/local/bin/
	sudo cp -rpvf $UBUNTU_PATH/bin/namtso_bluetooth_suspend.sh $1/usr/local/bin/
	sudo cp -rpvf $UBUNTU_PATH/bin/fix-dp-sound.sh $1/usr/local/bin/
	sudo cp -rpvf $UBUNTU_PATH/bin/fix-gdm-wayland.sh $1/usr/local/bin/
	sudo cp -rpvf $UBUNTU_PATH/bin/fix-gdm-wayland-hotplug.sh $1/usr/local/bin/

	#copy services
	sudo cp -rpvf $UBUNTU_PATH/services/* $1/lib/systemd/system/

	#enable services
	sudo chroot $1 /bin/bash -c "systemctl --no-reload enable resize2fs.service"
	sudo chroot $1 /bin/bash -c "systemctl --no-reload enable rockchip-isp.service"
	sudo chroot $1 /bin/bash -c "systemctl --no-reload enable bluetooth-namtso.service"
	sudo chroot $1 /bin/bash -c "systemctl --no-reload enable bluetooth-suspend.service"
	sudo chroot $1 /bin/bash -c "systemctl --no-reload enable fan.service"
	# sudo chroot $1 /bin/bash -c "systemctl --no-reload enable gdm3.service"
	sudo chroot $1 /bin/bash -c "systemctl --no-reload enable fix-gdm-wayland.service"
	
	#disable services
	sudo chroot $1 /bin/bash -c "systemctl --no-reload mask ondemand.service"

	if [ "$1" = "$UBUNTU_ROOTFS_PATH_24_04" ]; then
		sudo cp -rpvf $UBUNTU_PATH/bin/fix-gdm-multi-screen-display.sh $1/usr/local/bin/
		sudo chroot $1 /bin/bash -c "systemctl --no-reload enable gdm_multi_screen_display.service"
	fi
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

	sudo rm -f $1/etc/network/interfaces
	message "Setup timezone to '$TZDATA'"
	echo $TZDATA | sudo tee $1/etc/timezone
	sudo ln -sf ../usr/share/zoneinfo/$TZDATA  $1/etc/localtime
	sudo chroot $1 /bin/bash -c "dpkg-reconfigure -f noninteractive tzdata"

	date -u '+%Y-%m-%d %H:%M:%S' | sudo tee $1/etc/fake-hwclock.data

	# configure network manager
	sudo sed "s/managed=\(.*\)/managed=true/g" -i $1/etc/NetworkManager/NetworkManager.conf
	sudo sed "/dns/d" -i $1/etc/NetworkManager/NetworkManager.conf
	sudo sed "/rc-manager/d" -i $1/etc/NetworkManager/NetworkManager.conf
	sudo sed "s/\[main\]/\[main\]\ndns=default\nrc-manager=file/g" -i $1/etc/NetworkManager/NetworkManager.conf
	if [[ -n $NM_IGNORE_DEVICES ]]; then
		sudo mkdir -p $1/etc/NetworkManager/conf.d/
		cat <<-EOF > $1/etc/NetworkManager/conf.d/10-ignore-interfaces.conf
		[keyfile]
		unmanaged-devices=$NM_IGNORE_DEVICES
		EOF
	fi

	# nsswitch settings for sane DNS behavior: remove resolve, assure libnss-myhostname support
	sudo sed "s/hosts\:.*/hosts:          files mymachines dns myhostname/g" -i $1/etc/nsswitch.conf

	if [ -d $1/etc/resolvconf/resolv.conf.d ]; then
		echo "nameserver $NAMESERVER" | sudo tee $1/etc/resolvconf/resolv.conf.d/head
	fi

	sudo sed -i "s/#DNS=.*/DNS=$NAMESERVER/g" $1/etc/systemd/resolved.conf

	sudo cp -rpvf $UBUNTU_PATH/config/10-globally-managed-devices.conf $1/etc/NetworkManager/conf.d

	# ssh
	sudo chroot $1 /bin/bash -c "dpkg-reconfigure openssh-server"
}

ubuntu_config_misc()
{
	# mount
	sudo chroot $1 /bin/bash -c "mkdir -p /userdata"
	sudo chroot $1 /bin/bash -c "mkdir -p /oem"
	sudo cp -rpvf $UBUNTU_PATH/config/fstab $1/etc/

	# dtbo
	sudo mkdir -p $1/boot/overlays/rk3588-namtso-a10-3588.dtb.overlays
	sudo touch $1/boot/overlays/rk3588-namtso-a10-3588.dtb.overlay.env
	echo "fdt_overlays=" | sudo tee $1/boot/overlays/rk3588-namtso-a10-3588.dtb.overlay.env
	sudo cp -rf kernel/arch/arm64/boot/dts/rockchip/overlays/*.dtbo  $1/boot/overlays/rk3588-namtso-a10-3588.dtb.overlays

	#uEnv
	sudo cp -rpvf $UBUNTU_PATH/config/uEnv.txt $1/boot/

	# wifi & bt
	sudo cp -rpvf $UBUNTU_PATH/firmware/wlan/* $1/lib/firmware/
	sudo cp -rpvf $UBUNTU_PATH/bin/brcm_patchram_plus-arm64 $1/usr/local/bin/
	sudo cp -rpvf $UBUNTU_PATH/bin/brcm_patchram_plus-armhf $1/usr/local/bin/
	sudo cp -rpvf $UBUNTU_PATH/bin/hciattach-arm64 $1/usr/local/bin/hciattach
	sudo cp -rpvf $UBUNTU_PATH/bin/hciattach-armhf $1/usr/local/bin/
	if [ ! -d $1/etc/firmware ]; then
		sudo chroot $1 /bin/bash -c "ln -s /lib/firmware /etc/firmware"
	fi

	# udev
	sudo cp -rpvf $UBUNTU_PATH/config/udev/rules.d/* $1/etc/udev/rules.d/

	# audio
	sudo cp -rpvf $UBUNTU_PATH/config/audio/asound.state $1/var/lib/alsa/
	sudo cp -rpvf $UBUNTU_PATH/config/audio/default.pa.jammy.a10-3588.5.10 $1/etc/pulse/

	#gdm
	sudo sed -i 's/#WaylandEnable=.*/WaylandEnable=true/g' $1/etc/gdm3/custom.conf
	echo "$1/usr/sbin/gdm3" | sudo tee $1/etc/X11/default-display-manager
	sudo chroot $1 /bin/bash -c "DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true dpkg-reconfigure gdm3"

	#dp sound
	sudo cp -R $UBUNTU_PATH/config/desktop/.config $1/etc/skel

	#setting
	sudo cp -R $UBUNTU_PATH/config/desktop/.local $1/etc/skel

	sudo cp -arf $UBUNTU_PATH/config/desktop/.config $1/home/namtso
	sudo cp -arf $UBUNTU_PATH/config/desktop/.local $1/home/namtso

	eval 'LC_ALL=C LANG=C sudo chroot $1 /bin/bash -c "chown namtso:namtso /home/namtso/.config -R"'
	eval 'LC_ALL=C LANG=C sudo chroot $1 /bin/bash -c "chown namtso:namtso /home/namtso/.local  -R"'
	eval 'LC_ALL=C LANG=C sudo chroot $1 /bin/bash -c "chown root:root /home/"'

	sudo mkdir -p $1/usr/local/icons
	sudo cp -rpvf $UBUNTU_PATH/config/desktop/icons/* $1/usr/local/icons

	sudo cp -rpvf $UBUNTU_PATH/bin/rc.local $1/etc/

	# OTA
	if [ -f device/rockchip/common/tools/aarch64/update ]; then
		sudo cp -rpvf device/rockchip/common/tools/aarch64/update  $1/usr/local/bin/
	fi

	if [ -f device/rockchip/common/tools/aarch64/updateEngine ]; then
		sudo cp -rpvf device/rockchip/common/tools/aarch64/updateEngine  $1/usr/local/bin/
	fi

}

build_ubuntu22_04()
{
    IMAGE_DIR="${1:-$RK_OUTDIR/ubuntu22.04}"

	message "=========================================="
	message "          Start building for Ubuntu22.04"
	message "=========================================="

    if [ ! -d ubuntu ]; then
        message "ubuntu dir not exist"
        return
    fi

    if [ ! -f $UBUNTU_PATH/ubuntu-base-22.04-base-arm64.tar.gz ]; then
        message "$UBUNTU_PATH/ubuntu-base-22.04-base-arm64.tar.gz not exist"
        return
    fi

	cp $UBUNTU_PATH/config/headers-debian-byteshift.patch /tmp

	source "$RK_SCRIPTS_DIR/kernel-helper"
	$KMAKE bindeb-pkg KDEB_PKGVERSION=1.0 LOCAL_VERSION=-rockchip-5.10 KBUILD_DEBARCH=arm64 DEBFULLNAME=Namtso DEBEMAIL=hello@namtso.com CONFIG_SHELL=bash KDEB_COMPRESS=xz
	rm -rf *.buildinfo *.changes

    if [ ! -d $UBUNTU_ROOTFS_PATH_22_04 ]; then
        #sudo rm -rf $UBUNTU_ROOTFS_PATH_22_04
		mkdir -p $UBUNTU_ROOTFS_PATH_22_04
		sudo tar -xzf $UBUNTU_PATH/ubuntu-base-22.04-base-arm64.tar.gz -C $UBUNTU_ROOTFS_PATH_22_04
		sudo cp -rpvf /usr/bin/qemu-aarch64-static $UBUNTU_ROOTFS_PATH_22_04/usr/bin/
		echo "nameserver 1.0.0.1" | sudo tee $UBUNTU_ROOTFS_PATH_22_04/etc/resolv.conf
    fi

	sudo cp -rpvf $UBUNTU_PATH/config/sources_22.04.list $UBUNTU_ROOTFS_PATH_22_04/etc/apt/sources.list
	sudo cp -rpvf $UBUNTU_PATH/script/chroot_script_22_04.sh $UBUNTU_ROOTFS_PATH_22_04/tmp/chroot_script.sh
	sudo cp -rpvf $UBUNTU_PATH/script/RUNME.sh $UBUNTU_ROOTFS_PATH_22_04/tmp/

	if grep "$UBUNTU_ROOTFS_PATH_22_04/sys" /proc/mounts; then
		sudo umount $UBUNTU_ROOTFS_PATH_22_04/sys
	fi

	if grep "$UBUNTU_ROOTFS_PATH_22_04/run" /proc/mounts; then
		sudo umount $UBUNTU_ROOTFS_PATH_22_04/run
	fi

	if grep "$UBUNTU_ROOTFS_PATH_22_04/proc" /proc/mounts; then
		sudo umount $UBUNTU_ROOTFS_PATH_22_04/proc
	fi

	if grep "$UBUNTU_ROOTFS_PATH_22_04/dev/pts" /proc/mounts; then
		sudo umount $UBUNTU_ROOTFS_PATH_22_04/dev/pts
	fi

	if grep "$UBUNTU_ROOTFS_PATH_22_04/dev" /proc/mounts; then
		sudo umount $UBUNTU_ROOTFS_PATH_22_04/dev
	fi


	sudo mount -t devtmpfs chdev $UBUNTU_ROOTFS_PATH_22_04/dev
	sudo mount -t proc chproc    $UBUNTU_ROOTFS_PATH_22_04/proc
	sudo mount -t sysfs chsys    $UBUNTU_ROOTFS_PATH_22_04/sys
	sudo mount -t devpts chpts   $UBUNTU_ROOTFS_PATH_22_04/dev/pts
	sudo mount -t tmpfs chrun    $UBUNTU_ROOTFS_PATH_22_04/run

	# local chroot_cmd="; ; apt -y upgrade; apt install -y vim; apt-get install -y gnome; \
	# 				 apt-get install -y  gnome; exit"
	sudo chroot $UBUNTU_ROOTFS_PATH_22_04 /bin/bash -c "apt-get -y  update"
	sudo chroot $UBUNTU_ROOTFS_PATH_22_04 /bin/bash -c "DEBIAN_FRONTEND=noninteractive  apt-get -y --show-progress -o DPKG::Progress-Fancy=1 upgrade"
	sudo chroot $UBUNTU_ROOTFS_PATH_22_04 /bin/bash -c "apt-get -y  install sudo locales"

	sudo chroot $UBUNTU_ROOTFS_PATH_22_04 /bin/bash -c "locale-gen en_US.UTF-8"
	sudo chroot $UBUNTU_ROOTFS_PATH_22_04 /bin/bash -c "update-locale LANG=en_US.UTF-8 LANGUAGE=en_US.UTF-8 LC_MESSAGES=en_US.UTF-8"

    sudo chroot $UBUNTU_ROOTFS_PATH_22_04 /bin/bash -c "/tmp/chroot_script.sh"
	sudo chroot $UBUNTU_ROOTFS_PATH_22_04 /bin/bash -c "/tmp/RUNME.sh"

	ubuntu_install_package $UBUNTU_ROOTFS_PATH_22_04
	ubuntu_config_services $UBUNTU_ROOTFS_PATH_22_04
	ubuntu_config_network  $UBUNTU_ROOTFS_PATH_22_04
	ubuntu_config_misc     $UBUNTU_ROOTFS_PATH_22_04

    sudo umount $UBUNTU_ROOTFS_PATH_22_04/sys
	sudo umount $UBUNTU_ROOTFS_PATH_22_04/run
	sudo umount $UBUNTU_ROOTFS_PATH_22_04/proc
	sudo umount $UBUNTU_ROOTFS_PATH_22_04/dev/pts
    sudo umount $UBUNTU_ROOTFS_PATH_22_04/dev
	

    if [ -d $UBUNTU_PATH/rootfs ]; then
        sudo rm -rf $UBUNTU_PATH/rootfs
    fi

	if [ -f $UBUNTU_PATH/ubuntu_22.04.img ]; then
		rm -rf $UBUNTU_PATH/ubuntu_22.04.img
	fi

    mkdir -p $UBUNTU_PATH/rootfs
    dd if=/dev/zero of=$UBUNTU_PATH/ubuntu_22.04.img bs=1M count=6000
    mkfs.ext4 $UBUNTU_PATH/ubuntu_22.04.img
    sudo mount $UBUNTU_PATH/ubuntu_22.04.img $UBUNTU_PATH/rootfs/
    sudo cp -rfp $UBUNTU_ROOTFS_PATH_22_04/*  $UBUNTU_PATH/rootfs
    sudo umount $UBUNTU_PATH/rootfs/
    e2fsck -p -f $UBUNTU_PATH/ubuntu_22.04.img
    resize2fs  -M $UBUNTU_PATH/ubuntu_22.04.img


    ln -rsf $UBUNTU_PATH/ubuntu_22.04.img "$IMAGE_DIR/rootfs.ext4"

    finish_build build_ubuntu22_04 $@
}

build_ubuntu24_04()
{
	IMAGE_DIR="${1:-$RK_OUTDIR/ubuntu24.04}"

	message "=========================================="
	message "          Start building for Ubuntu24.04"
	message "=========================================="

    if [ ! -d ubuntu ]; then
        message "ubuntu dir not exist"
        return
    fi

    if [ ! -f $UBUNTU_PATH/ubuntu-base-24.04-base-arm64.tar.gz ]; then
        message "$UBUNTU_PATH/ubuntu-base-24.04-base-arm64.tar.gz not exist"
        return
    fi

	cp $UBUNTU_PATH/config/headers-debian-byteshift.patch /tmp

	source "$RK_SCRIPTS_DIR/kernel-helper"
	$KMAKE bindeb-pkg KDEB_PKGVERSION=1.0 LOCAL_VERSION=-rockchip-5.10 KBUILD_DEBARCH=arm64 DEBFULLNAME=Namtso DEBEMAIL=hello@namtso.com CONFIG_SHELL=bash KDEB_COMPRESS=xz
	rm -rf *.buildinfo *.changes

    if [ ! -d $UBUNTU_ROOTFS_PATH_24_04 ]; then
        #sudo rm -rf $UBUNTU_ROOTFS_PATH_24_04
		mkdir -p $UBUNTU_ROOTFS_PATH_24_04
		sudo tar -xzf $UBUNTU_PATH/ubuntu-base-24.04-base-arm64.tar.gz -C $UBUNTU_ROOTFS_PATH_24_04
		sudo cp -rpvf /usr/bin/qemu-aarch64-static $UBUNTU_ROOTFS_PATH_24_04/usr/bin/
		echo "nameserver 1.0.0.1" | sudo tee $UBUNTU_ROOTFS_PATH_24_04/etc/resolv.conf
    fi

	sudo cp -rpvf $UBUNTU_PATH/config/sources_24.04.list $UBUNTU_ROOTFS_PATH_24_04/etc/apt/sources.list
	sudo cp -rpvf $UBUNTU_PATH/script/chroot_script_24_04.sh $UBUNTU_ROOTFS_PATH_24_04/tmp/chroot_script.sh
	sudo cp -rpvf $UBUNTU_PATH/script/RUNME.sh $UBUNTU_ROOTFS_PATH_24_04/tmp/

	if grep "$UBUNTU_ROOTFS_PATH_24_04/sys" /proc/mounts; then
		sudo umount $UBUNTU_ROOTFS_PATH_24_04/sys
	fi

	if grep "$UBUNTU_ROOTFS_PATH_24_04/run" /proc/mounts; then
		sudo umount $UBUNTU_ROOTFS_PATH_24_04/run
	fi

	if grep "$UBUNTU_ROOTFS_PATH_24_04/proc" /proc/mounts; then
		sudo umount $UBUNTU_ROOTFS_PATH_24_04/proc
	fi

	if grep "$UBUNTU_ROOTFS_PATH_24_04/dev/pts" /proc/mounts; then
		sudo umount $UBUNTU_ROOTFS_PATH_24_04/dev/pts
	fi

	if grep "$UBUNTU_ROOTFS_PATH_24_04/dev" /proc/mounts; then
		sudo umount $UBUNTU_ROOTFS_PATH_24_04/dev
	fi


	sudo mount -t devtmpfs chdev $UBUNTU_ROOTFS_PATH_24_04/dev
	sudo mount -t proc chproc    $UBUNTU_ROOTFS_PATH_24_04/proc
	sudo mount -t sysfs chsys    $UBUNTU_ROOTFS_PATH_24_04/sys
	sudo mount -t devpts chpts   $UBUNTU_ROOTFS_PATH_24_04/dev/pts
	sudo mount -t tmpfs chrun    $UBUNTU_ROOTFS_PATH_24_04/run

	# local chroot_cmd="; ; apt -y upgrade; apt install -y vim; apt-get install -y gnome; \
	# 				 apt-get install -y  gnome; exit"
	sudo chroot $UBUNTU_ROOTFS_PATH_24_04 /bin/bash -c "apt-get -y  update"
	sudo chroot $UBUNTU_ROOTFS_PATH_24_04 /bin/bash -c "DEBIAN_FRONTEND=noninteractive  apt-get -y --show-progress -o DPKG::Progress-Fancy=1 upgrade"
	sudo chroot $UBUNTU_ROOTFS_PATH_24_04 /bin/bash -c "apt-get -y  install sudo locales"

	sudo chroot $UBUNTU_ROOTFS_PATH_24_04 /bin/bash -c "locale-gen en_US.UTF-8"
	sudo chroot $UBUNTU_ROOTFS_PATH_24_04 /bin/bash -c "update-locale LANG=en_US.UTF-8 LANGUAGE=en_US.UTF-8 LC_MESSAGES=en_US.UTF-8"

    sudo chroot $UBUNTU_ROOTFS_PATH_24_04 /bin/bash -c "/tmp/chroot_script.sh"
	sudo chroot $UBUNTU_ROOTFS_PATH_24_04 /bin/bash -c "/tmp/RUNME.sh"

	# sudo cp -rpvf $UBUNTU_PATH/bin/mali_csffw_6.1.bin  $UBUNTU_ROOTFS_PATH_24_04/lib/firmware

	cat <<-EOF | sudo tee $UBUNTU_ROOTFS_PATH_24_04/etc/apt/sources.list.d/liujianfeng1994-ubuntu-panfork-mesa-jammy.list
	deb https://ppa.launchpadcontent.net/liujianfeng1994/panfork-mesa/ubuntu/ jammy main
	# deb-src https://ppa.launchpadcontent.net/liujianfeng1994/panfork-mesa/ubuntu/ jammy main
	EOF

	sudo cp -rpvf $UBUNTU_PATH/config/panfork.key $UBUNTU_ROOTFS_PATH_24_04
	sudo rm -rf $UBUNTU_ROOTFS_PATH_24_04/etc/apt/trusted.gpg.d/panfork.gpg
	eval 'LC_ALL=C LANG=C sudo chroot $UBUNTU_ROOTFS_PATH_24_04 /bin/bash -c "cat panfork.key | gpg --dearmor -o /etc/apt/trusted.gpg.d/panfork.gpg"'
	sudo rm -rf $UBUNTU_ROOTFS_PATH_24_04/panfork.key

	# this should fix resolvconf installation failure in some cases
	eval 'LC_ALL=C LANG=C sudo chroot $UBUNTU_ROOTFS_PATH_24_04 /bin/bash -c "echo "resolvconf resolvconf/linkify-resolvconf boolean false" | debconf-set-selections"'

	sudo rm $UBUNTU_ROOTFS_PATH_24_04/etc/resolv.conf
    echo "nameserver 1.0.0.1" | sudo tee $UBUNTU_ROOTFS_PATH_24_04/etc/resolv.conf

	# stage: update packages list
	message "Updating package list $UBUNTU_ROOTFS_PATH_24_04"
	eval 'LC_ALL=C LANG=C sudo chroot $UBUNTU_ROOTFS_PATH_24_04 /bin/bash -c "DEBIAN_FRONTEND=noninteractive apt-get -y $apt_extra update"'
	eval 'LC_ALL=C LANG=C sudo chroot $UBUNTU_ROOTFS_PATH_24_04 /bin/bash -c "DEBIAN_FRONTEND=noninteractive apt-get -y $apt_extra dist-upgrade"'

	ubuntu_install_package  $UBUNTU_ROOTFS_PATH_24_04
	ubuntu_config_services  $UBUNTU_ROOTFS_PATH_24_04
	ubuntu_config_network   $UBUNTU_ROOTFS_PATH_24_04
	ubuntu_config_misc      $UBUNTU_ROOTFS_PATH_24_04

    sudo umount $UBUNTU_ROOTFS_PATH_24_04/sys
	sudo umount $UBUNTU_ROOTFS_PATH_24_04/run
	sudo umount $UBUNTU_ROOTFS_PATH_24_04/proc
	sudo umount $UBUNTU_ROOTFS_PATH_24_04/dev/pts
    sudo umount $UBUNTU_ROOTFS_PATH_24_04/dev
	

    if [ -d $UBUNTU_PATH/rootfs ]; then
        sudo rm -rf $UBUNTU_PATH/rootfs
    fi

	if [ -f $UBUNTU_PATH/ubuntu_24.04.img ]; then
		rm -rf $UBUNTU_PATH/ubuntu_24.04.img
	fi

    mkdir -p $UBUNTU_PATH/rootfs
    dd if=/dev/zero of=$UBUNTU_PATH/ubuntu_24.04.img bs=1M count=6000
    mkfs.ext4 $UBUNTU_PATH/ubuntu_24.04.img
    sudo mount $UBUNTU_PATH/ubuntu_24.04.img $UBUNTU_PATH/rootfs/
    sudo cp -rfp $UBUNTU_ROOTFS_PATH_24_04/*  $UBUNTU_PATH/rootfs
    sudo umount $UBUNTU_PATH/rootfs/
    e2fsck -p -f $UBUNTU_PATH/ubuntu_24.04.img
    resize2fs  -M $UBUNTU_PATH/ubuntu_24.04.img


    ln -rsf $UBUNTU_PATH/ubuntu_24.04.img "$IMAGE_DIR/rootfs.ext4"
	finish_build build_ubuntu24_04 $@
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
	echo -e "ubuntu22.04                       \tbuild ubuntu22.04 rootfs"
	echo -e "ubuntu24.04                       \tbuild ubuntu24.04 rootfs"
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
	rm -rf "$RK_OUTDIR/ubuntu22.04"
	rm -rf "$RK_OUTDIR/ubuntu24.04"
	sudo rm -rf "$UBUNTU_ROOTFS_PATH_22_04"
	sudo rm -rf "$UBUNTU_ROOTFS_PATH_24_04"
	rm -rf "$UBUNTU_PATH/ubuntu_22.04.img"
	rm -rf "$UBUNTU_PATH/ubuntu_24.04.img"
	rm -rf "$RK_OUTDIR/debian"
	rm -rf "$RK_OUTDIR/rootfs"
	rm -rf "$RK_FIRMWARE_DIR/rootfs.img"
}

INIT_CMDS="default buildroot debian yocto ubuntu22.04 ubuntu24.04"
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

	if [ $RK_ROOTFS_SYSTEM = "ubuntu22.04" ]; then
		RK_ROOTFS_SYSTEM=ubuntu_22_04
	fi

	if [ $RK_ROOTFS_SYSTEM = "ubuntu24.04" ]; then
		RK_ROOTFS_SYSTEM=ubuntu_24_04
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

BUILD_CMDS="rootfs buildroot debian yocto ubuntu22.04 ubuntu24.04"
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
		yocto | debian | buildroot | ubuntu22.04 | ubuntu24.04) ;;
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
		ubuntu22.04) build_ubuntu22_04 "$IMAGE_DIR" ;;
		ubuntu24.04) build_ubuntu24_04 "$IMAGE_DIR" ;;
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
	buildroot | debian | yocto | ubuntu22.04 | ubuntu24.04) init_hook $@ ;&
	*) build_hook $@ ;;
esac
