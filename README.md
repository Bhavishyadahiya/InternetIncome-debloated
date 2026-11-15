# InternetIncome — Debloated

A smaller, headless-focused fork of InternetIncome for running bandwidth-sharing clients in Docker, with direct connections or multiple proxies. It does not manage VPN connections.

**Keep the useful clients. Drop browser automation and profile archives. Make configuration and maintenance easier to understand.**

## Why use this fork?

Compared with the original browser-heavy setup, this fork offers:

- **Less browser overhead:** no automated Chrome/Firefox sessions for Grass, Gradient, Adnade, or Ebesucher.
- **Fewer moving parts:** no bundled browser profile ZIPs, profile extraction, VNC credentials, or browser-reset helpers.
- **A leaner download:** the large Chrome and Firefox profile archives are excluded.
- **No banner animation delay:** the banner prints once instead of clearing the terminal and replaying an animation.
- **Configurable proxy engines:** keep automatic selection or choose tun2socks, tun2proxy, or the lightweight TCP-only redsocks option.
- **Native IdlePay proxy sharing:** one persistent IdlePay device handles a whole proxy list instead of creating a separate IdlePay device for every proxy.
- **Safer replacement prompts:** existing direct-connection containers using the same image are listed before deletion and require confirmation.
- **Opt-in image updates:** scoped Watchtower updates are disabled by default and target only eligible app containers from the current run.
- **Regression tests:** launcher behavior is covered by isolated tests without enrolling accounts or running real sharing services.

“Better” here means less browser baggage and clearer operation—not guaranteed higher earnings or a measured performance gain. Resource use still depends on the apps, proxy count, and traffic. Some remaining helpers require access to the Docker socket; this is not a hardened container sandbox.

## Supported projects

The script contains integrations for **17 projects**. “Supported” means a launch path exists; it does not guarantee that a provider still accepts Docker, your account, or your IP type.

Enable only the projects you want in [`properties.conf`](properties.conf).

| Project | Configuration to enable it | Notes |
| --- | --- | --- |
| AntGain | `ANTGAIN_API_KEY` | Saves its device ID in `antgain.txt`. |
| BitPing | `BITPING_EMAIL`, `BITPING_PASSWORD` | Disable account MFA before using this client. |
| EarnFM | `EARN_FM_API` | Standard client; optional Fleetshare mode below. |
| IdlePay | `IDLEPAY_KEY` | Enrollment key; saved identity allows later starts without it. |
| PacketShare | `PACKETSHARE_EMAIL`, `PACKETSHARE_PASSWORD` | Add these settings to the config; the template does not currently include them. |
| PacketStream | `PACKETSTREAM_CID` | Uses your account's CID. |
| Pawns / IPRoyal | `IPROYALS_EMAIL`, `IPROYALS_PASSWORD` | Uses the Pawns CLI and `on-failure:5` restart policy. |
| Peer2Profit | `PEER2PROFIT_EMAIL` | Legacy integration; official Docker support was withdrawn. |
| ProxyBase | `PROXYBASE_ACCOUNT_ID` | Account ID is passed to the peer CLI. |
| ProxyLite | `PROXYLITE_USER_ID` | Includes a daily restart helper. |
| ProxyRack | `PROXYRACK_API` | Saves its device ID in `proxyrack.txt`. |
| Repocket | `REPOCKET_API` | API key only; email is no longer required. |
| Titan Network | `TITAN_HASH` | This launcher starts only one Titan device per directory. |
| Traffmonetizer | `TRAFFMONETIZER_TOKEN` | Selects an image for the host architecture. |
| URnetwork | `UR_AUTH_TOKEN` | Keep a nonempty token setting; saved authentication is reused after enrollment. |
| Wipter | `WIPTER_EMAIL`, `WIPTER_PASSWORD` | Uses a third-party Docker wrapper. |
| WizardGain | `WIZARD_GAIN_EMAIL` | Email-based worker configuration. |

### Aggregate proxy modes

- **EarnFM Fleetshare:** set `USE_EARN_FM_FLEETSHARE=true` alongside `EARN_FM_API`. Uses SOCKS5 proxies from `proxies.txt` in one Fleetshare container instead of the standard client.
- **URnetwork:** set `UR_NETWORK_PROXY_MODE=true` alongside `UR_AUTH_TOKEN` to aggregate SOCKS5 proxies in one provider container. For initial enrollment, run the script promptly after copying the short-lived auth token.
- **IdlePay:** automatically uses one native proxy-list container when `USE_PROXIES=true`.

