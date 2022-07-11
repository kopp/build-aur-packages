#!/usr/bin/env bash

# fail if anything goes wrong
set -e
# print each line before executing
set -x

# get list of all packages with dependencies to install
packages_with_aur_dependencies="$(aur depends --pkgname $INPUT_PACKAGES $INPUT_MISSING_AUR_DEPENDENCIES)"
echo "AUR Packages requested to install: $INPUT_PACKAGES"
echo "AUR Packages to fix missing dependencies: $INPUT_MISSING_AUR_DEPENDENCIES"
echo "AUR Packages to install (including dependencies): $packages_with_aur_dependencies"

# sync repositories
sudo pacman -Sy

if [ -n "$INPUT_MISSING_PACMAN_DEPENDENCIES" ]
then
    echo "Additional Pacman packages to install: $INPUT_MISSING_PACMAN_DEPENDENCIES"
    sudo pacman --noconfirm -S $INPUT_MISSING_PACMAN_DEPENDENCIES
fi

# add them to the local repository
aur sync \
    --noconfirm --noview \
    --database aurci2 --root /home/builder/workspace \
    $packages_with_aur_dependencies

# Move the local repository to the workspace.
# Preserve the environment to keep the GITHUB_WORKSPACE variable.
sudo --preserve-env /move_local_worksace_to_github_workspace.sh
