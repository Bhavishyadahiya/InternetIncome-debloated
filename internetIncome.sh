#!/bin/bash

##################################################################################
# Author: engageub                                                               #
# Description: This script lets you earn passive income by sharing your internet #
# connection. It also supports multiple proxies with multiple accounts.          #
# Script Name: Internet Income (Supports Proxies)                                #
# Script Link: https://github.com/engageub/InternetIncome                        #
# DISCLAIMER: This script is provided "as is" and without warranty of any kind.  #
# The author makes no warranties, express or implied, that this script is free of#
# errors, defects, or suitable for any particular purpose. The author shall not  #
# be liable for any damages suffered by any user of this script, whether direct, #
# indirect, incidental, consequential, or special, arising from the use of or    #
# inability to use this script or its documentation, even if the author has been #
# advised of the possibility of such damages.                                    #
##################################################################################

# Wipter resource limits (per container; edit these values here)
WIPTER_MEMORY_LIMIT="120m"
WIPTER_CPU_LIMIT="0.2"

######### DO NOT EDIT THE CODE BELOW UNLESS YOU KNOW WHAT YOU ARE DOING  #########
# Colours
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
NOCOLOUR="\033[0m"

# File names
properties_file="properties.conf"
banner_file="banner.jpg"
proxies_file="proxies.txt"
container_names_file="containernames.txt"
antgain_file="antgain.txt"
proxyrack_file="proxyrack.txt"
networks_file="networks.txt"
idlepay_data_folder="idlepay-data"
bitping_data_folder="bitping-data"
urnetwork_data_folder="urnetwork-data"
restart_file="restart.sh"
dns_resolver_file="resolv.conf"
earn_fm_config_file="earnfm_config.json"
redsocks_entrypoint_file="redsocks_entrypoint.sh"
traffmonetizer_data_folder="traffmonetizerdata"
titan_data_folder="titan-data"
ur_proxies_file="ur_proxies.txt"
ur_data_proxies_file="$urnetwork_data_folder/data/.urnetwork/proxy"
process_id_file="process.pid"
required_files=($banner_file $properties_file $restart_file)
files_to_be_removed=($earn_fm_config_file $dns_resolver_file $container_names_file $networks_file $ur_proxies_file $ur_data_proxies_file $process_id_file $redsocks_entrypoint_file)
folders_to_be_removed=()
back_up_folders=($idlepay_data_folder $titan_data_folder $bitping_data_folder $urnetwork_data_folder $traffmonetizer_data_folder)
back_up_files=($antgain_file $proxyrack_file)
container_pulled=false
docker_in_docker_detected=false

#Unique Id
UNIQUE_ID=`cat /dev/urandom | LC_ALL=C tr -dc 'a-f0-9' | dd bs=1 count=32 2>/dev/null`

# Use banner if exists (printed once, no animation delay)
if [ -f "$banner_file" ]; then
  echo -e "${GREEN}"
  cat "$banner_file"
  echo -e "${NOCOLOUR}"
fi

# Check if a container with name already exists
# Existing direct-connection containers of the same image are deleted only after confirmation.
check_container_exists() {
  local container_name="$1"
  local image="$2"

  WATCH_TOWER_LABEL=""
  # Only floating app image tags are eligible for scoped auto-updates.
  case "${image##*:}" in
    latest|arm64v8|arm32v7)
      if [ "$AUTO_UPDATE_CONTAINERS" = true ]; then
        WATCH_TOWER_LABEL="--label=com.centurylinklabs.watchtower.scope=$UNIQUE_ID"
      fi
      ;;
  esac
  if [ -z "$container_name" ]; then
    echo -e "${RED}Error: container_name is required. Exiting..${NOCOLOUR}"
    exit 1
  fi
  if sudo docker inspect --type container "$container_name" >/dev/null 2>&1; then
    echo -e "${RED}A container with name $container_name already exists. Exiting..${NOCOLOUR}"
    exit 1
  fi
  if [ -n "$image" ]; then
    local matched_names=()
    local matched_images=()
    local cname container_image
    while IFS='|' read -r cname container_image; do
      [[ -z "$cname" || "$cname" == *"$UNIQUE_ID"* ]] && continue
      matched_names+=("$cname")
      matched_images+=("$container_image")
    done < <(sudo docker ps --filter "ancestor=$image" --filter "network=bridge" --format '{{.Names}}|{{.Image}}')

    if [ ${#matched_names[@]} -gt 0 ]; then
      echo -e "${YELLOW}The following existing direct-connection containers were found:${NOCOLOUR}"
      local idx
      for idx in "${!matched_names[@]}"; do
        echo -e "${YELLOW}  Name:${NOCOLOUR} ${matched_names[$idx]} ${YELLOW}Image:${NOCOLOUR} ${matched_images[$idx]}"
      done
      echo -e "${YELLOW}Do you want to delete these containers? (yes/no)${NOCOLOUR}"
      local choice=""
      if ! read -r -t 60 choice </dev/tty; then
        echo -e "${RED}No response within 60 seconds. Skipping container deletion.${NOCOLOUR}"
      else
        case "$choice" in
          yes|y|Y)
            for cname in "${matched_names[@]}"; do
              if sudo docker rm -f "$cname"; then
                echo -e "${GREEN}Deleted container $cname successfully.${NOCOLOUR}"
              else
                echo -e "${RED}Failed to delete container $cname. Exiting..${NOCOLOUR}"
                exit 1
              fi
            done
            ;;
          *) echo -e "${YELLOW}Skipping container deletion.${NOCOLOUR}" ;;
        esac
      fi
    fi
  fi
  echo "$container_name" | tee -a "$container_names_file"
}

# Validate proxies format
validate_proxies() {
  local lineno=0
  local proxy
  while IFS= read -r proxy || [[ -n "$proxy" ]]; do
    ((lineno++))
    [[ -z "$proxy" || "$proxy" == \#* ]] && continue
    local valid=false
    # Strip whitespace
    proxy=$(echo "$proxy" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    # Must have a protocol
    if echo "$proxy" | grep -qE "^[a-zA-Z0-9+-]+://"; then
      local protocol="${proxy%%://*}"
      protocol=$(echo "$protocol" | tr '[:upper:]' '[:lower:]')
      local rest="${proxy#*://}"
      # Split on last @ to handle special chars (including @) in passwords
      local hostport credentials
      if echo "$rest" | grep -q "@"; then
        hostport="${rest##*@}"
        credentials="${rest%@*}"
      else
        hostport="$rest"
        credentials=""
      fi
      # Validate host:port
      if echo "$hostport" | grep -qE "^[a-zA-Z0-9._-]+:[0-9]{1,5}$"; then
        local port="${hostport##*:}"
        if (( port >= 1 && port <= 65535 )); then
          case "$protocol" in
            http|https)
              [[ -z "$credentials" ]] && valid=true
              if [[ -n "$credentials" ]]; then
                local user="${credentials%%:*}"
                local pass="${credentials#*:}"
                [[ -n "$user" && "$credentials" == *":"* && -n "$pass" ]] && valid=true
              fi
              ;;
            socks4|socks4a)
              [[ -z "$credentials" || -n "$credentials" ]] && valid=true
              ;;
            socks5|socks5h)
              [[ -z "$credentials" ]] && valid=true
              if [[ -n "$credentials" ]]; then
                local user="${credentials%%:*}"
                local pass="${credentials#*:}"
                [[ -n "$user" && "$credentials" == *":"* && -n "$pass" ]] && valid=true
              fi
              ;;
            ss)
              if [[ -n "$credentials" ]]; then
                local method="${credentials%%:*}"
                local pass="${credentials#*:}"
                [[ -n "$method" && "$credentials" == *":"* && -n "$pass" ]] && valid=true
                echo "$credentials" | grep -qE "^[A-Za-z0-9+/=]+$" && valid=true
              fi
              ;;
          esac
        fi
      fi
    fi
    if [[ "$valid" == false ]]; then
      echo -e "${RED}Error: Invalid proxy format on line ${lineno}: '${proxy}'${NOCOLOUR}"
      echo -e "${RED}Expected: protocol://host:port or protocol://user:password@IP:PORT${NOCOLOUR}"
      exit 1
    fi
  done < "$proxies_file"
}

# IdlePay can route its own proxy list when no other app is enabled.
idlepay_only_enabled() {
  [[ $IDLEPAY_KEY || -f "$PWD/$idlepay_data_folder/data/config.json" ]] &&
  ! [[ ( $BITPING_EMAIL && $BITPING_PASSWORD ) ||
       $REPOCKET_API || $EARN_FM_API || $TRAFFMONETIZER_TOKEN ||
       $PROXYRACK_API || $PROXYBASE_ACCOUNT_ID ||
       ( $IPROYALS_EMAIL && $IPROYALS_PASSWORD ) ||
       ( $WIPTER_EMAIL && $WIPTER_PASSWORD ) ||
       ( $PACKETSHARE_EMAIL && $PACKETSHARE_PASSWORD ) ||
       $PEER2PROFIT_EMAIL || $ANTGAIN_API_KEY || $WIZARD_GAIN_EMAIL ||
       $PACKETSTREAM_CID || $PROXYLITE_USER_ID || $UR_AUTH_TOKEN ||
       $TITAN_HASH ]]
}

