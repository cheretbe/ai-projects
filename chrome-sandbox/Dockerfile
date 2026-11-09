# Disposable Google Chrome for X11 passthrough. Profile lives in /tmp (tmpfs at runtime).
FROM debian:bookworm-slim

ARG UID=1000
ARG GID=1000
ARG CHROME_DEB=https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates wget locales xdg-utils libx11-xcb1 libgl1 libegl1 libgl1-mesa-dri socat \
      fonts-liberation fonts-dejavu fonts-noto-core fonts-noto-cjk fonts-noto-color-emoji \
 && sed -i 's/^# *\(en_US.UTF-8\|ru_RU.UTF-8\)/\1/' /etc/locale.gen \
 && locale-gen \
 && wget -qO /tmp/chrome.deb "$CHROME_DEB" \
 && apt-get install -y --no-install-recommends /tmp/chrome.deb \
 && rm /tmp/chrome.deb \
 && rm -rf /var/lib/apt/lists/*

# certutil, to import extra CAs (mounted at /usr/local/share/ca-certificates) into Chrome's NSS db.
RUN apt-get update \
 && apt-get install -y --no-install-recommends libnss3-tools \
 && rm -rf /var/lib/apt/lists/*

RUN groupadd -g "$GID" chrome \
 && useradd -m -u "$UID" -g "$GID" -s /bin/bash chrome \
 && mkdir -p /home/chrome/Downloads \
 && chown -R chrome:chrome /home/chrome

COPY --chmod=755 entrypoint.sh /usr/local/bin/entrypoint.sh

USER chrome
WORKDIR /home/chrome

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
