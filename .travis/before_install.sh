#!/bin/sh
if [ "$TRAVIS_OS_NAME" = "linux" -a -z "$config" ]; then
	case "$TRAVIS_CPU_ARCH" in
		amd64 | s390x)
			pkgs="gobjc-multilib"
			;;
		*)
			pkgs="gobjc"
			;;
	esac

	pkgs="$pkgs libsctp-dev"

	if grep precise /etc/lsb-release >/dev/null; then
		pkgs="$pkgs ipx"
	fi

	# We don't need any of them and they're often broken.
	sudo rm -f /etc/apt/sources.list.d/*

	if ! sudo apt-get -qq update >/tmp/apt_log 2>&1; then
		cat /tmp/apt_log
		exit 1
	fi

	if ! sudo apt-get -qq install -y $pkgs >>/tmp/apt_log 2>&1; then
		cat /tmp/apt_log
		exit 1
	fi

	if grep precise /etc/lsb-release >/dev/null; then
		sudo ipx_internal_net add 1234 123456
	fi
fi

if [ "$TRAVIS_OS_NAME" = "windows" ]; then
	# https://docs.travis-ci.com/user/reference/windows/#how-do-i-use-msys2
	choco uninstall -y mingw
	choco upgrade --no-progress -y msys2
	export msys2='cmd //C RefreshEnv.cmd '
	export msys2+='& set MSYS=winsymlinks:nativestrict '
	export msys2+='& C:\\tools\\msys64\\msys2_shell.cmd -defterm -no-start'
	export mingw64="$msys2 -mingw64 -full-path -here -c "\"\$@"\" --"
	export msys2+=" -msys2 -c "\"\$@"\" --"
	$msys2 pacman -S --noconfirm --needed \
		mingw-w64-i686-toolchain mingw-w64-x86_64-toolchain \
		autoconf automake
	if [ "$compiler" = "clang" ]; then
		$msys2 pacman -S --noconfirm --needed \
			mingw-w64-i686-clang mingw-w64-x86_64-clang
	fi
	taskkill //IM gpg-agent.exe //F  # https://travis-ci.community/t/4967
fi

if [ "$config" = "nintendo_3ds" -o "$config" = "nintendo_ds" ]; then
	docker pull devkitpro/devkitarm
fi

if [ "$config" = "wii" ]; then
	docker pull devkitpro/devkitppc
fi

if [ "$config" = "amigaos" ]; then
	wget -q https://franke.ms/download/amiga-gcc.tgz
	tar -C / -xzf amiga-gcc.tgz
fi
