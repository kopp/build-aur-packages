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

# Add the packages to the local repository one by one.
# We iterate through the list to ensure that if one package fails, 
# we can continue with the others.
for pkg in $packages_with_aur_dependencies; do
    echo "Building package: $pkg"
    if ! sudo --user builder \
        aur sync \
        --noconfirm --noview \
        --clean \
        --database aurci2 --root /local_repository \
        "$pkg"; then
        echo "Error: Failed to build package $pkg. Skipping..."
    fi
done

cd /local_repository
shopt -s nullglob
for file in *:*pkg.tar*; do
    echo "Detected colon in filename: $file"
    new_name="${file//:/.}"
    echo "Renaming to: $new_name"
    mv "$file" "$new_name"
    sudo --user builder repo-add aurci2.db.tar.gz "$new_name"
done
shopt -u nullglob

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