# Start all containers
start_containers() {

  local i=$1
  local proxy=$2
  local DNS_VOLUME="--mount type=bind,source=$PWD/$dns_resolver_file,target=/etc/resolv.conf,readonly"
  local TUN_DNS_VOLUME

  if [ "$container_pulled" = false ]; then
    # For users with Docker-in-Docker, the PWD path is on the host where Docker is installed.
    # The files are created in the same path as the inner Docker path.
    printf 'nameserver 8.8.8.8\nnameserver 8.8.4.4\nnameserver 1.1.1.1\nnameserver 1.0.0.1\n' > $dns_resolver_file;
    if [ ! -f $dns_resolver_file ]; then
      echo -e "${RED}There is a problem creating resolver file. Exiting..${NOCOLOUR}";
      exit 1;
    fi
    sudo docker pull docker:cli
    if sudo docker run --rm --mount type=bind,source=$PWD,target=/output docker:cli sh -c "if [ ! -f /output/$dns_resolver_file ]; then exit 0; else exit 1; fi"; then
      docker_in_docker_detected=true
    fi
    sudo docker run --rm --mount type=bind,source=$PWD,target=/output docker:cli sh -c "if [ ! -f /output/$dns_resolver_file ]; then printf 'nameserver 8.8.8.8\nnameserver 8.8.4.4\nnameserver 1.1.1.1\nnameserver 1.0.0.1\n' > /output/$dns_resolver_file; printf 'Docker-in-Docker is detected. The script runs with limited features.\nThe files and folders are created in the same path on the host where your parent docker is installed.\n'; fi"
  fi

  if [[ "$ENABLE_LOGS" != true ]]; then
    LOGS_PARAM="--log-driver none"
    TUN_LOG_PARAM="silent"
  else
    LOGS_PARAM="--log-driver=json-file --log-opt max-size=100k"
    TUN_LOG_PARAM="debug"
  fi

  if [[ $i && $proxy ]]; then
    NETWORK_TUN="--network=container:tun$UNIQUE_ID$i"

    echo -e "${YELLOW}Starting Proxy container..${NOCOLOUR}"
    # Starting tun containers
    # Resolve which tunnel engine to use based on TUNNEL_METHOD:
    #   auto      -> pick automatically (default, keeps original behavior)
    #   tun2socks -> force xjasonlyu/tun2socks (full IP tunnel)
    #   tun2proxy -> force tun2proxy (full IP tunnel, supports DNS over HTTPS)
    #   redsocks  -> lightweight TCP-only SOCKS/HTTP redirector
    tunnel_method=$(echo "${TUNNEL_METHOD:-auto}" | tr '[:upper:]' '[:lower:]')
    case "$tunnel_method" in
      auto|tun2socks|tun2proxy|redsocks) ;;
      *)
        echo -e "${RED}Invalid TUNNEL_METHOD '$TUNNEL_METHOD'. Use auto, tun2socks, tun2proxy or redsocks. Exiting..${NOCOLOUR}"
        exit 1
        ;;
    esac

    if [ "$tunnel_method" = "auto" ]; then
      if [[ "$USE_SOCKS5_DNS" == "true" && "$proxy" == socks5://* ]]; then
        tun_engine="hev"
      elif [[ "$proxy" =~ ^(http|https|socks4|socks5):// ]]; then
        tun_engine="tun2proxy"
      else
        tun_engine="tun2socks"
      fi
    else
      tun_engine="$tunnel_method"
    fi

    # DNS handling per engine
    TUN_DNS_VOLUME=""
    DNS_OPTION=""
    if [ "$tun_engine" = "tun2proxy" ]; then
      if [ "$USE_DNS_OVER_HTTPS" = true ]; then
        DNS_OPTION="--dns over-tcp"
      else
        DNS_OPTION="--dns virtual"
      fi
    else
      TUN_DNS_VOLUME="$DNS_VOLUME"
    fi

    if [ "$container_pulled" = false ]; then
      case "$tun_engine" in
        hev)       sudo docker pull ghcr.io/heiher/hev-socks5-tunnel:2.20.0 ;;
        tun2proxy) sudo docker pull ghcr.io/tun2proxy/tun2proxy:v0.8.7 ;;
        tun2socks) sudo docker pull xjasonlyu/tun2socks:v2.7.0 ;;
        redsocks)
          sudo docker pull alpine:3.20
          # Generic redsocks launcher; reads the proxy details from env vars at runtime.
          cat > "$redsocks_entrypoint_file" <<'RSEOF'
#!/bin/sh
set -e
apk add --no-cache redsocks iptables >/dev/null 2>&1 || { echo "redsocks install failed"; exit 1; }
RS_LOCAL_PORT=12345
if [ "$ENABLE_LOGS" = "true" ]; then RS_LOG="on"; else RS_LOG="off"; fi
{
  echo "base {"
  echo "  log_debug = $RS_LOG;"
  echo "  log_info = $RS_LOG;"
  echo "  log = \"stderr\";"
  echo "  daemon = off;"
  echo "  redirector = iptables;"
  echo "}"
  echo "redsocks {"
  echo "  local_ip = 0.0.0.0;"
  echo "  local_port = $RS_LOCAL_PORT;"
  echo "  ip = $PROXY_HOST;"
  echo "  port = $PROXY_PORT;"
  echo "  type = $PROXY_TYPE;"
  if [ -n "$PROXY_USER" ]; then
    echo "  login = \"$PROXY_USER\";"
    echo "  password = \"$PROXY_PASS\";"
  fi
  echo "}"
} > /etc/redsocks.conf
PROXY_IP=$(getent hosts "$PROXY_HOST" | awk '{print $1; exit}')
[ -z "$PROXY_IP" ] && PROXY_IP="$PROXY_HOST"
iptables -t nat -N REDSOCKS 2>/dev/null || iptables -t nat -F REDSOCKS
for net in 0.0.0.0/8 10.0.0.0/8 127.0.0.0/8 169.254.0.0/16 172.16.0.0/12 192.168.0.0/16 224.0.0.0/4 240.0.0.0/4; do
  iptables -t nat -A REDSOCKS -d "$net" -j RETURN
