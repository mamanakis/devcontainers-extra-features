#!/usr/bin/env bash
set -ex

source ./library_scripts.sh

PACKAGE=${PACKAGE:-""}
VERSION=${VERSION:-"latest"}
INSTALLATION_FLAGS=${INSTALLATION_FLAGS:-""}

if [ -z "$PACKAGE" ]; then
	echo -e "'package' variable is empty, skipping"
	exit 0
fi

if [ "$(id -u)" -ne 0 ]; then
	echo -e 'Script must be run as
    root. Use sudo, su, or add "USER root" to your Dockerfile before running this script.'
	exit 1
fi

check_packages() {
	if ! dpkg -s "$@" >/dev/null 2>&1; then
		if [ "$(find /var/lib/apt/lists/* | wc -l)" = "0" ]; then
			echo "Running apt-get update..."
			apt-get update -y
		fi
		apt-get -y install --no-install-recommends "$@"
	fi
}

ensure_curl() {
	if ! type curl >/dev/null 2>&1; then
		apt-get update -y && apt-get -y install --no-install-recommends curl ca-certificates
	fi
}

install_via_homebrew() {
	package=$1
	version=$2
	installation_flags=$3

	# install Homebrew if does not exists
	if ! type brew >/dev/null 2>&1; then
		echo "Installing Homebrew..."

		# nanolayer is a cli utility which keeps container layers as small as possible
		# source code: https://github.com/devcontainers-extra/nanolayer
		# `ensure_nanolayer` is a bash function that will find any existing nanolayer installations,
		# and if missing - will download a temporary copy that automatically get deleted at the end
		# of the script
		ensure_nanolayer nanolayer_location "v0.5.6"

		$nanolayer_location \
			install \
			devcontainer-feature \
			"ghcr.io/meaningful-ooo/devcontainer-features/homebrew:2" \
			--option shallow_clone='true' --option update="true"
		source /etc/profile.d/nanolayer-homebrew.sh
	fi

	if [ "$version" = "latest" ]; then
		package_full="$package"
	else
		package_full="${package}@${version}"
	fi

	tap_dir="$(brew --prefix)/Homebrew/Library/Taps/homebrew/homebrew-core"
	if [ -d "$tap_dir" ]; then
		# Solves CVE-2022-24767 mitigation in Git >2.35.2
		# For more information: https://github.blog/2022-04-12-git-security-vulnerability-announced/
		git config --system --add safe.directory "$tap_dir"
	fi

	su - "$_REMOTE_USER" <<EOF
		set -e

		brew_safe_install() {
			local installation_flags=$1
			local package_full=$2

			# The reason for "--overwrite" flag is to not fail when a similarly
			# named binary is already linked
			brew install $installation_flags --overwrite "$package_full" --only-dependencies

			# The reason we first installing dependencies and only then the main
			# package is that some packages are big enough to reach the linux
			# open file limit. While normally this limit can be changed, the current
			# devcontainer feature building phase run unprivileged and therfore
			# cannot change the hard nofile limit from host machine during feature
			# build time.
			brew install $installation_flags --overwrite "$package_full"
		}

		if brew desc --formulae "$package_full" >/dev/null 2>&1; then
			brew_safe_install $installation_flags "$package_full"
		elif [ -d "$tap_dir" ]; then
			if [ "\$(git -C "$tap_dir" rev-parse --is-shallow-repository 2>/dev/null)" = "true" ]; then
				echo "Unshallowing homebrew-core. This could take a while."
				git -C "$tap_dir" fetch --unshallow
			fi

			if brew desc --formulae "$package" >/dev/null 2>&1; then
				brew_safe_install $installation_flags "$package"
			else
				echo "Formula '$package_full' not found in Homebrew formulae." >&2
				exit 1
			fi
		else
			echo "Formula '$package_full' not found in Homebrew formulae." >&2
			exit 1
		fi

		brew link --overwrite --force "$package_full"
EOF
}

install_via_homebrew "$PACKAGE" "$VERSION" "$INSTALLATION_FLAGS"