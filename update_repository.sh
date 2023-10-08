#!/usr/bin/env bash

# Fail if anything goes wrong.
set -e
# Print each line before executing if Github arction debug logging is enabled
if [ "$RUNNER_DEBUG" == "1" ] 
then
    set -x
fi

# remove newlines from any input parameters
INPUT_PACKAGES="${INPUT_PACKAGES//$'\n'/ }"
INPUT_MISSING_AUR_DEPENDENCIES="${INPUT_MISSING_AUR_DEPENDENCIES//$'\n'/ }"
INPUT_MISSING_PACMAN_DEPENDENCIES="${INPUT_MISSING_PACMAN_DEPENDENCIES//$'\n'/ }"

# Get list of all packages with dependencies to install.
echo "AUR Packages requested to install: $INPUT_PACKAGES"
echo "AUR Packages to fix missing dependencies: $INPUT_MISSING_AUR_DEPENDENCIES"
echo "Name of pacman repository: $INPUT_REPONAME"
echo "Keep existing packages: $INPUT_KEEP"

packages_with_aur_dependencies="$(aur depends --pkgname $INPUT_PACKAGES $INPUT_MISSING_AUR_DEPENDENCIES)"
packages_with_aur_dependencies="${packages_with_aur_dependencies//$'\n'/ }"
for f in $INPUT_PACKAGES $INPUT_MISSING_AUR_DEPENDENCIES ;
do
    if [ "${packages_with_aur_dependencies/*${f}*/FOUND}" != "FOUND" ]
    then
        echo "ERROR: Package $f not found."
        exit 1
    fi
done
echo "AUR Packages to install (including dependencies): $packages_with_aur_dependencies"

# Check for optional missing pacman dependencies to install.
if [ -n "$INPUT_MISSING_PACMAN_DEPENDENCIES" ]
then
    echo "Additional Pacman packages to install: $INPUT_MISSING_PACMAN_DEPENDENCIES"
    pacman --noconfirm -S $INPUT_MISSING_PACMAN_DEPENDENCIES
fi

if [ "$INPUT_KEEP" == "true" ]
then
    # Copy workspace to local repo to avoid rebuilding and keep
    # existing packages, even older versions
    echo "Preserving existing files:"
    ls -l $GITHUB_WORKSPACE
    if [ ! -z "$(ls $GITHUB_WORKSPACE)" ]
    then
        cp -a $GITHUB_WORKSPACE/* /home/builder/workspace/
        chown -R builder:builder /home/builder/workspace/*
    fi
fi

# create an empty repository file
sudo --user builder \
    repo-add \
    /home/builder/workspace/$INPUT_REPONAME.db.tar.gz

## Register the local repository with pacman.
cat >> /etc/pacman.conf <<-EOF

# local repository (required by aur tools to be set up)
[$INPUT_REPONAME]
SigLevel = Optional
Server = file:///home/builder/workspace
EOF

# Sync repositories.
pacman -Sy

# Add the packages to the local repository.
sudo --user builder \
    aur sync \
    --noconfirm --noview \
    --database "$INPUT_REPONAME" --root /home/builder/workspace \
    $packages_with_aur_dependencies

if [ "$INPUT_KEEP" == "true" ] && 
    cmp --quiet \
        /home/builder/workspace/$INPUT_REPONAME.db \
        $GITHUB_WORKSPACE/$INPUT_REPONAME.db
then
    echo "updated=false" >>$GITHUB_OUTPUT
else
    echo "updated=true" >>$GITHUB_OUTPUT

    # Move the local repository to the workspace.
    if [ -n "$GITHUB_WORKSPACE" ]
    then
        rm -f /home/builder/workspace/*.old
        echo "Moving repository to github workspace"
        mv /home/builder/workspace/* $GITHUB_WORKSPACE/
        # make sure that the .db/.files files are in place
        # Note: Symlinks fail to upload, so copy those files
        cd $GITHUB_WORKSPACE
        rm $INPUT_REPONAME.db $INPUT_REPONAME.files
        cp $INPUT_REPONAME.db.tar.gz $INPUT_REPONAME.db
        cp $INPUT_REPONAME.files.tar.gz $INPUT_REPONAME.files
    else
        echo "No github workspace known (GITHUB_WORKSPACE is unset)."
    fi

fi