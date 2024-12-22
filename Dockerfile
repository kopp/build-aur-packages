FROM archlinux:latest

# Disable the sandbox for downloading
# This was added in pacman 7 but requires the kernel feature 'landlock' to be
# available, which is not available on current runners on github.
RUN sed -i 's,#DisableSandbox,DisableSandbox,' /etc/pacman.conf

# Install build dependencies.
# Note: update (-u) so that the newly installed tools use up-to-date packages.
#       For example, gcc (in base-devel) fails if it uses an old glibc (from
#       base image).
RUN pacman -Syu --noconfirm base-devel

# Patch makepkg to allow running as root; see
# https://www.reddit.com/r/archlinux/comments/6qu4jt/how_to_run_makepkg_in_docker_container_yes_as_root/
RUN sed -i 's,exit $E_ROOT,echo but you know what you do,' /usr/bin/makepkg

# Add the gpg key for 6BC26A17B9B7018A.
# This should not be necessary.  It should be possible to use
#     gpg --recv-keys --keyserver pgp.mit.edu 6BC26A17B9B7018A
# but this fails randomly in github actions, so import the key from file.
COPY gpg_key_6BC26A17B9B7018A.gpg.asc /tmp/

COPY update_repository.sh /


# Create a local user for building since aur tools should be run as normal user.
# This user is in the `alpm` group, to ensure, that the files it generates are accessible
# - to the user building the packages (the builder user)
# - to the user that pacman uses to download artifacts
# See also https://archlinux.org/news/manual-intervention-for-pacman-700-and-local-repositories-required/
RUN \
    pacman -S --noconfirm sudo && \
    useradd -m -g alpm builder && \
    echo 'builder ALL = NOPASSWD: ALL' > /etc/sudoers.d/builder_pacman

# Create a folder for the local repository.
# This also needs to be accessible to `builder` and `alpm`.
RUN \
    mkdir /local_repository && \
    chown builder:alpm /local_repository

USER builder

# Build aurutils as unprivileged user.
RUN \
    gpg --import /tmp/gpg_key_6BC26A17B9B7018A.gpg.asc && \
    cd /tmp/ && \
    curl --output aurutils.tar.gz https://aur.archlinux.org/cgit/aur.git/snapshot/aurutils.tar.gz && \
    tar xf aurutils.tar.gz && \
    cd aurutils && \
    makepkg --syncdeps --noconfirm && \
    sudo pacman -U --noconfirm aurutils-*.pkg.tar.zst && \
    cp /tmp/aurutils/aurutils-*.pkg.tar.zst /local_repository/ && \
    repo-add /local_repository/aurci2.db.tar.gz /local_repository/aurutils-*.pkg.tar.zst


USER root
# Note: Github actions require the dockerfile to be run as root, so do not
#       switch back to the unprivileged user.
#       Use `sudo --user <user> <command>` to run a command as this user.

# Register the local repository with pacman.
RUN \
    echo "# local repository (required by aur tools to be set up)" >> /etc/pacman.conf && \
    echo "[aurci2]" >> /etc/pacman.conf && \
    echo "SigLevel = Optional TrustAll" >> /etc/pacman.conf && \
    echo "Server = file:///local_repository" >> /etc/pacman.conf

CMD ["/update_repository.sh"]
