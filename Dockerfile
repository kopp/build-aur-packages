FROM archlinux:latest

# patch makepkg to allow running as root; see
# https://www.reddit.com/r/archlinux/comments/6qu4jt/how_to_run_makepkg_in_docker_container_yes_as_root/
RUN sed -i 's,exit $E_ROOT,echo but you know what you do,' /usr/bin/makepkg

# install build dependencies
RUN pacman -Sy --noconfirm base-devel

# install aurutils and register it as local package repository
RUN gpg --recv-keys --keyserver "hkp://ipv4.pool.sks-keyservers.net" 6BC26A17B9B7018A
RUN cd /tmp/
RUN curl --output aurutils.tar.gz https://aur.archlinux.org/cgit/aur.git/snapshot/aurutils.tar.gz
RUN tar xf aurutils.tar.gz
RUN cd aurutils
RUN makepkg --syncdeps --noconfirm
RUN pacman -U --noconfirm aurutils-2.3.3-1-any.pkg.tar.xz
RUN mkdir /workspace
RUN repo-add /workspace/aurci2.db.tar.gz /tmp/u/aurutils/aurutils-*.pkg.tar.xz
RUN echo "# local repository (required by aur tools to be set up)" >> /etc/pacman.conf
RUN echo "[aurci2]" >> /etc/pacman.conf
RUN echo "SigLevel = Optional TrustAll" >> /etc/pacman.conf
RUN echo "Server = file:///workspace" >> /etc/pacman.conf

COPY update_repository.sh /

CMD ["/update_repository.sh"]
