FROM archlinux:latest

# install build dependencies
# Note: update (-u) so that the newly installed tools use up-to-date packages.
#       For example, gcc (in base-devel) fails if it uses an old glibc (from
#       base image).
RUN pacman -Syu --noconfirm base-devel

# TEMPORARY FIX
# The glibc installed by arch linux is too new for Github Actions, see
# https://stackoverflow.com/a/66184907/2165903
ENV PATCHED_GLIBC=glibc-linux4-2.33-4-x86_64.pkg.tar.zst
RUN curl -LO https://repo.archlinuxcn.org/x86_64/$PATCHED_GLIBC && \
    bsdtar -C / -xvf $PATCHED_GLIBC

# patch makepkg to allow running as root; see
# https://www.reddit.com/r/archlinux/comments/6qu4jt/how_to_run_makepkg_in_docker_container_yes_as_root/
RUN sed -i 's,exit $E_ROOT,echo but you know what you do,' /usr/bin/makepkg

# fix makepkg issues in github actions
# https://stackoverflow.com/q/66088277
RUN sed -i 's/\tif \[\[ -r $MAKEPKG_CONF \]\]; then/\tif \[\[ -f $MAKEPKG_CONF \]\]; then/' /usr/share/makepkg/util/config.sh

# make sure that the aur tools work under root as well
ENV AUR_ASROOT=1

# install aurutils and register it as local package repository
RUN \
    gpg --recv-keys --keyserver "hkp://ipv4.pool.sks-keyservers.net" 6BC26A17B9B7018A && \
    cd /tmp/ && \
    curl --output aurutils.tar.gz https://aur.archlinux.org/cgit/aur.git/snapshot/aurutils.tar.gz && \
    tar xf aurutils.tar.gz && \
    cd aurutils && \
    makepkg --syncdeps --noconfirm && \
    pacman -U --noconfirm aurutils-*.pkg.tar.zst && \
    mkdir /workspace && \
    cp /tmp/aurutils/aurutils-*.pkg.tar.zst /workspace/ && \
    repo-add /workspace/aurci2.db.tar.gz /workspace/aurutils-*.pkg.tar.zst && \
    echo "# local repository (required by aur tools to be set up)" >> /etc/pacman.conf && \
    echo "[aurci2]" >> /etc/pacman.conf && \
    echo "SigLevel = Optional TrustAll" >> /etc/pacman.conf && \
    echo "Server = file:///workspace" >> /etc/pacman.conf

COPY update_repository.sh /

CMD ["/update_repository.sh"]