## Removed projects and components

These integrations have been removed from this fork and are no longer launched:

| Removed project | What was removed | Why |
| --- | --- | --- |
| Grass | Browser-extension launch path | Avoid the shared browser-extension container and its overhead. |
| Gradient | Browser-extension launch path | Removed with the shared DePIN extension container. |
| Adnade | Automated Firefox sessions and reset helper | Avoid browser-based surfing, profile maintenance, and extra access ports. |
| Ebesucher | Automated Chrome/Firefox sessions and reset helpers | Avoid browser-based surfing, VNC access, and profile maintenance. |
| Honeygain | Docker client and credential settings | due to its limit of 10nodes per account its recommended to use seperate HGincome script |
| EarnApp | Docker client, enrollment URLs, and identity/data tracking | EA requires highly specific ips and most ips are not eligible so it would create junk containers thats why removed |
| Mysterium | Node client, dashboard ports, and identity/data tracking | Outside this fork's proxy-focused scope; VPN connection management is not supported. |

Also excluded: `chromeprofiledata.zip`, `firefoxprofiledata.zip`, their extracted profiles, and the associated browser tracking/configuration code.

Removing an integration does not stop old containers or delete previously saved data. Honeygain, EarnApp, and Mysterium are no longer started by the script; their legacy files are no longer included in its cleanup lists.

Other projects advertised in the parent README are not listed as supported unless this script actually implements them.

## Quick start

### 1. Requirements

- Linux with Bash and a working Docker Engine. On Windows, use a Linux environment such as WSL2 with Docker access.
- `sudo` and common Linux command-line tools. AntGain uses `uuidgen`.
- `/dev/net/tun` and Docker `NET_ADMIN` capability for the full tunnel engines. Redsocks does not use the TUN device but still needs network administration privileges.
- Your own app accounts and networks/proxies whose owners permit bandwidth sharing.

