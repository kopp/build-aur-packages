#!/usr/bin/env bash

# Fail if anything goes wrong.
set -e
# Print each line before executing.
set -x

# Get list of all packages with dependencies to install.
packages_with_aur_dependencies="$(aur depends --pkgname $INPUT_PACKAGES $INPUT_MISSING_AUR_DEPENDENCIES)"
echo "AUR Packages requested to install: $INPUT_PACKAGES"
echo "AUR Packages to fix missing dependencies: $INPUT_MISSING_AUR_DEPENDENCIES"
echo "AUR Packages to install (including dependencies): $packages_with_aur_dependencies"

# Sync repositories.
pacman -Sy

# Check for optional missing pacman dependencies to install.
if [ -n "$INPUT_MISSING_PACMAN_DEPENDENCIES" ]
then
    echo "Additional Pacman packages to install: $INPUT_MISSING_PACMAN_DEPENDENCIES"
    pacman --noconfirm -S $INPUT_MISSING_PACMAN_DEPENDENCIES
fi

# Add the packages to the local repository.
sudo --user builder \
    aur sync \
    --noconfirm --noview \
    --clean \
    --database aurci2 --root /local_repository \
    $packages_with_aur_dependencies

# Move the local repository to the workspace.
if [ -n "$GITHUB_WORKSPACE" ]
then
    rm -f /local_repository/*.old
    echo "Moving repository to github workspace"
    mv /local_repository/* $GITHUB_WORKSPACE/
    # make sure that the .db/.files files are in place
    # Note: Symlinks fail to upload, so copy those files
    cd $GITHUB_WORKSPACE
    rm aurci2.db aurci2.files
    cp aurci2.db.tar.gz aurci2.db
    cp aurci2.files.tar.gz aurci2.files
else
    echo "No github workspace known (GITHUB_WORKSPACE is unset)."
fi
