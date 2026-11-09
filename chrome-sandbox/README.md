# chrome-sandbox

Disposable Google Chrome (stable) running in Docker, displayed as a normal window on the local
X11 desktop. Every launch starts with a fresh profile; nothing persists except downloads.

## Usage

```sh
./run.sh                      # build on first run (~1 GB), then open Chrome
./run.sh https://example.com  # open a URL
./run.sh --start-maximized    # any Chrome flag works
```

Downloads land in `~/Downloads/chrome-sandbox/` (override with `CHROME_DOWNLOADS=/path`).

## What persists

| Thing                    | Persists? |
|--------------------------|-----------|
| History, cookies, logins | no (profile is on tmpfs, container is `--rm`) |
| Extensions, settings     | no |
| Downloads                | yes, in the mounted folder |
| The image itself         | yes, until `docker rmi chrome-sandbox` |

## Options

- `CHROME_NO_SANDBOX=1 ./run.sh` runs with `--no-sandbox` and without `SYS_ADMIN`.
- `CHROME_GPU=1 ./run.sh` passes `/dev/dri` for hardware acceleration.
- `CHROME_DNS="100.100.100.100" ./run.sh` sets the container's DNS servers (space-separated).
- `CHROME_CA_DIR=/path ./run.sh` sets the folder of extra CA certs to trust (default below).

## Corporate network (VPN DNS, internal CAs)

Two things differ from Chrome on the host:

- **DNS.** Docker copies the host's upstream resolvers but not systemd-resolved split DNS, so
  names served by a VPN resolver can resolve to public IPs in the container. A host such as
  `chat.corp.example` may then hit its public endpoint, which can use a different certificate
  chain. Pass the VPN resolver (see `resolvectl status`) with `CHROME_DNS`.
- **Certificates.** `run.sh` mounts the host's `/usr/local/share/ca-certificates` read-only
  (override with `CHROME_CA_DIR`), and `entrypoint.sh` imports every `*.crt` into Chrome's NSS
  db (`~/.pki/nssdb`) with `certutil` before Chrome starts.

```sh
CHROME_DEBUG=1 CHROME_DNS=100.100.100.100 ./run.sh https://chat.corp.example/
```

If a site still shows `ERR_CERT_AUTHORITY_INVALID`, compare `getent hosts <name>` inside the
container (`docker exec chrome-sandbox-<pid> ...`) with the host's answer before checking certs.

## Remote debugging / driving it from Claude Code

```sh
CHROME_DEBUG=1 ./run.sh https://site.example   # DevTools on http://127.0.0.1:9222
```

While the port is open any local process can control the browser, so enable it only while
diagnosing. The project `.mcp.json` registers `chrome-devtools-mcp` pointed at that port: start
the sandbox, run `/mcp` in Claude Code to connect `chrome-devtools`, then ask Claude to open a URL,
take screenshots, read console/network errors or record a trace. You see the same page in the
sandbox window.

Without the MCP server, Claude can still drive the page over raw CDP the way `cookies.mjs`
does: find the page in `http://127.0.0.1:9222/json` and send `Runtime.evaluate` to its
`webSocketDebuggerUrl`. Code run this way uses the page's logged-in session, so it can call the
site's own API with `fetch()`.

## Reusing cookies across sessions

The profile is discarded on exit. To carry specific cookies (a login, a site's "accepted
visitor" cookie) into a new session, save them from a running debug session and inject them at
the next start:

```sh
node cookies.mjs save cookies/example.com.json example.com   # from a CHROME_DEBUG=1 session
CHROME_DEBUG=1 CHROME_COOKIES=cookies/example.com.json ./run.sh https://example.com
```

`cookies/` holds plain-text cookie values; treat it like a password file. Expired entries are
skipped on load, and open pages are reloaded so the cookies apply right away.

## Maintenance

```sh
docker rmi chrome-sandbox            # remove the image
docker build --pull --build-arg UID="$(id -u)" --build-arg GID="$(id -g)" \
  -t chrome-sandbox .                 # rebuild to pick up a newer Chrome or Dockerfile changes
```
