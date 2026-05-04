#!/usr/bin/env bash

# Fail if anything goes wrong.
set -e
# Print each line before executing.
set -x

INPUT_PACKAGES="${INPUT_PACKAGES:-}"
INPUT_CUSTOM_PKGBUILD_DIRECTORIES="${INPUT_CUSTOM_PKGBUILD_DIRECTORIES:-}"
INPUT_MISSING_PACMAN_DEPENDENCIES="${INPUT_MISSING_PACMAN_DEPENDENCIES:-}"
INPUT_MISSING_AUR_DEPENDENCIES="${INPUT_MISSING_AUR_DEPENDENCIES:-}"
CUSTOM_BUILT_PACKAGE_NAMES=""

if [ -z "$INPUT_PACKAGES" ] && [ -z "$INPUT_CUSTOM_PKGBUILD_DIRECTORIES" ]
then
    echo "Error: Set at least one of packages or custom_pkgbuild_directories."
    exit 1
fi

resolve_pkgbuild_directory() {
    local input_directory="$1"

    if [[ "$input_directory" = /* ]]
    then
        printf '%s\n' "$input_directory"
    elif [ -n "$GITHUB_WORKSPACE" ]
    then
        printf '%s\n' "$GITHUB_WORKSPACE/$input_directory"
    else
        printf '%s\n' "$input_directory"
    fi
}

add_package_to_repository() {
    local package_file="$1"
    local package_destination="/local_repository/$(basename -- "$package_file")"

    cp -- "$package_file" "$package_destination" || return 1
    chown builder:alpm "$package_destination" || return 1
    sudo --user builder repo-add /local_repository/aurci2.db.tar.gz "$package_destination" || return 1

    local package_info
    package_info="$(pacman -Qp "$package_destination")" || return 1
    CUSTOM_BUILT_PACKAGE_NAMES="$CUSTOM_BUILT_PACKAGE_NAMES ${package_info%% *}"
}

build_custom_pkgbuild_directory() {
    local input_directory="$1"
    local source_directory
    source_directory="$(resolve_pkgbuild_directory "$input_directory")"

    if [ ! -d "$source_directory" ]
    then
        echo "Error: Custom PKGBUILD directory does not exist: $source_directory"
        return 1
    fi

    if [ ! -f "$source_directory/PKGBUILD" ]
    then
        echo "Error: Custom PKGBUILD directory has no PKGBUILD: $source_directory"
        return 1
    fi

    local build_directory
    build_directory="$(mktemp -d /tmp/custom-pkgbuild.XXXXXX)" || return 1

    cp -a "$source_directory"/. "$build_directory"/ || return 1
    chown -R builder:alpm "$build_directory" || return 1

    sudo --user builder bash -c \
        'cd "$1" && makepkg --syncdeps --noconfirm --clean' \
        _ "$build_directory" || return 1

    local package_list
    package_list="$(sudo --user builder bash -c \
        'cd "$1" && makepkg --packagelist' \
        _ "$build_directory")" || return 1

    if [ -z "$package_list" ]
    then
        echo "Error: Custom PKGBUILD did not produce any package files: $source_directory"
        return 1
    fi

    local package_file
    local package_path
    while IFS= read -r package_file
    do
        [ -n "$package_file" ] || continue
        if [ -f "$package_file" ]
        then
            package_path="$package_file"
        elif [ -f "$build_directory/$package_file" ]
        then
            package_path="$build_directory/$package_file"
        else
            echo "Error: Expected package file does not exist: $package_file"
            return 1
        fi

        add_package_to_repository "$package_path" || return 1
    done <<< "$package_list"

    # Refresh the local repository database so later custom PKGBUILDs can depend
    # on packages built earlier in this run.
    pacman -Sy || return 1
}

build_aur_packages() {
    local requested_packages="$1"
    local description="$2"

    if [ -z "$requested_packages" ]
    then
        echo "No $description."
        return 0
    fi

    local packages_with_dependencies
    packages_with_dependencies="$(aur depends --pkgname $requested_packages)"

    echo "$description: $requested_packages"
    echo "$description (including dependencies): $packages_with_dependencies"

    # Add the packages to the local repository one by one.
    # We iterate through the list to ensure that if one package fails,
    # we can continue with the others.
    for pkg in $packages_with_dependencies; do
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

    pacman -Sy
}

is_custom_built_package() {
    local package_name="$1"
    local custom_package_name

    for custom_package_name in $CUSTOM_BUILT_PACKAGE_NAMES; do
        if [ "$package_name" = "$custom_package_name" ]
        then
            return 0
        fi
    done

    return 1
}

filter_custom_packages_from_aur_requests() {
    local requested_packages="$1"
    local filtered_packages=""
    local requested_package

    for requested_package in $requested_packages; do
        if is_custom_built_package "$requested_package"
        then
            echo "Skipping AUR package $requested_package because a custom PKGBUILD built it." >&2
        else
            filtered_packages="$filtered_packages $requested_package"
        fi
    done

    printf '%s\n' "$filtered_packages"
}

echo "AUR Packages requested to install: $INPUT_PACKAGES"
echo "AUR Packages to fix missing dependencies: $INPUT_MISSING_AUR_DEPENDENCIES"
echo "Custom PKGBUILD directories requested: $INPUT_CUSTOM_PKGBUILD_DIRECTORIES"

# Sync repositories.
pacman -Sy

# Check for optional missing pacman dependencies to install.
if [ -n "$INPUT_MISSING_PACMAN_DEPENDENCIES" ]
then
    echo "Additional Pacman packages to install: $INPUT_MISSING_PACMAN_DEPENDENCIES"
    pacman --noconfirm -S $INPUT_MISSING_PACMAN_DEPENDENCIES
fi

if [ -n "$INPUT_CUSTOM_PKGBUILD_DIRECTORIES" ]
then
    build_aur_packages "$INPUT_MISSING_AUR_DEPENDENCIES" "AUR Packages to fix missing dependencies"

    for pkgbuild_directory in $INPUT_CUSTOM_PKGBUILD_DIRECTORIES; do
        echo "Building custom PKGBUILD directory: $pkgbuild_directory"
        if ! build_custom_pkgbuild_directory "$pkgbuild_directory"; then
            echo "Error: Failed to build custom PKGBUILD directory $pkgbuild_directory. Skipping..."
        fi
    done

    aur_packages_after_custom="$(filter_custom_packages_from_aur_requests "$INPUT_PACKAGES")"
    build_aur_packages "$aur_packages_after_custom" "AUR Packages requested to install"
else
    build_aur_packages "$INPUT_PACKAGES $INPUT_MISSING_AUR_DEPENDENCIES" "AUR Packages to install"
fi

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
