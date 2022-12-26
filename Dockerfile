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
    mkdir /home/builder/workspace && \
    repo-add /home/builder/workspace/aurci2.db.tar.gz

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
