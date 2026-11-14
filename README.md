# 💻 Internet Income 💸 Multi-Proxy . Multi-IP . Multi-VPN 🏰

## Debloated fork

This fork preserves its existing applications and custom `TUNNEL_METHOD` selection. Grass, Gradient, Adnade, Ebesucher, and the browser profile archives remain excluded.

Upstream script updates synchronized on 2026-11-14 against [`engageub/InternetIncome` at `d514430`](https://github.com/engageub/InternetIncome/commit/d514430737d184ef7c3043e5b516d038f71f3989):

* HEV SOCKS5 tunnel updated to `2.20.0` and tun2proxy to `v0.8.7`; tun2socks stays at `v2.7.0`.
* Repocket now requires only `REPOCKET_API`, not an email address.
* Existing direct-connection containers using the same image are listed before deletion and require confirmation; refusing or timing out leaves them untouched.
* `AUTO_UPDATE_CONTAINERS=false` by default. Enabling it starts one scoped Watchtower helper, checking every 24 hours and updating only this run's application containers tagged `latest`, `arm64v8`, or `arm32v7`. Pinned tunnels, helper containers, and EarnApp's `lite` image are excluded.
* Pawns uses `on-failure:5`; existing restart policies for other apps follow upstream.
* Quad9 was removed from the generated DNS resolver list, following upstream.
* `CLOSE_ALL_PORTS=true` disables Mysterium dashboard port publishing and URL output. The default is `false`.

Use your own accounts and only networks/proxies you are authorized to share. App comparison rows below are informational, not a guarantee that every listed app has a container integration.

### IdlePay

The integration uses the [official IdlePay Docker client](https://idlepay.io/docs/docker), `ghcr.io/idlepay/idlepay:latest`, with native amd64, arm64, and arm/v7 support.

1. Verify your email and create an enrollment key in the [Devices dashboard](https://app.idlepay.io/devices).
2. Set `IDLEPAY_KEY='ipk_...'` in `properties.conf` and start the script.
3. The device identity is saved in `idlepay-data/data`, mounted at `/etc/idlepay`. Ordinary `--delete` preserves it; `--deleteBackup` removes it. Never share this directory between running devices.
4. After enrollment, you can revoke the key and clear `IDLEPAY_KEY`; saved `config.json` enables subsequent starts.

With `USE_PROXIES=false`, IdlePay uses direct internet access. With `USE_PROXIES=true`, a **single** IdlePay container reads `proxies.txt` using its native proxy support and disables direct sharing (`IDLEPAY_DIRECT=off`). It does not need a tunnel or dashboard port. **Current launcher limitation:** `--start` still creates a generic tunnel for each proxy before starting IdlePay, even when no tunnel-based apps are enabled; those tunnels add startup time and must succeed. The mounted proxy file replaces IdlePay's saved proxy list on every start, so edit that file rather than using `idlepay proxy add`. Only one connection per public IP earns. IdlePay accepts static HTTP/HTTPS/SOCKS5 proxies, not SOCKS4 or Shadowsocks; unsupported types stop startup with a clear error rather than silently sharing the host IP. Per its [official sharing documentation](https://idlepay.io/docs/sharing#proxy-formats), authenticated HTTP/SOCKS5 proxy addresses and credentials are sent to IdlePay so its servers can connect directly. Use only proxies whose owners permit this. IdlePay also updates its client internally, independently of optional Watchtower image updates.

### Trees.app

[Trees.app](https://www.trees.app/) is included as a **manual-setup app**, not an automated container integration. Its official download page currently offers Windows, macOS, and Android; no supported Linux/Docker/headless client was verified as of 2026-11-14. Install the official client on a supported device and sign in there. There is intentionally no invented `TREES_*` credential setting or third-party image in this script.

### Local validation

From this fork's script directory, run:

```sh
python -I tests/test_internet_income.py -v
```

These tests require Bash and mock Docker, sudo, and delays. They check launcher behavior without starting services or sending credentials to app providers; they are not live service-connectivity tests.

<img src="https://i.ibb.co/DKbwPN1/imgonline-com-ua-twotoone-2ck-Xl1-JPvw2t-D1.jpg" width="100%" height="300"/>

This script lets you earn income by sharing your internet bandwidth. The income is passive and you don't have to do anything after the setup but keep getting payouts to your account.
The main advantage of this script is the use of multiple proxies through docker containers. 
Running the applications inside Docker is recommended, as it provides an isolated environment that keeps your host system clean, avoids dependency conflicts, and prevents interference with system configurations or future updates.
Your income depends on the number of proxies used and the proxy location. If you use all the apps mentioned, you can earn about $50 per month or more from 1 IP depending on the location of the proxy and demand.
Please read the respective apps' legal terms or FAQ section if you have any queries on the type of traffic sent. 
For advanced users, it is recommended to use the [test](https://github.com/engageub/InternetIncome/tree/test) branch.

To maximize earnings, use the [test](https://github.com/engageub/InternetIncome/tree/test) with `USE_DNS_OVER_HTTPS` enabled when working with proxies. This configuration also enables DNS caching by default, reducing DNS queries and lowering latency. For direct connections, use the `main` branch, and for proxy-based connections, use the `test` branch.


[🚀 Got 100+ SOCKS5 Proxies? Turn Them Into Passive Income! 💰 Click Here](https://github.com/engageub/InternetIncome/wiki/%F0%9F%92%B8-Earn-More-with-Your-SOCKS5-Proxies)

**Note**: Collecting and reading publicly available data from the internet is usually protected by free speech rights under the First Amendment of the US Constitution.

### <ins> [Click here to get Static Residential Proxies starting at $1](https://github.com/engageub/InternetIncome/wiki/Proxies-and-Hosting-Providers)</ins> 

File Internet Crime Complaints World Wide here: https://www.ic3.gov/

## 💰	Register with the following links:
### <ins>[Click here to Sign Up now](https://github.com/engageub/InternetIncome/wiki/Registration-Links)</ins> 
## :judge: Comparison of different apps based on proxy type 

| App Name | Residential/Home ISP | Datacenter/Hosting/VPS |Limit per Account|Devices per IP| Payment|
|  :--- |  :---: |  :---: | :---: | :---: | :---: |
| [IdlePay](https://idlepay.io/) | :heavy_check_mark: | :heavy_check_mark: | No limit | 1 | Crypto |
| [Trees.app](https://www.trees.app/) (manual setup; no verified Docker client) | :heavy_check_mark: | :x: | No limit | 1 | Paypal |
| [EarnApp](https://t.co/k0w7jqLfxq)  | :heavy_check_mark:	  | :x: | No limit|1| Paypal, Gift Card |
| [PacketStream](https://t.co/FtklOxS7QN)  | :heavy_check_mark:	  | :x: |No limit|1| Paypal |
| [Honeygain](https://t.co/Xo1FwoUJx1) | :heavy_check_mark:	  | :x: |10|1| Crypto, Paypal |
| [IPRoyal](https://t.co/7hZUclQbCd)  | :heavy_check_mark:	  | :x: |No limit|1|Crypto, Paypal|
| [Uprock](https://t.co/xwUf7kY9U0) | :heavy_check_mark:	  | :x: |No limit|1| Crypto |
| [PassiveApp](https://passiveapp.com/i/KWc0pl)  | :heavy_check_mark: | :x: |No limit|1| Crypto, Paypal|
| [Bytebenefit](https://bytebenefit.io/invited?ref=nD8Rtx) | :heavy_check_mark: | :x: |No limit|1| Paypal, Stripe|
| [Wipter](https://wipter.com/register?via=CE5979A505) | :heavy_check_mark:	  | :heavy_check_mark: |No limit|1| Crypto |
| [AntGain](https://t.co/0phceMTJhF)  | :heavy_check_mark:	  | :heavy_check_mark: | No limit|1| Crypto |
| [WizardGain](https://t.co/NBMM8abxi0) | :heavy_check_mark:	  | :heavy_check_mark: |No limit|1| Paypal, Crypto|
| [URnetwork](https://ur.io/c?bonus=YSC0T7) (Use refer code `YSC0T7` in settings for bonus) | :heavy_check_mark:	  | :heavy_check_mark: |No limit|1| Crypto |
| [Titan Network IP Lease](https://edge.titannet.info/signup?inviteCode=ESTWVWQ2) | :heavy_check_mark:	  | :heavy_check_mark: |No limit|1| Crypto/Rewards |
| [Titan Network TNT3](https://test1.titannet.io/intiveRegister?code=ILOgrq) | :heavy_check_mark:	  | :heavy_check_mark: |No limit|1| Rewards |
| [EarnFM](https://t.co/SX6ggtooDW)  | :heavy_check_mark:	  | :heavy_check_mark: |No limit|1| Crypto, Paypal, Giftcard|
| [Peer2Profit](https://t.me/peer2profit_app_bot?start=163956712261b9cf129932a)  | :heavy_check_mark:	  | :heavy_check_mark:	 | No limit|No limit| Crypto|
| [ProxyBase](https://peer.proxybase.org/dashboard/signup?referral=t5QAXPQ8Q8)  | :heavy_check_mark:	  | :heavy_check_mark: |No limit|1| Crypto|
| [ProxyRack](https://peer.proxyrack.com/ref/tqkgvytmszxtxafo30miq2dbeeauuopmmup0eklx)  | :heavy_check_mark:	  | :heavy_check_mark: |500|1| Paypal|
| [Repocket](https://link.repocket.co/pV1G)  | :heavy_check_mark:	  | :heavy_check_mark: |No limit|2| Paypal, Wise, Crypto|
| [Traffmonetizer](https://traffmonetizer.com/?aff=4211) | :heavy_check_mark:	  | :heavy_check_mark: |No limit|No limit| Crypto|
| [ProxyLite](https://proxylite.ru/?r=AXLDPNX5) | :heavy_check_mark:	  | :heavy_check_mark: |No limit|1| Crypto|
| [BitPing](https://app.bitping.com/?r=drPpp600) | :heavy_check_mark:	  | :heavy_check_mark: |No limit|1| Crypto|
| [Mysterium](https://mystnodes.co/?referral_code=xejcELAJ368e6PYnB30VHAnNKn30Aa6wKygVZdam) | :heavy_check_mark:	  | :heavy_check_mark: |No limit|1| Crypto|
| [Bytelixir](https://t.co/MNaVYiALR5) | :heavy_check_mark:	  | :heavy_check_mark: |No limit|1| Crypto |
| [Salad](https://salad.com/) | :heavy_check_mark:	  | :heavy_check_mark: |No limit|1| Paypal |

* [Click here](https://prnt.sc/siTVsNW9QDrL) to view the screenshot above as some browsers don't support checkmarks. 
* No Limit indicates that the website has not mentioned any specifics and multiple proxies were working. Try to use 1 device per IP.
* To convert crypto to other wallets or currencies, you may use [BestChange](https://www.bestchange.com/?p=1252652).
* The comparison mentioned above was updated on 25-04-2024 and may be subject to change later.

## :house_with_garden:	Prerequisites 	
You can just run the following commands to install or update docker.

[Click here to get up to 4 always free instances](https://developer.oracle.com/free.html)

![Linux](https://img.shields.io/badge/Linux-FCC624?style=for-the-badge&logo=linux&logoColor=black)
### Install docker on Linux
```
sudo apt-get update
sudo apt-get -y install docker.io
```
If you use Arm or Aarch Linux OS, you must install [binfmt](https://hub.docker.com/r/tonistiigi/binfmt) emulator to support amd64 images on your PC.
### For ARM or AARCH Architectures
```
sudo docker run --privileged --rm tonistiigi/binfmt --install all
sudo apt-get install qemu binfmt-support qemu-user-static
```

![Windows](https://img.shields.io/badge/Windows-0078D6?style=for-the-badge&logo=windows&logoColor=white)
### Install Docker on Windows
Follow this [tutorial](https://www.youtube.com/watch?v=2ezNqqaSjq8) till 7.30 minutes where docker runs on Ubuntu and then follow the next steps below to download the code.
  
![Docker](https://img.shields.io/badge/docker-%230db7ed.svg?style=for-the-badge&logo=docker&logoColor=white)  
### Want to try Docker for free without installation?
If you like to use Docker directly for free, you can use [iximiuz](https://labs.iximiuz.com/playgrounds/docker).
## 👇	Next steps❓	
Download the code and edit the configuration file properties.conf with your account details.  
If you don't have GUI access but have terminal access, you can use the following commands to download the code.
### Download the code
```
wget -O main.zip https://github.com/Bhavishyadahiya/InternetIncome-debloated/archive/refs/heads/main.zip
sudo apt-get install unzip
unzip main.zip -d internetincome-download
cd internetincome-download/InternetIncome-debloated-main
# If the archive contains a nested internetIncome-debloated folder, enter it:
if [ -d internetIncome-debloated ]; then cd internetIncome-debloated; fi
```
* Please edit the "properties.conf" file using the following instructions and save the changes.  
* If you are using proxies, please set the `USE_PROXIES` value to `true`.
* Please refer to [How to add proxies](https://github.com/engageub/InternetIncome/wiki/Frequently-Asked-Questions#how-to-use-residential-proxies) for configuring various types of proxies.
* When setting your email, password, or token, always place them between single quotes ('') to consider special characters. 
* If you do not wish to use a particular application, leave the default value as it is, and the script will not run for that application.
### Update configuration and save
```
vi properties.conf
```
## :runner: Run the script
After you have followed all the mentioned above steps just run the following command to start and check your income flow to you :money_mouth_face:	.
### Start the process
```
sudo bash internetIncome.sh --start
```
## :stop_sign: Stop and Delete containers
To stop and delete all the containers started with the script. Run the following command.  Note that for Earnapp, Proxyrack, Traffmonetizer, and mysterium the data is not deleted and the same IDs will be used on delete and start since it is required to do a manual setup each time you start. Delete them or use a different folder to download the script if you want to change the node IDs.
### Stop and delete containers
Note that the backup of device IDs and node IDs are present in the same folder of the script. 
```
sudo bash internetIncome.sh --delete
```
### Delete backup files and folders
To delete the backup files and folders created by the script, use the following command.
```
sudo bash internetIncome.sh --deleteBackup
```

## :department_store:	Proxies or Hosting Providers
[Click here to get proxies or hosting providers with free credits.](https://github.com/engageub/InternetIncome/wiki/Proxies-and-Hosting-Providers)

**<ins>Note:</ins>** [Bytelixir](https://t.co/MNaVYiALR5), [PassiveApp](https://passiveapp.com/i/KWc0pl) and [Peer2Profit](https://t.me/peer2profit_app_bot?start=163956712261b9cf129932a)  support proxies in dashboard. You can add your proxies directly in website dashboard instead of running applications. 


## :grey_question: FAQ
### <ins>[Click here to view Frequently Asked Questions](https://github.com/engageub/InternetIncome/wiki/Frequently-Asked-Questions)</ins> 

## 📇 License:
* This product is available for free and may be freely copied and distributed in its original form. 
* However, it is prohibited to distribute modified copies of the product. 
* Personal modifications are allowed for personal use only.

## :warning: Disclaimer
This script is provided "as is" and without warranty of any kind.  
The author makes no warranties, express or implied, that this script is free of errors, defects, or suitable for any particular purpose.  
The author shall not  be liable for any damages suffered by any user of this script, whether direct, indirect, incidental, consequential, or special, arising from the use of or inability to use this script or its documentation, even if the author has been advised of the possibility of such damages.  