Install Docker using the [official installation instructions](https://docs.docker.com/engine/install/) for your distribution. The script's `--install` helper uses `apt-get`; it is not an Arch Linux installer. Some app images are amd64-only, so ARM hosts may need emulation even when the tunnel image supports ARM.

### 2. Get this fork

```sh
git clone https://github.com/Bhavishyadahiya/InternetIncome-debloated.git
cd InternetIncome-debloated
```

Run all commands from the directory containing `internetIncome.sh`, `properties.conf`, `restart.sh`, and `banner.jpg`. File and data paths are relative to your working directory.

### 3. Configure your apps

Edit `properties.conf`:

```sh
DEVICE_NAME='my-server'
REPOCKET_API='your_repocket_api_key'
IDLEPAY_KEY='ipk_your_enrollment_key'
USE_PROXIES=false
```

These are placeholders, not working credentials. Leave unused credentials blank and unused switches `false`. Use single quotes around values containing special characters. The config is interpreted by the shell: use a trusted file, not configuration copied from an untrusted source.

**Never commit account credentials, enrollment keys, proxy passwords, or saved device data.** App authentication may remain in persistent data directories even after you clear a setting.

### 4. Optional: add proxies

Set `USE_PROXIES=true` and put one proxy per line in `proxies.txt`:

```text
# SOCKS5 with authentication
socks5://username:password@proxy.example:1080

# HTTP with authentication
http://username:password@proxy.example:8080
```

Blank lines and lines starting with `#` are ignored. Use the URL format above, not `host:port:username:password`. Whether an IP earns or is accepted depends on each provider's rules; more containers on the same public IP do not necessarily help.

### 5. Start

```sh
sudo bash internetIncome.sh --start
```

The script records container names in `containernames.txt`. Complete any provider-specific enrollment or dashboard linking shown in the output.

## IdlePay setup

1. Verify your email and create an enrollment key in the [IdlePay Devices dashboard](https://app.idlepay.io/devices).
2. Set `IDLEPAY_KEY='ipk_your_enrollment_key'` and start the script.
3. Check enrollment and connection status:

   ```sh
   sudo docker exec <idlepay-container-name> idlepay status --all
   ```

The official image is `ghcr.io/idlepay/idlepay:latest`, with native amd64, arm64, and arm/v7 support. Its device identity is stored in `idlepay-data/data`, mounted at `/etc/idlepay`. Never share or copy this directory between running devices.

- **Direct mode:** `USE_PROXIES=false` enables direct sharing.
- **Proxy mode:** `USE_PROXIES=true` mounts the complete proxy list and sets `IDLEPAY_DIRECT=off`, disabling sharing of the host's own connection.
- **Accepted proxies:** static HTTP, HTTPS, and SOCKS5. SOCKS4 and Shadowsocks are not supported by this integration.
- **Proxy-list changes:** the mounted file replaces saved proxies on every container start. Edit the file and restart the container; do not mix this with `idlepay proxy add`.
- **After enrollment:** you can revoke the key and clear `IDLEPAY_KEY`; the saved identity enables subsequent starts.
- **Updates:** IdlePay updates its client internally, independently of Watchtower image updates.

Per [IdlePay's sharing documentation](https://idlepay.io/docs/sharing#proxy-formats), authenticated HTTP/SOCKS5 proxy addresses and credentials are sent to IdlePay so its servers can connect directly. Use only proxies whose owners authorize this.

**IdlePay-only startup:** when proxies are enabled and IdlePay is the only enabled app, the launcher starts its native proxy-list container once and skips all tunnel containers. This also works with saved enrollment and optional Watchtower. An empty proxy list is rejected. If any other app is enabled, the existing per-proxy tunnel behavior is retained; EarnFM Fleetshare and URnetwork's aggregate proxy mode do not change this rule.

## Networking and maintenance

### Tunnel selection

`TUNNEL_METHOD` applies when proxies are enabled:

| Value | Behavior |
| --- | --- |
| `auto` | HEV for SOCKS5 with `USE_SOCKS5_DNS=true`; tun2proxy for HTTP/HTTPS/SOCKS4/SOCKS5; tun2socks otherwise. |
| `tun2socks` | Force the full IP tunnel using `xjasonlyu/tun2socks:v2.7.0`. |
| `tun2proxy` | Force `ghcr.io/tun2proxy/tun2proxy:v0.8.7`. |
| `redsocks` | TCP-only redirector. **UDP and DNS go directly, not through the proxy.** |

HEV is pinned to `2.20.0`. `USE_DNS_OVER_HTTPS=true` selects tun2proxy's `--dns over-tcp` option; the setting name does not mean every tunnel engine provides HTTPS DNS. Neither Docker nor these settings guarantee anonymity or prevent every network leak.

### Optional controls

- `ENABLE_LOGS=true`: enable bounded container logs for troubleshooting. Logs are disabled by default.
- `AUTO_UPDATE_CONTAINERS=true`: start one scoped Watchtower helper that checks every 24 hours. Only this run's app images tagged `latest`, `arm64v8`, or `arm32v7` are eligible. Pinned tunnels and other helper containers are excluded. Default: `false`.

### Stop and remove containers

```sh
sudo bash internetIncome.sh --delete
```

This removes tracked containers and generated runtime files. Saved identities/authentication for IdlePay, AntGain, ProxyRack, Titan, BitPing, URnetwork, and Traffmonetizer are retained for reuse.

Additional cleanup can list containers outside this project whose parent network container no longer exists; deleting those requires confirmation. Startup also asks before deleting existing direct-connection containers of the same image.

To reset retained identities after stopping the containers:

```sh
sudo bash internetIncome.sh --deleteBackup
```

**This deletes saved authentication and device data.** Providers may require re-enrollment. Do not use it as a routine restart command.

## Validation

```sh
python -I tests/test_internet_income.py -v
```

The 40 tests require Python and Bash and mock Docker, sudo, and delays. They cover startup, cleanup, app activation, tunnel choices, deletion prompts, update scoping, and IdlePay identity/proxy behavior. They are not live connectivity or earnings tests.

## Attribution and license

Based on [engageub/InternetIncome](https://github.com/engageub/InternetIncome). Relevant upstream script changes were synchronized on November 14, 2026, against commit `d514430737d184ef7c3043e5b516d038f71f3989`, while preserving this fork's exclusions and custom tunnel selection.

See [LICENSE](LICENSE) for the license included in this repository. Third-party clients and services have their own terms. This software is provided as-is, with no guarantee of earnings, provider acceptance, or suitability for your network.