done
iptables -t nat -A REDSOCKS -d "$PROXY_IP" -j RETURN
iptables -t nat -A REDSOCKS -p tcp -j REDIRECT --to-ports $RS_LOCAL_PORT
iptables -t nat -A OUTPUT -p tcp -j REDSOCKS
exec redsocks -c /etc/redsocks.conf
RSEOF
          ;;
      esac
    fi
    if [ "$tun_engine" = "hev" ]; then
      SOCKS_PROXY=$proxy
      SOCKS_NO_SCHEME="${SOCKS_PROXY#socks5://}"
      if [[ "$SOCKS_NO_SCHEME" == *@* ]]; then
        SOCKS_CREDS="${SOCKS_NO_SCHEME%@*}"
        SOCKS_HOSTPORT="${SOCKS_NO_SCHEME##*@}"
        SOCKS_USER="${SOCKS_CREDS%%:*}"
        SOCKS_PASS="${SOCKS_CREDS#*:}"
      else
        SOCKS_HOSTPORT="$SOCKS_NO_SCHEME"
        SOCKS_USER=""
        SOCKS_PASS=""
      fi
      SOCKS_ADDR="${SOCKS_HOSTPORT%%:*}"
      SOCKS_PORT="${SOCKS_HOSTPORT##*:}"
      if [[ "$ENABLE_LOGS" != true ]]; then
        TUN_LOG_PARAM="warn"
      fi
      check_container_exists tun$UNIQUE_ID$i
      if CONTAINER_ID=$(sudo docker run --name tun$UNIQUE_ID$i $LOGS_PARAM $TUN_DNS_VOLUME --restart=always -e LOG_LEVEL=$TUN_LOG_PARAM --mount type=bind,source=/dev/net/tun,target=/dev/net/tun --sysctl net.ipv6.conf.all.disable_ipv6=1 --sysctl net.ipv6.conf.default.disable_ipv6=1 --cap-add=NET_ADMIN -e SOCKS5_ADDR="$SOCKS_ADDR" -e SOCKS5_PORT="$SOCKS_PORT" -e SOCKS5_USERNAME="$SOCKS_USER" -e SOCKS5_PASSWORD="$SOCKS_PASS" -e ICMP='reply' -d --no-healthcheck ghcr.io/heiher/hev-socks5-tunnel:2.20.0); then
        echo -e "${GREEN}Container tun$UNIQUE_ID$i started successfully.${NOCOLOUR}"
      else
        echo -e "${RED}Failed to start container for proxy. Exiting..${NOCOLOUR}"
        exit 1
      fi
    elif [ "$tun_engine" = "tun2proxy" ]; then
      if ! [[ "$proxy" =~ ^(http|https|socks4|socks5):// ]]; then
        echo -e "${RED}tun2proxy supports http/https/socks4/socks5 proxies only. Got: $proxy. Exiting..${NOCOLOUR}"
        exit 1
      fi
      if [[ "$ENABLE_LOGS" != true ]]; then
        TUN_LOG_PARAM="off"
      else
        TUN_LOG_PARAM="trace"
      fi
      check_container_exists tun$UNIQUE_ID$i
      if CONTAINER_ID=$(sudo docker run --name tun$UNIQUE_ID$i $LOGS_PARAM --restart=always --mount type=bind,source=/dev/net/tun,target=/dev/net/tun --sysctl net.ipv6.conf.all.disable_ipv6=1 --sysctl net.ipv6.conf.default.disable_ipv6=1 --cap-add=NET_ADMIN -d ghcr.io/tun2proxy/tun2proxy:v0.8.7 $DNS_OPTION --proxy $proxy --verbosity $TUN_LOG_PARAM); then
        echo -e "${GREEN}Container tun$UNIQUE_ID$i started successfully.${NOCOLOUR}"
      else
        echo -e "${RED}Failed to start container for proxy. Exiting..${NOCOLOUR}"
        exit 1
      fi
    elif [ "$tun_engine" = "redsocks" ]; then
      RS_SCHEME="${proxy%%://*}"
      RS_REST="${proxy#*://}"
      if [[ "$RS_REST" == *@* ]]; then
        RS_CREDS="${RS_REST%@*}"
        RS_HOSTPORT="${RS_REST##*@}"
        RS_USER="${RS_CREDS%%:*}"
        RS_PASS="${RS_CREDS#*:}"
      else
        RS_HOSTPORT="$RS_REST"
        RS_USER=""
        RS_PASS=""
      fi
      RS_HOST="${RS_HOSTPORT%%:*}"
      RS_PORT="${RS_HOSTPORT##*:}"
      case "$RS_SCHEME" in
        socks5|socks5h) RS_TYPE="socks5" ;;
        socks4|socks4a) RS_TYPE="socks4" ;;
        http|https)     RS_TYPE="http-connect" ;;
        *)
          echo -e "${RED}redsocks supports socks5/socks4/http proxies only. Got: $proxy. Exiting..${NOCOLOUR}"
          exit 1
          ;;
      esac
      check_container_exists tun$UNIQUE_ID$i
      if CONTAINER_ID=$(sudo docker run --name tun$UNIQUE_ID$i $LOGS_PARAM $TUN_DNS_VOLUME --restart=always --sysctl net.ipv6.conf.all.disable_ipv6=1 --sysctl net.ipv6.conf.default.disable_ipv6=1 --cap-add=NET_ADMIN -e PROXY_TYPE="$RS_TYPE" -e PROXY_HOST="$RS_HOST" -e PROXY_PORT="$RS_PORT" -e PROXY_USER="$RS_USER" -e PROXY_PASS="$RS_PASS" -e ENABLE_LOGS="$ENABLE_LOGS" --mount type=bind,source=$PWD/$redsocks_entrypoint_file,target=/entrypoint.sh,readonly -d alpine:3.20 sh /entrypoint.sh); then
        echo -e "${GREEN}Container tun$UNIQUE_ID$i started successfully.${NOCOLOUR}"
      else
        echo -e "${RED}Failed to start container for proxy. Exiting..${NOCOLOUR}"
        exit 1
      fi
    else
      check_container_exists tun$UNIQUE_ID$i
      if CONTAINER_ID=$(sudo docker run --name tun$UNIQUE_ID$i $LOGS_PARAM $TUN_DNS_VOLUME --restart=always -e LOGLEVEL=$TUN_LOG_PARAM -e PROXY=$proxy --mount type=bind,source=/dev/net/tun,target=/dev/net/tun --sysctl net.ipv6.conf.all.disable_ipv6=1 --sysctl net.ipv6.conf.default.disable_ipv6=1 --cap-add=NET_ADMIN -d xjasonlyu/tun2socks:v2.7.0); then
        echo -e "${GREEN}Container tun$UNIQUE_ID$i started successfully.${NOCOLOUR}"
      else
        echo -e "${RED}Failed to start container for proxy. Exiting..${NOCOLOUR}"
        exit 1
      fi
    fi
    sleep 1
  fi

  # Starting BitPing container
  if [[ $BITPING_EMAIL && $BITPING_PASSWORD ]]; then
    echo -e "${YELLOW}Starting Bitping container..${NOCOLOUR}"
    if [ "$container_pulled" = false ]; then
      sudo docker pull bitping/bitpingd:latest
    fi
    # Create bitping folder
    mkdir -p $PWD/$bitping_data_folder/data$i/.bitpingd
    sudo chmod -R 777 $PWD/$bitping_data_folder/data$i/.bitpingd
    check_container_exists bitping$UNIQUE_ID$i bitping/bitpingd:latest
    if CONTAINER_ID=$(sudo docker run -d $WATCH_TOWER_LABEL --name bitping$UNIQUE_ID$i --restart=always $NETWORK_TUN $LOGS_PARAM $DNS_VOLUME --mount type=bind,source=$PWD/$bitping_data_folder/data$i/.bitpingd,target=/root/.bitpingd -e BITPING_EMAIL=$BITPING_EMAIL -e BITPING_PASSWORD=$BITPING_PASSWORD bitping/bitpingd:latest); then
      echo -e "${GREEN}Container bitping$UNIQUE_ID$i started successfully.${NOCOLOUR}"
    else
      echo -e "${RED}Failed to start container for BitPing. Exiting..${NOCOLOUR}"
      exit 1
    fi
  else
    if [[ "$container_pulled" == false && "$ENABLE_LOGS" == true ]]; then
      echo -e "${RED}BitPing Node is not enabled. Ignoring BitPing..${NOCOLOUR}"
    fi
  fi

  # Starting Repocket container
  if [[ $REPOCKET_API ]]; then
    echo -e "${YELLOW}Starting Repocket container..${NOCOLOUR}"
    if [ "$container_pulled" = false ]; then
      sudo docker pull repocket/repocket:latest
    fi

    check_container_exists repocket$UNIQUE_ID$i repocket/repocket:latest
    if CONTAINER_ID=$(sudo docker run -d $WATCH_TOWER_LABEL --name repocket$UNIQUE_ID$i --restart=always $NETWORK_TUN $LOGS_PARAM $DNS_VOLUME -e RP_API_KEY=$REPOCKET_API repocket/repocket:latest); then
      echo -e "${GREEN}Container repocket$UNIQUE_ID$i started successfully.${NOCOLOUR}"
    else
      echo -e "${RED}Failed to start container for Repocket. Exiting..${NOCOLOUR}"
      exit 1
    fi
  else
    if [[ "$container_pulled" == false && "$ENABLE_LOGS" == true ]]; then
      echo -e "${RED}Repocket API is not configured. Ignoring Repocket..${NOCOLOUR}"
    fi
  fi

  # Starting Earn FM container
  if [[ $EARN_FM_API && "$USE_EARN_FM_FLEETSHARE" != true ]]; then
    echo -e "${YELLOW}Starting EarnFM container..${NOCOLOUR}"
    if [ "$container_pulled" = false ]; then
      sudo docker pull earnfm/earnfm-client:latest
    fi
    check_container_exists earnfm$UNIQUE_ID$i earnfm/earnfm-client:latest
    if CONTAINER_ID=$(sudo docker run -d $WATCH_TOWER_LABEL --name earnfm$UNIQUE_ID$i --restart=always $NETWORK_TUN $LOGS_PARAM $DNS_VOLUME -e EARNFM_TOKEN=$EARN_FM_API earnfm/earnfm-client:latest); then
      echo -e "${GREEN}Container earnfm$UNIQUE_ID$i started successfully.${NOCOLOUR}"
    else
      echo -e "${RED}Failed to start container for EarnFM. Exiting..${NOCOLOUR}"
      exit 1
    fi
  else
    if [[ "$container_pulled" == false && "$ENABLE_LOGS" == true ]]; then
      echo -e "${RED}EarnFM Api is not configured. Ignoring EarnFM..${NOCOLOUR}"
    fi
  fi

  # Starting Earn FM Fleetshare container
  if [[ $EARN_FM_API && "$USE_EARN_FM_FLEETSHARE" = true ]]; then
    if [ "$container_pulled" = false ]; then
      echo -e "${YELLOW}Starting EarnFM Fleetshare container..${NOCOLOUR}"
      sudo docker pull earnfm/fleetshare:latest
      if [ -f "$proxies_file" ]; then
        SOCKS_PROXIES=()
        while IFS= read -r line; do
          # Skip empty lines
          [[ -z "$line" ]] && continue
          if [[ "$line" == socks5://* ]]; then
            # Remove socks5:// prefix for config format
            proxy="${line#socks5://}"
            SOCKS_PROXIES+=("\"$proxy\"")
          fi
        done < "$proxies_file"
        if [[ ${#SOCKS_PROXIES[@]} -eq 0 ]]; then
          echo -e "${RED}Proxies file $proxies_file does not have socks5 proxies. Exiting..${NOCOLOUR}"
          exit 1
        fi
      	cat > "$earn_fm_config_file" <<-EOF
	{
	  "apiKey": "$EARN_FM_API",
	  "devices": {
	    "subnets": [],
	    "socksProxies": [$(IFS=,; echo "${SOCKS_PROXIES[*]}")]
	  },
	  "debug": false
	}
	EOF
        if [ ! -f "$earn_fm_config_file" ]; then
          echo -e "${RED}Config file could not be generated for EarnFM Fleetshare. Exiting..${NOCOLOUR}"
          exit 1
        fi
        check_container_exists earnfm$UNIQUE_ID$i earnfm/fleetshare:latest
        if CONTAINER_ID=$(sudo docker run -d $WATCH_TOWER_LABEL --name earnfm$UNIQUE_ID$i --restart=always $LOGS_PARAM $DNS_VOLUME --mount type=bind,source=$PWD/$earn_fm_config_file,target=/app/config.json earnfm/fleetshare:latest); then
          echo -e "${GREEN}Container earnfm$UNIQUE_ID$i started successfully.${NOCOLOUR}"
        else
          echo -e "${RED}Failed to start container for EarnFM. Exiting..${NOCOLOUR}"
          exit 1
        fi
      else
        echo -e "${RED}Proxies file $proxies_file does not exist. Exiting..${NOCOLOUR}"
        exit 1
      fi
    fi
  else
    if [[ "$container_pulled" == false && "$ENABLE_LOGS" == true ]]; then
      echo -e "${RED}EarnFM Fleetshare is not configured. Ignoring EarnFM Fleetshare..${NOCOLOUR}"
    fi
  fi

  # Starting Traffmonetizer container
  if [[ $TRAFFMONETIZER_TOKEN ]]; then
    echo -e "${YELLOW}Starting Traffmonetizer container..${NOCOLOUR}"
    if [ "$CPU_ARCH" == "aarch64" ] || [ "$CPU_ARCH" == "arm64" ]; then
      traffmonetizer_image="traffmonetizer/cli_v2:arm64v8"
    elif [ "$CPU_ARCH" == "armv7l" ]; then
      traffmonetizer_image="traffmonetizer/cli_v2:arm32v7"
    else
      traffmonetizer_image="--platform=linux/amd64 traffmonetizer/cli_v2:latest"
    fi
    if [ "$container_pulled" = false ]; then
      sudo docker pull $traffmonetizer_image
    fi
    mkdir -p $PWD/$traffmonetizer_data_folder/data$i
    sudo chmod -R 777 $PWD/$traffmonetizer_data_folder/data$i
    traffmonetizer_volume="--mount type=bind,source=$PWD/$traffmonetizer_data_folder/data$i,target=/.config/traffmonetizer"
    check_container_exists traffmon$UNIQUE_ID$i "${traffmonetizer_image##* }"
    if CONTAINER_ID=$(sudo  docker run -d $WATCH_TOWER_LABEL --name traffmon$UNIQUE_ID$i --restart=always $LOGS_PARAM $DNS_VOLUME $NETWORK_TUN $traffmonetizer_volume $traffmonetizer_image start accept --device-name $DEVICE_NAME$i --token $TRAFFMONETIZER_TOKEN); then
      echo -e "${GREEN}Container traffmon$UNIQUE_ID$i started successfully.${NOCOLOUR}"
    else
      echo -e "${RED}Failed to start container for Traffmonetizer. Exiting..${NOCOLOUR}"
      exit 1
    fi
  else
    if [[ "$container_pulled" == false && "$ENABLE_LOGS" == true ]]; then
      echo -e "${RED}Traffmonetizer Token is not configured. Ignoring Traffmonetizer..${NOCOLOUR}"
    fi
  fi

  # Starting ProxyRack container
  if [[ $PROXYRACK_API ]]; then
    echo -e "${YELLOW}Starting Proxyrack container..${NOCOLOUR}"
    for loop_count in {1..500}; do
      if [ "$loop_count" -eq 500 ]; then
        echo -e "${RED}Unique UUID cannot be generated for ProxyRack. Exiting..${NOCOLOUR}"
        exit 1
      fi
      RANDOM_ID=`cat /dev/urandom | LC_ALL=C tr -dc 'A-F0-9' | dd bs=1 count=64 2>/dev/null`
      if [ -f $proxyrack_file ]; then
        if ! grep -qF "$RANDOM_ID" "$proxyrack_file"; then
          break
        fi
      else
        break;
      fi
    done
    if [ "$container_pulled" = false ]; then
      sudo docker pull --platform=linux/amd64 proxyrack/pop:latest
    fi
    if [ -f $proxyrack_file ] && proxyrack_uuid=$(sed "${i}q;d" $proxyrack_file);then
      if [[ $proxyrack_uuid ]];then
        echo $proxyrack_uuid
      else
        echo "Proxyrack UUID does not exist, creating UUID"
        proxyrack_uuid=$RANDOM_ID
        printf "%s\n" "$proxyrack_uuid" | tee -a $proxyrack_file
      fi
    else
      echo "Proxyrack UUID does not exist, creating UUID"
      proxyrack_uuid=$RANDOM_ID
      printf "%s\n" "$proxyrack_uuid" | tee -a $proxyrack_file
    fi

    check_container_exists proxyrack$UNIQUE_ID$i proxyrack/pop:latest
    if CONTAINER_ID=$(sudo docker run -d $WATCH_TOWER_LABEL --name proxyrack$UNIQUE_ID$i --platform=linux/amd64 $NETWORK_TUN $LOGS_PARAM $DNS_VOLUME --restart=always -e UUID=$proxyrack_uuid  -e DEVICE_NAME=$DEVICE_NAME$i -e API_KEY=$PROXYRACK_API proxyrack/pop:latest); then
      echo -e "${GREEN}Container proxyrack$UNIQUE_ID$i started successfully.${NOCOLOUR}"
    else
      echo -e "${RED}Failed to start container for Proxyrack. Exiting..${NOCOLOUR}"
      exit 1
    fi
  else
    if [[ "$container_pulled" == false && "$ENABLE_LOGS" == true ]]; then
      echo -e "${RED}Proxyrack is not enabled. Ignoring Proxyrack..${NOCOLOUR}"
    fi
  fi

  # Starting ProxyBase container
  if [[ "$PROXYBASE_ACCOUNT_ID" ]]; then
    echo -e "${YELLOW}Starting Proxybase container..${NOCOLOUR}"
    if [ "$container_pulled" = false ]; then
      sudo docker pull ghcr.io/proxybaseorg/peer-cli:latest
    fi
    check_container_exists proxybase$UNIQUE_ID$i ghcr.io/proxybaseorg/peer-cli:latest
    if CONTAINER_ID=$(sudo docker run -d $WATCH_TOWER_LABEL --name proxybase$UNIQUE_ID$i $NETWORK_TUN $LOGS_PARAM $DNS_VOLUME --restart=always ghcr.io/proxybaseorg/peer-cli:latest $PROXYBASE_ACCOUNT_ID $DEVICE_NAME$i); then
      echo -e "${GREEN}Container proxybase$UNIQUE_ID$i started successfully.${NOCOLOUR}"
    else
      echo -e "${RED}Failed to start container for Proxybase. Exiting..${NOCOLOUR}"
      exit 1
    fi
  else
    if [[ "$container_pulled" == false && "$ENABLE_LOGS" == true ]]; then
      echo -e "${RED}Proxybase is not enabled. Ignoring Proxybase..${NOCOLOUR}"
    fi
  fi

  # Starting IPRoyals pawns container
  if [[ $IPROYALS_EMAIL && $IPROYALS_PASSWORD ]]; then
    echo -e "${YELLOW}Starting IPRoyals container..${NOCOLOUR}"
    if [ "$container_pulled" = false ]; then
      sudo docker pull iproyal/pawns-cli:latest
    fi
    check_container_exists pawns$UNIQUE_ID$i iproyal/pawns-cli:latest
    if CONTAINER_ID=$(sudo docker run -d $WATCH_TOWER_LABEL --name pawns$UNIQUE_ID$i --restart=on-failure:5 $LOGS_PARAM $DNS_VOLUME $NETWORK_TUN iproyal/pawns-cli:latest -email=$IPROYALS_EMAIL -password=$IPROYALS_PASSWORD -device-name=$DEVICE_NAME$i -device-id=$DEVICE_NAME$i -accept-tos); then
      echo -e "${GREEN}Container pawns$UNIQUE_ID$i started successfully.${NOCOLOUR}"
    else
      echo -e "${RED}Failed to start container for IPRoyals. Exiting..${NOCOLOUR}"
      exit 1
    fi
  else
    if [[ "$container_pulled" == false && "$ENABLE_LOGS" == true ]]; then
      echo -e "${RED}IPRoyals Email or Password is not configured. Ignoring IPRoyals..${NOCOLOUR}"
    fi
  fi

  # Starting Wipter container
  if [[ $WIPTER_EMAIL && $WIPTER_PASSWORD ]]; then
    echo -e "${YELLOW}Starting Wipter container..${NOCOLOUR}"
    if [ "$container_pulled" = false ]; then
      sudo docker pull ghcr.io/techroy23/docker-wipter:latest
    fi
    check_container_exists wipter$UNIQUE_ID$i ghcr.io/techroy23/docker-wipter:latest
    if CONTAINER_ID=$(sudo docker run -d $WATCH_TOWER_LABEL --name wipter$UNIQUE_ID$i --memory="$WIPTER_MEMORY_LIMIT" --cpus="$WIPTER_CPU_LIMIT" --restart=always $LOGS_PARAM $DNS_VOLUME $NETWORK_TUN -e WIPTER_EMAIL=$WIPTER_EMAIL -e WIPTER_PASSWORD=$WIPTER_PASSWORD ghcr.io/techroy23/docker-wipter:latest); then
      echo -e "${GREEN}Container wipter$UNIQUE_ID$i started successfully.${NOCOLOUR}"
    else
      echo -e "${RED}Failed to start container for Wipter. Exiting..${NOCOLOUR}"
      exit 1
    fi
  else
    if [[ "$container_pulled" == false && "$ENABLE_LOGS" == true ]]; then
      echo -e "${RED}Wipter Email or Password is not configured. Ignoring Wipter..${NOCOLOUR}"
    fi
  fi

  # Starting PacketShare container
  if [[ $PACKETSHARE_EMAIL && $PACKETSHARE_PASSWORD ]]; then
    echo -e "${YELLOW}Starting PacketShare container..${NOCOLOUR}"
    if [ "$container_pulled" = false ]; then
      sudo docker pull packetshare/packetshare:latest
    fi
    check_container_exists packetshare$UNIQUE_ID$i packetshare/packetshare:latest
    if CONTAINER_ID=$(sudo docker run -d $WATCH_TOWER_LABEL --name packetshare$UNIQUE_ID$i --restart=always $LOGS_PARAM $DNS_VOLUME $NETWORK_TUN packetshare/packetshare:latest -accept-tos -email=$PACKETSHARE_EMAIL -password=$PACKETSHARE_PASSWORD); then
      echo -e "${GREEN}Container packetshare$UNIQUE_ID$i started successfully.${NOCOLOUR}"
    else
      echo -e "${RED}Failed to start container for PacketShare. Exiting..${NOCOLOUR}"
      exit 1
    fi
  else
    if [[ "$container_pulled" == false && "$ENABLE_LOGS" == true ]]; then
      echo -e "${RED}PacketShare Email or Password is not configured. Ignoring PacketShare..${NOCOLOUR}"
    fi
  fi

  # Starting Peer2Profit container
  if [[ $PEER2PROFIT_EMAIL ]]; then
    echo -e "${YELLOW}Starting Peer2Profit container..${NOCOLOUR}"
    if [ "$container_pulled" = false ]; then
      sudo docker pull --platform=linux/amd64 enwaiax/peer2profit:latest
    fi
    check_container_exists peer2profit$UNIQUE_ID$i enwaiax/peer2profit:latest
    if CONTAINER_ID=$(sudo docker run -d $WATCH_TOWER_LABEL --platform=linux/amd64 --name peer2profit$UNIQUE_ID$i $NETWORK_TUN $LOGS_PARAM $DNS_VOLUME --restart always -e email=$PEER2PROFIT_EMAIL enwaiax/peer2profit:latest); then
      echo -e "${GREEN}Container peer2profit$UNIQUE_ID$i started successfully.${NOCOLOUR}"
    else
      echo -e "${RED}Failed to start container for Peer2Profit. Exiting..${NOCOLOUR}"
      exit 1
    fi
  else
    if [[ "$container_pulled" == false && "$ENABLE_LOGS" == true ]]; then
      echo -e "${RED}Peer2Profit Email is not configured. Ignoring Peer2Profit..${NOCOLOUR}"
    fi
  fi

  # Starting AntGain container
  if [[ $ANTGAIN_API_KEY ]]; then
    echo -e "${YELLOW}Starting AntGain container..${NOCOLOUR}"
    if [ "$container_pulled" = false ]; then
      if ! command -v uuidgen &> /dev/null; then
        echo -e "${RED}uuidgen is not installed. Attempting to install it...${NOCOLOUR}"
        sudo apt-get update && sudo apt-get -y install uuid-runtime          
      fi
      sudo docker pull pinors/antgain-cli:latest
    fi
    for loop_count in {1..500}; do
      if [ "$loop_count" -eq 500 ]; then
        echo -e "${RED}Unique UUID cannot be generated for AntGain. Exiting..${NOCOLOUR}"
        exit 1
      fi
      RANDOM_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')
      if [ -f $antgain_file ]; then
        if ! grep -qF "$RANDOM_ID" "$antgain_file"; then
          break
        fi
      else
        break;
      fi
    done
    if [[ ! $RANDOM_ID ]]; then
      echo -e "${RED}Unable to install uuidgen automatically. Please install it manually and try again. Exiting...${NOCOLOUR}"
      exit 1;                                                                   
    fi
    if [ -f $antgain_file ] && antgain_uuid=$(sed "${i}q;d" $antgain_file);then
      if [[ $antgain_uuid ]];then
        echo $antgain_uuid
      else
        echo "Antgain UUID does not exist, creating UUID"
        antgain_uuid=$RANDOM_ID
        printf "%s\n" "$antgain_uuid" | tee -a $antgain_file
      fi
    else
      echo "Antgain UUID does not exist, creating UUID"
      antgain_uuid=$RANDOM_ID
      printf "%s\n" "$antgain_uuid" | tee -a $antgain_file
    fi

    check_container_exists antgain$UNIQUE_ID$i pinors/antgain-cli:latest
    if CONTAINER_ID=$(sudo docker run -d $WATCH_TOWER_LABEL --name antgain$UNIQUE_ID$i $NETWORK_TUN $LOGS_PARAM $DNS_VOLUME --restart always -e ANTGAIN_API_KEY=$ANTGAIN_API_KEY -e ANTGAIN_DEVICE_ID=$antgain_uuid --no-healthcheck pinors/antgain-cli:latest run); then
      echo -e "${GREEN}Container antgain$UNIQUE_ID$i started successfully.${NOCOLOUR}"
    else
      echo -e "${RED}Failed to start container for AntGain. Exiting..${NOCOLOUR}"
      exit 1
    fi
  else
    if [[ "$container_pulled" == false && "$ENABLE_LOGS" == true ]]; then
      echo -e "${RED}AntGain API is not configured. Ignoring AntGain..${NOCOLOUR}"
    fi
  fi

  # Starting WizardGain container
  if [[ $WIZARD_GAIN_EMAIL ]]; then
    echo -e "${YELLOW}Starting WizardGain container..${NOCOLOUR}"
    if [ "$container_pulled" = false ]; then
      sudo docker pull wizardgain/worker:latest
    fi
    check_container_exists wizardgain$UNIQUE_ID$i wizardgain/worker:latest
    if CONTAINER_ID=$(sudo docker run -d $WATCH_TOWER_LABEL --name wizardgain$UNIQUE_ID$i $NETWORK_TUN $LOGS_PARAM $DNS_VOLUME --restart always -e EMAIL=$WIZARD_GAIN_EMAIL wizardgain/worker:latest); then
      echo -e "${GREEN}Container wizardgain$UNIQUE_ID$i started successfully.${NOCOLOUR}"
    else
      echo -e "${RED}Failed to start container for WizardGain. Exiting..${NOCOLOUR}"
      exit 1
    fi
  else
    if [[ "$container_pulled" == false && "$ENABLE_LOGS" == true ]]; then
      echo -e "${RED}WizardGain Email is not configured. Ignoring WizardGain..${NOCOLOUR}"
    fi
  fi

  # Starting PacketStream container
  if [[ $PACKETSTREAM_CID ]]; then
    echo -e "${YELLOW}Starting PacketStream container..${NOCOLOUR}"
    if [ "$container_pulled" = false ]; then
      sudo docker pull packetstream/psclient:latest
    fi
    check_container_exists packetstream$UNIQUE_ID$i packetstream/psclient:latest
    if CONTAINER_ID=$(sudo docker run -d $WATCH_TOWER_LABEL --name packetstream$UNIQUE_ID$i $NETWORK_TUN $LOGS_PARAM $DNS_VOLUME --restart always -e HTTP_PROXY="" -e HTTPS_PROXY="" -e CID=$PACKETSTREAM_CID packetstream/psclient:latest); then
      echo -e "${GREEN}Container packetstream$UNIQUE_ID$i started successfully.${NOCOLOUR}"
    else
      echo -e "${RED}Failed to start container for PacketStream. Exiting..${NOCOLOUR}"
      exit 1
    fi
  else
    if [[ "$container_pulled" == false && "$ENABLE_LOGS" == true ]]; then
      echo -e "${RED}PacketStream CID is not configured. Ignoring PacketStream..${NOCOLOUR}"
    fi
  fi

  # Starting Proxylite container
  if [[ $PROXYLITE_USER_ID ]]; then
    echo -e "${YELLOW}Starting Proxylite container..${NOCOLOUR}"
    if [ "$container_pulled" = false ]; then
      sudo docker pull proxylite/proxyservice:latest
      check_container_exists dindproxylite$UNIQUE_ID$i
      if CONTAINER_ID=$(sudo docker run -d --name dindproxylite$UNIQUE_ID$i $LOGS_PARAM $DNS_VOLUME --restart=always --mount type=bind,source=/var/run/docker.sock,target=/var/run/docker.sock --mount type=bind,source=$(which docker),target=/usr/bin/docker --mount type=bind,source=$PWD,target=/proxylite --network none docker:cli /bin/sh -c 'cd /proxylite && chmod +x /proxylite/restart.sh && while true; do sleep 86400; /proxylite/restart.sh --restartProxylite; done'); then
         echo -e "${GREEN}Container dindproxylite$UNIQUE_ID$i started successfully.${NOCOLOUR}"
      else
        echo -e "${RED}Failed to start container for Proxylite restart. Exiting..${NOCOLOUR}"
        exit 1
      fi
    fi
    check_container_exists proxylite$UNIQUE_ID$i proxylite/proxyservice:latest
    if CONTAINER_ID=$(sudo docker run -d $WATCH_TOWER_LABEL --name proxylite$UNIQUE_ID$i --platform=linux/amd64 $NETWORK_TUN $LOGS_PARAM $DNS_VOLUME  -e USER_ID=$PROXYLITE_USER_ID --restart=always proxylite/proxyservice:latest); then
      echo -e "${GREEN}Container proxylite$UNIQUE_ID$i started successfully.${NOCOLOUR}"
    else
      echo -e "${RED}Failed to start container for Proxylite. Exiting..${NOCOLOUR}"
      exit 1
    fi
  else
    if [[ "$container_pulled" == false && "$ENABLE_LOGS" == true ]]; then
      echo -e "${RED}Proxylite is not configured. Ignoring Proxylite..${NOCOLOUR}"
    fi
  fi

  # Starting URnetwork container
  if [[ $UR_AUTH_TOKEN ]]; then
    echo -e "${YELLOW}Starting URnetwork container..${NOCOLOUR}"
    if [ "$container_pulled" = false ]; then
      sudo docker pull bringyour/community-provider:latest
      # Create URnetwork folder
      mkdir -p $PWD/$urnetwork_data_folder/data/.urnetwork
      sudo chmod -R 777 $PWD/$urnetwork_data_folder/data/.urnetwork
      if [ ! -f "$PWD/$urnetwork_data_folder/data/.urnetwork/jwt" ]; then
        sudo docker run --rm $DNS_VOLUME $NETWORK_TUN --mount type=bind,source="$PWD/$urnetwork_data_folder/data/.urnetwork",target=/root/.urnetwork --entrypoint /usr/local/sbin/bringyour-provider bringyour/community-provider:latest auth $UR_AUTH_TOKEN
        sleep 1
        if [ ! -f "$PWD/$urnetwork_data_folder/data/.urnetwork/jwt" ]; then
          echo -e "${RED}JWT file could not be generated for URnetwork. Exiting..${NOCOLOUR}"
          exit 1
        fi
      fi
      if [ "$UR_NETWORK_PROXY_MODE" = true ]; then
        if [ -f "$proxies_file" ]; then
          SOCKS_PROXIES=()
          while IFS= read -r line; do
            # Skip empty lines
            [[ -z "$line" ]] && continue
            if [[ "$line" == socks5://* ]]; then
              # Remove socks5:// prefix for config format
              SOCKS_PROXY=$line
              # Strip scheme
              SOCKS_NO_SCHEME="${SOCKS_PROXY#socks5://}"
              # If auth exists, split it
              if [[ "$SOCKS_NO_SCHEME" == *@* ]]; then
                SOCKS_CREDS="${SOCKS_NO_SCHEME%@*}"
                SOCKS_HOSTPORT="${SOCKS_NO_SCHEME##*@}"
                SOCKS_USER="${SOCKS_CREDS%%:*}"
                SOCKS_PASS="${SOCKS_CREDS#*:}"
              else
                SOCKS_HOSTPORT="$SOCKS_NO_SCHEME"
                SOCKS_USER=""
                SOCKS_PASS=""
              fi
              SOCKS_ADDR="${SOCKS_HOSTPORT%%:*}"
              SOCKS_PORT="${SOCKS_HOSTPORT##*:}"
              if [[ $SOCKS_USER && $SOCKS_PASS ]]; then
                echo "$SOCKS_ADDR:$SOCKS_PORT:$SOCKS_USER:$SOCKS_PASS" >> $ur_proxies_file
              else
                echo "$SOCKS_ADDR:$SOCKS_PORT" >> $ur_proxies_file
              fi
            fi
          done < "$proxies_file"
        fi
        if [ ! -f "$ur_proxies_file" ]; then
          echo -e "${RED}Proxies file $ur_proxies_file does not have socks5 proxies. Exiting..${NOCOLOUR}"
          exit 1
        fi
        # Generate proxy file using urnetwork
        sudo docker run --rm $DNS_VOLUME --mount type=bind,source="$PWD/$urnetwork_data_folder/data/.urnetwork",target=/root/.urnetwork --mount type=bind,source="$PWD/$ur_proxies_file",target=/root/ur_proxy.txt bringyour/community-provider:latest proxy add --proxy_file=/root/ur_proxy.txt
        sleep 1
        if [ ! -f "$PWD/$urnetwork_data_folder/data/.urnetwork/proxy" ]; then
          echo -e "${RED}Proxy file could not be generated for URnetwork. Exiting..${NOCOLOUR}"
          exit 1
        fi
        check_container_exists urnetwork$UNIQUE_ID$i bringyour/community-provider:latest
        if CONTAINER_ID=$(sudo docker run -d $WATCH_TOWER_LABEL --name urnetwork$UNIQUE_ID$i --restart=always $LOGS_PARAM $DNS_VOLUME --mount type=bind,source="$PWD/$urnetwork_data_folder/data/.urnetwork",target=/root/.urnetwork bringyour/community-provider:latest provide); then
          echo -e "${GREEN}Container urnetwork$UNIQUE_ID$i started successfully.${NOCOLOUR}"
        else
          echo -e "${RED}Failed to start container for URnetwork. Exiting..${NOCOLOUR}"
          exit 1
        fi
      else
        check_container_exists dindurnetwork$UNIQUE_ID$i
        if CONTAINER_ID=$(sudo docker run -d --name dindurnetwork$UNIQUE_ID$i $LOGS_PARAM $DNS_VOLUME --restart=always --mount type=bind,source=/var/run/docker.sock,target=/var/run/docker.sock --mount type=bind,source=$(which docker),target=/usr/bin/docker --mount type=bind,source=$PWD,target=/urnetwork --network none docker:cli /bin/sh -c 'cd /urnetwork && chmod +x /urnetwork/restart.sh && while true; do sleep 86400; /urnetwork/restart.sh --restartURnetwork; done'); then
          echo -e "${GREEN}Container dindurnetwork$UNIQUE_ID$i started successfully.${NOCOLOUR}"
        else
          echo -e "${RED}Failed to start container for URnetwork restart. Exiting..${NOCOLOUR}"
          exit 1
        fi
      fi
    fi
    if [ "$UR_NETWORK_PROXY_MODE" != true ]; then
      check_container_exists urnetwork$UNIQUE_ID$i bringyour/community-provider:latest
      if CONTAINER_ID=$(sudo docker run -d $WATCH_TOWER_LABEL --name urnetwork$UNIQUE_ID$i --restart=always $NETWORK_TUN $LOGS_PARAM $DNS_VOLUME --mount type=bind,source="$PWD/$urnetwork_data_folder/data/.urnetwork",target=/root/.urnetwork bringyour/community-provider:latest provide); then
        echo -e "${GREEN}Container urnetwork$UNIQUE_ID$i started successfully.${NOCOLOUR}"
      else
        echo -e "${RED}Failed to start container for URnetwork. Exiting..${NOCOLOUR}"
        exit 1
      fi
    fi
  else
    if [[ "$container_pulled" == false && "$ENABLE_LOGS" == true ]]; then
      echo -e "${RED}URnetwork Node is not enabled. Ignoring URnetwork..${NOCOLOUR}"
    fi
  fi

  # Starting Titan Network container
  if [[ $TITAN_HASH ]]; then
    if [ "$container_pulled" = false ]; then
      sudo docker pull nezha123/titan-edge:latest
      mkdir -p $PWD/$titan_data_folder/data$i
      sudo chmod -R 777 $PWD/$titan_data_folder/data$i
      titan_volume="--mount type=bind,source=$PWD/$titan_data_folder/data$i,target=/root/.titanedge"
      check_container_exists titan$UNIQUE_ID$i nezha123/titan-edge:latest
      if CONTAINER_ID=$(sudo  docker run -d $WATCH_TOWER_LABEL --name titan$UNIQUE_ID$i --restart=always $LOGS_PARAM $DNS_VOLUME $NETWORK_TUN $titan_volume nezha123/titan-edge:latest); then
        echo -e "${GREEN}Container titan$UNIQUE_ID$i started successfully.${NOCOLOUR}"
      else
        echo -e "${RED}Failed to start container for Titan Network. Exiting..${NOCOLOUR}"
        exit 1
      fi
      sleep 5
      sudo docker run --rm -it $titan_volume nezha123/titan-edge:latest bind --hash=$TITAN_HASH https://api-test1.container1.titannet.io/api/v2/device/binding
      echo -e "${GREEN}The current script is designed to support only a single device for the Titan Network. Please create a new folder, download the InternetIncome script, and add the appropriate hash for the new device.${NOCOLOUR}"
    fi
  else
    if [[ "$container_pulled" == false && "$ENABLE_LOGS" == true ]]; then
      echo -e "${RED}Titan Network Hash is not configured. Ignoring Titan Network..${NOCOLOUR}"
    fi
  fi

  # Starting IdlePay container (native proxy list, one persistent device per folder)
  if [[ $IDLEPAY_KEY || -f "$PWD/$idlepay_data_folder/data/config.json" ]]; then
    if [ "$container_pulled" = false ]; then
      echo -e "${YELLOW}Starting IdlePay container..${NOCOLOUR}"
      local idlepay_direct=on
      local idlepay_proxy_volume=()
      if [ "$USE_PROXIES" = true ]; then
        if grep -Ev '^[[:space:]]*(#|$|(socks5|socks5h|http|https)://)' "$proxies_file" | grep -q .; then
          echo -e "${RED}IdlePay supports only static HTTP/HTTPS/SOCKS5 proxies. Disable IdlePay or use supported proxies. Exiting..${NOCOLOUR}"
          exit 1
        fi
        idlepay_direct=off
        idlepay_proxy_volume=(--mount "type=bind,source=$PWD/$proxies_file,target=/proxies.txt,readonly")
      fi
      sudo docker pull ghcr.io/idlepay/idlepay:latest
      mkdir -p "$PWD/$idlepay_data_folder/data"
      check_container_exists idlepay$UNIQUE_ID ghcr.io/idlepay/idlepay:latest
      if CONTAINER_ID=$(sudo docker run -d $WATCH_TOWER_LABEL --name idlepay$UNIQUE_ID --restart unless-stopped --hostname "$DEVICE_NAME" $LOGS_PARAM $DNS_VOLUME -e IDLEPAY_KEY="$IDLEPAY_KEY" -e IDLEPAY_DIRECT="$idlepay_direct" --mount "type=bind,source=$PWD/$idlepay_data_folder/data,target=/etc/idlepay" "${idlepay_proxy_volume[@]}" ghcr.io/idlepay/idlepay:latest); then
        echo -e "${GREEN}Container idlepay$UNIQUE_ID started successfully. Check enrollment with: sudo docker exec idlepay$UNIQUE_ID idlepay status${NOCOLOUR}"
      else
        echo -e "${RED}Failed to start container for IdlePay. Exiting..${NOCOLOUR}"
        exit 1
      fi
    fi
  else
    if [[ "$container_pulled" == false && "$ENABLE_LOGS" == true ]]; then
      echo -e "${RED}IdlePay enrollment key is not configured. Ignoring IdlePay..${NOCOLOUR}"
    fi
  fi

  # Starting Watchtower container for scoped floating-tag app images
  if [[ "$AUTO_UPDATE_CONTAINERS" == true && "$container_pulled" == false ]]; then
    echo -e "${YELLOW}Starting Internet Income Watchtower container..${NOCOLOUR}"
    sudo docker pull ghcr.io/nicholas-fedor/watchtower:nightly
    check_container_exists internetincomewatchtower$UNIQUE_ID
    if CONTAINER_ID=$(sudo docker run -d --name internetincomewatchtower$UNIQUE_ID $LOGS_PARAM $DNS_VOLUME --restart=always -e WATCHTOWER_CLEANUP=true --mount type=bind,source=/var/run/docker.sock,target=/var/run/docker.sock --no-healthcheck ghcr.io/nicholas-fedor/watchtower:nightly --scope $UNIQUE_ID --interval 86400); then
      echo -e "${GREEN}Container internetincomewatchtower$UNIQUE_ID started successfully.${NOCOLOUR}"
    else
      echo -e "${RED}Failed to start container for Watchtower. Exiting..${NOCOLOUR}"
      exit 1
    fi
  fi

  container_pulled=true
}

# Update and Install Docker
if [[ "$1" == "--install" ]]; then
  sudo apt-get update
  sudo apt-get -y install docker.io
  CPU_ARCH=`uname -m`
  if [ "$CPU_ARCH" == "aarch64" ] || [ "$CPU_ARCH" == "arm64" ]; then
    sudo docker run --privileged --rm tonistiigi/binfmt --install all
    sudo apt-get install qemu binfmt-support qemu-user-static
  fi
  # Check if Docker is installed
  if command -v docker &> /dev/null; then
    echo -e "${GREEN}Docker is installed.${NOCOLOUR}"
    docker --version
    exit 0
  else
    echo -e "${RED}Docker is not installed. There is a problem installing Docker.${NOCOLOUR}"
    echo "Please install Docker manually by following https://docs.docker.com/engine/install/"
    exit 1
  fi
fi

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
  echo -e "${RED}Docker is not installed, without which the script cannot start. Exiting..${NOCOLOUR}"
  echo -e "To install Docker and its dependencies, please run the following command\n"
  echo -e "${YELLOW}sudo bash internetIncome.sh --install${NOCOLOUR}\n"
  exit 1
fi

if [[ "$1" == "--start" ]]; then
  echo -e "\n\nStarting.."

  # Check if the required files are present
  for required_file in "${required_files[@]}"; do
    if [ ! -f "$required_file" ]; then
      echo -e "${RED}Required file $required_file does not exist, exiting..${NOCOLOUR}"
      exit 1
    fi
  done

  for file in "${files_to_be_removed[@]}"; do
    if [ -f "$file" ]; then
      echo -e "${RED}File $file still exists, there might be containers still running. Please stop them and delete before running the script. Exiting..${NOCOLOUR}"
      echo -e "To stop and delete containers run the following command\n"
      echo -e "${YELLOW}sudo bash internetIncome.sh --delete${NOCOLOUR}\n"
      exit 1
    fi
  done

  for folder in "${folders_to_be_removed[@]}"; do
    if [ -d "$folder" ]; then
      echo -e "${RED}Folder $folder still exists, there might be containers still running. Please stop them and delete before running the script. Exiting..${NOCOLOUR}"
      echo -e "To stop and delete containers run the following command\n"
      echo -e "${YELLOW}sudo bash internetIncome.sh --delete${NOCOLOUR}\n"
      exit 1
    fi
  done

  # Remove special characters ^M from properties file
  sed -i 's/\r//g' $properties_file

  # CPU architecture to get docker images
  CPU_ARCH=`uname -m`

  # Write current PID to file
  echo "$$" > $process_id_file

  # Read the properties file and export variables to the current shell
  while IFS= read -r line; do
    # Ignore lines that start with #
    if [[ $line != '#'* ]]; then
        # Split the line at the first occurrence of =
        key="${line%%=*}"
        value="${line#*=}"
        # Trim leading and trailing whitespace from key and value
        key="${key%"${key##*[![:space:]]}"}"
        value="${value%"${value##*[![:space:]]}"}"
        # Ignore lines without a value after =
        if [[ -n $value ]]; then
            # Replace variables with their values
            value=$(eval "echo $value")
            # Export the key-value pairs as variables
            export "$key"="$value"
        fi
    fi
  done < $properties_file

  # Setting Device name
  if [[ ! $DEVICE_NAME ]]; then
    echo -e "${RED}Device Name is not configured. Using default name ${NOCOLOUR}ubuntu"
    DEVICE_NAME=ubuntu
  fi

  if [ "$USE_PROXIES" = true ]; then
    echo -e "${GREEN}USE_PROXIES is enabled, using proxies..${NOCOLOUR}"
    if [ ! -f "$proxies_file" ]; then
      echo -e "${RED}Proxies file $proxies_file does not exist, exiting..${NOCOLOUR}"
      exit 1
    fi

    # Remove special character ^M and trim space from proxies file
    sed -i 's/\r//g' $proxies_file
    sed -i 's/^[ \t]*//;s/[ \t]*$//' $proxies_file
    validate_proxies
    if idlepay_only_enabled; then
      if ! grep -qEv '^[[:space:]]*(#|$)' "$proxies_file"; then
        echo -e "${RED}No proxies configured for IdlePay. Exiting..${NOCOLOUR}"
        rm "$process_id_file"
        exit 1
      fi
      echo -e "${GREEN}Only IdlePay is enabled, using its native proxy router without tunnel containers..${NOCOLOUR}"
      start_containers
    else
      i=0;
      while IFS= read -r line || [ -n "$line" ]; do
        if [[ "$line" =~ ^[^#].* ]]; then
          i=`expr $i + 1`
          start_containers "$i" "$line"
        fi
      done < $proxies_file
    fi
  else
    echo -e "${RED}USE_PROXIES is disabled, using direct internet connection..${NOCOLOUR}"
    start_containers
  fi
  # Remove Process file
  rm $process_id_file
  exit 0
fi

# Delete containers and networks
if [[ "$1" == "--delete" ]]; then
  echo -e "\n\nDeleting Containers and networks.."
  # Check if there is already a running process
  if [ -f "$process_id_file" ]; then
    PID=$(cat "$process_id_file")
    PROC_DIR=$(pwdx "$PID" 2>/dev/null | awk '{print $2}')
    if [ "$PROC_DIR" = "$PWD" ]; then
      echo "There is already a running process (PID $PID)."
      echo "Do you want to stop it and continue? (yes/no)"
      # Prompt with 60-second timeout
      read -r -t 60 ANSWER
      if [ $? -ne 0 ]; then
        echo "No response within 60 seconds. Exiting."
        exit 1
      fi
      case "$ANSWER" in
        yes|y|Y)
          echo "Stopping process $PID..."
          kill "$PID" 2>/dev/null
          sleep 2
          rm -f "$process_id_file"
          echo "Process stopped. Continuing..."
          ;;
        no|n|N)
          echo "Operation cancelled."
          exit 1
          ;;
        *)
          echo "Invalid response. Exiting."
          exit 1
          ;;
      esac
    fi
  fi

  # Delete containers by container names
  if [ -f "$container_names_file" ]; then
    for i in `cat $container_names_file`; do
      sudo docker rm -f $i
    done
    # Delete the container file
    rm $container_names_file
  fi

  # Delete networks
  if [ -f "$networks_file" ]; then
    for i in `cat $networks_file`; do
      sudo docker network rm $i
    done
    # Delete network file
    rm $networks_file
  fi

  # Delete files
  for file in "${files_to_be_removed[@]}"; do
    if [ -f "$file" ]; then
      rm $file
    fi
  done

  # Delete files for Docker-in-Docker
  sudo docker run --rm --mount type=bind,source="$PWD",target=/output docker:cli sh -c 'for file in "$@"; do if [ -f "/output/$file" ]; then rm "/output/$file"; fi; done' sh "${files_to_be_removed[@]}"

  # Delete folders
  folders_to_be_removed+=("${files_to_be_removed[@]}")
  for folder in "${folders_to_be_removed[@]}"; do
    if [ -d "$folder" ]; then
      rm -Rf $folder;
    fi
  done

  # Delete folders for Docker-in-Docker
  sudo docker run --rm --mount type=bind,source="$PWD",target=/output docker:cli sh -c 'for folder in "$@"; do if [ -d "/output/$folder" ]; then rm -rf "/output/$folder"; fi; done' sh "${folders_to_be_removed[@]}"

  # Delete stale containers using deleted parent network (network_mode: container:<parent> where parent no longer exists)
  echo -e "${YELLOW}Checking for stale containers...${NOCOLOUR}"
  declare -A existing
  declare -A container_data  # cid -> "name status netmode image"
  stale_cids=()
  # Single docker inspect call — add --type container to skip images/networks
  while read -r cid cname status netmode image; do
    cname="${cname#/}"
    existing["$cid"]=1
    existing["$cname"]=1
    container_data["$cid"]="$cname $status $netmode $image"
  done < <(sudo docker inspect --type container $(sudo docker ps -aq) --format '{{.Id}} {{.Name}} {{.State.Status}} {{.HostConfig.NetworkMode}} {{.Config.Image}}' 2>/dev/null)

  # Single pass — identify stale containers first, no deletion yet
  for cid in "${!container_data[@]}"; do
    read -r cname status netmode image <<< "${container_data[$cid]}"
    # Only process containers with network mode referencing another container
    [[ "$netmode" != container:* ]] && continue
    parent="${netmode#container:}"
    if [[ -z "${existing[$parent]}" ]]; then
      stale_cids+=("$cid")
    fi
  done

  if [ ${#stale_cids[@]} -eq 0 ]; then
    echo -e "${GREEN}No stale containers found.${NOCOLOUR}"
  else
    echo -e "${YELLOW}The following stale containers were found (parent network container no longer exists):${NOCOLOUR}"
    for cid in "${stale_cids[@]}"; do
      read -r cname status netmode image <<< "${container_data[$cid]}"
      echo -e "${YELLOW}  Name:${NOCOLOUR} $cname (${status})"
      echo -e "${YELLOW}  Network Mode:${NOCOLOUR} $netmode"
      echo -e "${YELLOW}  Image:${NOCOLOUR} $image"
    done
    echo -e "${YELLOW}Do you want to delete these stale containers? (yes/no)${NOCOLOUR}"
    read -r -t 60 CHOICE </dev/tty
    if [ $? -ne 0 ]; then
      echo -e "${RED}No response within 60 seconds. Skipping stale container deletion.${NOCOLOUR}"
    else
      case "$CHOICE" in
        yes|y|Y)
          echo -e "${YELLOW}Deleting stale containers. This may take a few minutes...${NOCOLOUR}"
          for cid in "${stale_cids[@]}"; do
            read -r cname status netmode image <<< "${container_data[$cid]}"
            echo -e "${YELLOW}Removing stale container:${NOCOLOUR} $cname ($status)"
            sudo docker rm -f "$cname"
          done
          echo -e "${GREEN}Stale container deletion completed successfully.${NOCOLOUR}"
          ;;
        no|n|N)
          echo -e "${YELLOW}Skipping stale container deletion.${NOCOLOUR}"
          ;;
        *)
          echo -e "${RED}Invalid response. Skipping stale container deletion.${NOCOLOUR}"
          ;;
      esac
    fi
  fi
  exit 0
fi

# Delete backup files and folders
if [[ "$1" == "--deleteBackup" ]]; then
  echo -e "\n\nDeleting backup folders and files.."

  # Check if previous files exist
  for file in "${files_to_be_removed[@]}"; do
    if [ -f "$file" ]; then
      echo -e "${RED}File $file still exists, there might be containers still running. Please stop them and delete before running the script. Exiting..${NOCOLOUR}"
      echo -e "To stop and delete containers run the following command\n"
      echo -e "${YELLOW}sudo bash internetIncome.sh --delete${NOCOLOUR}\n"
      exit 1
    fi
  done

  # Check if previous folders exist
  for folder in "${folders_to_be_removed[@]}"; do
    if [ -d "$folder" ]; then
      echo -e "${RED}Folder $folder still exists, there might be containers still running. Please stop them and delete before running the script. Exiting..${NOCOLOUR}"
      echo -e "To stop and delete containers run the following command\n"
      echo -e "${YELLOW}sudo bash internetIncome.sh --delete${NOCOLOUR}\n"
      exit 1
    fi
  done

  # Delete backup files
  for file in "${back_up_files[@]}"; do
    if [ -f "$file" ]; then
      rm $file
    fi
  done

  # Delete backup files for Docker-in-Docker
  sudo docker run --rm --mount type=bind,source="$PWD",target=/output docker:cli sh -c 'for file in "$@"; do if [ -f "/output/$file" ]; then rm "/output/$file"; fi; done' sh "${back_up_files[@]}"

  # Delete backup folders
  back_up_folders+=("${back_up_files[@]}")
  for folder in "${back_up_folders[@]}"; do
    if [ -d "$folder" ]; then
      rm -Rf $folder;
    fi
  done

  # Delete backup folders for Docker-in-Docker
  sudo docker run --rm --mount type=bind,source="$PWD",target=/output docker:cli sh -c 'for folder in "$@"; do if [ -d "/output/$folder" ]; then rm -rf "/output/$folder"; fi; done' sh "${back_up_folders[@]}"
  exit 0
fi

echo -e "Valid options are: ${RED}--start${NOCOLOUR}, ${RED}--delete${NOCOLOUR}, ${RED}--deleteBackup${NOCOLOUR}"
