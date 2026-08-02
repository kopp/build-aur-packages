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
FAILED_BUILDS=()
SUCCESSFUL_BUILDS=()
ATTEMPTED_AUR_PACKAGES=()

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

array_contains() {
    local wanted="$1"
    shift

    local item
    for item in "$@"; do
        if [ "$item" = "$wanted" ]
        then
            return 0
        fi
    done

    return 1
}

record_failure() {
    local build="$1"

    if ! array_contains "$build" "${FAILED_BUILDS[@]}"
    then
        FAILED_BUILDS+=("$build")
    fi
}

record_success() {
    local build="$1"

    if ! array_contains "$build" "${SUCCESSFUL_BUILDS[@]}"
    then
        SUCCESSFUL_BUILDS+=("$build")
    fi
}

print_json_array() {
    local separator=""
    local value

    printf '['
    for value in "$@"; do
        value="${value//\\/\\\\}"
        value="${value//\"/\\\"}"
        value="${value//$'\n'/\\n}"
        value="${value//$'\r'/\\r}"
        value="${value//$'\t'/\\t}"
        printf '%s"%s"' "$separator" "$value"
        separator=','
    done
    printf ']'
}

set_action_outputs() {
    local repository_ready="false"

    if [ "${#SUCCESSFUL_BUILDS[@]}" -gt 0 ]
    then
        repository_ready="true"
    fi

    if [ -n "${GITHUB_OUTPUT:-}" ]
    then
        printf 'failed_builds=' >> "$GITHUB_OUTPUT"
        print_json_array "${FAILED_BUILDS[@]}" >> "$GITHUB_OUTPUT"
        printf '\nrepository_ready=%s\n' "$repository_ready" >> "$GITHUB_OUTPUT"
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

    echo "$description: $requested_packages"

    # Resolve each requested package separately. A broken AUR entry must not
    # prevent unrelated package roots from being resolved and built.
    local packages_with_dependencies=()
    local requested_package
    local resolved_packages
    local resolved_package
    for requested_package in $requested_packages; do
        if ! resolved_packages="$(aur depends --pkgname "$requested_package")"; then
            echo "Error: Failed to resolve dependencies for package $requested_package. Skipping..."
            record_failure "aur-resolution:$requested_package"
            continue
        fi

        for resolved_package in $resolved_packages; do
            if ! array_contains "$resolved_package" "${packages_with_dependencies[@]}"
            then
                packages_with_dependencies+=("$resolved_package")
            fi
        done
    done

    echo "$description (including dependencies): ${packages_with_dependencies[*]}"

    # Add the packages to the local repository one by one.
    # We iterate through the list to ensure that if one package fails,
    # we can continue with the others.
    local pkg
    for pkg in "${packages_with_dependencies[@]}"; do
        if array_contains "$pkg" "${ATTEMPTED_AUR_PACKAGES[@]}"
        then
            echo "Skipping package already attempted in this run: $pkg"
            continue
        fi
        ATTEMPTED_AUR_PACKAGES+=("$pkg")

        echo "Building package: $pkg"
        if ! sudo --user builder \
            aur sync \
            --noconfirm --noview \
            --clean \
            --database aurci2 --root /local_repository \
            "$pkg"; then
            echo "Error: Failed to build package $pkg. Skipping..."
            record_failure "aur:$pkg"
        else
            record_success "aur:$pkg"
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
            record_failure "custom:$pkgbuild_directory"
        else
            record_success "custom:$pkgbuild_directory"
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

set_action_outputs

if [ "${#FAILED_BUILDS[@]}" -gt 0 ]
then
    echo "Build completed with ${#FAILED_BUILDS[@]} failure(s):"
    printf ' - %s\n' "${FAILED_BUILDS[@]}"
    echo "::error title=Partial AUR repository build::One or more packages failed: ${FAILED_BUILDS[*]}"
    exit 1
fi
