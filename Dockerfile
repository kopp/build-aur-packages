FROM archlinux:base-devel

COPY update_repository.sh /

# Create a local user for building since aur tools should be run as normal user.
# Also update all packages (-u), so that the newly installed tools use up-to-date packages.
#       For example, gcc (in base-devel) fails if it uses an old glibc (from
#       base image).
RUN \
    pacman-key --init && \
    pacman -Syu --noconfirm --needed sudo && \
    groupadd builder && \
    useradd -m -g builder builder && \
    echo 'builder ALL = NOPASSWD: /usr/bin/pacman' > /etc/sudoers.d/builder_pacman


USER builder

# Build aurutils as unprivileged user.
RUN \
    cd /tmp/ && \
    curl --output aurutils.tar.gz https://aur.archlinux.org/cgit/aur.git/snapshot/aurutils.tar.gz && \
    tar xf aurutils.tar.gz && \
    cd aurutils && \
    makepkg --syncdeps --noconfirm && \
    sudo pacman -U --noconfirm aurutils-*.pkg.tar.zst && \
    mkdir /home/builder/workspace

USER root
# Note: Github actions require the dockerfile to be run as root, so do not
#       switch back to the unprivileged user.
#       Use `sudo -u <user> <command>` to run a command as this user.

CMD ["/update_repository.sh"]
