#!/usr/bin/env bash

# get list of all packages with dependencies to install
packages_with_aur_dependencies="$(aur depends --pkgname $INPUT_PACKAGES $INPUT_MISSING_AUR_DEPENDENCIES)"
echo "AUR Packages requested to install: $INPUT_PACKAGES"
echo "AUR Packages to fix missing dependencies: $INPUT_MISSING_AUR_DEPENDENCIES"
echo "AUR Packages to install (including dependencies): $packages_with_aur_dependencies"

# sync repositories
pacman -Sy

if [ -n "$INPUT_MISSING_PACMAN_DEPENDENCIES" ]
then
    echo "Additional Pacman packages to install: $INPUT_MISSING_PACMAN_DEPENDENCIES"
    pacman -S $INPUT_MISSING_PACMAN_DEPENDENCIES
fi

echo workspace
ls /workspace

# add them to the local repository
aur sync \
    --noconfirm --noview \
    --database aurci2 --root /workspace \
    $packages_with_aur_dependencies

# move the local repository to the workspace
if [ -n "$GITHUB_WORKSPACE" ]
then
    echo "Moving repository to github workspace"
    mv /workspace/* $GITHUB_WORKSPACE/
fi
