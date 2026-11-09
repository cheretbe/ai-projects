#!/bin/sh
set -e
# Trust extra CAs mounted by run.sh (e.g. corporate roots); Chrome on Linux reads them from NSS.
if ls /usr/local/share/ca-certificates/*.crt >/dev/null 2>&1; then
  mkdir -p "$HOME/.pki/nssdb"
  [ -f "$HOME/.pki/nssdb/cert9.db" ] || certutil -N -d sql:"$HOME/.pki/nssdb" --empty-password
  for crt in /usr/local/share/ca-certificates/*.crt; do
    certutil -A -d sql:"$HOME/.pki/nssdb" -t "C,," -n "$(basename "$crt" .crt)" -i "$crt"
  done
fi
set -- --user-data-dir=/tmp/profile --no-first-run --no-default-browser-check --password-store=basic "$@"
if [ -n "${CHROME_DEBUG_PORT:-}" ]; then
  # Chrome only listens on the container loopback; socat exposes it on all
  # interfaces (port 9223) so run.sh can publish it to the host loopback.
  socat TCP-LISTEN:9223,reuseaddr,fork TCP:127.0.0.1:"$CHROME_DEBUG_PORT" &
  set -- --remote-debugging-port="$CHROME_DEBUG_PORT" "$@"
fi
exec google-chrome-stable "$@"
