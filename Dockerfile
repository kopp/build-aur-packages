FROM archlinux:latest

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
RUN \
    pacman -S --noconfirm sudo && \
    groupadd builder && \
    useradd -m -g builder builder && \
    echo 'builder ALL = NOPASSWD: /usr/bin/pacman' > /etc/sudoers.d/builder_pacman


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
    mkdir /home/builder/workspace && \
    cp /tmp/aurutils/aurutils-*.pkg.tar.zst /home/builder/workspace/ && \
    repo-add /home/builder/workspace/aurci2.db.tar.gz /home/builder/workspace/aurutils-*.pkg.tar.zst

USER root
# Note: Github actions require the dockerfile to be run as root, so do not
#       switch back to the unprivileged user.
#       Use `sudo -u <user> <command>` to run a command as this user.

# Register the local repository with pacman.
RUN \
    echo "# local repository (required by aur tools to be set up)" >> /etc/pacman.conf && \
    echo "[aurci2]" >> /etc/pacman.conf && \
    echo "SigLevel = Optional TrustAll" >> /etc/pacman.conf && \
    echo "Server = file:///home/builder/workspace" >> /etc/pacman.conf

CMD ["/update_repository.sh"]
