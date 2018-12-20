#!/bin/bash

set -e
set -o pipefail

config_keepalived() {
  if ! compgen -A variable | grep -q -E 'KEEPALIVED_VIRTUAL_IPADDRESS_[0-9]{1,3}'; then
    echo "[$(date)][KEEPALIVED] No KEEPALIVED_VIRTUAL_IPADDRESS_ varibles detected."
    return 1
  fi

  KEEPALIVED_STATE=${KEEPALIVED_STATE:-MASTER}

  if [[ "${KEEPALIVED_STATE^^}" == 'MASTER' ]]; then
    KEEPALIVED_PRIORITY=${KEEPALIVED_PRIORITY:-200}
  elif [[ "${KEEPALIVED_STATE^^}" == 'BACKUP' ]]; then
    KEEPALIVED_PRIORITY=${KEEPALIVED_PRIORITY:-100}
  fi

  KEEPALIVED_INTERFACE=${KEEPALIVED_INTERFACE:-eth0}
  KEEPALIVED_VIRTUAL_ROUTER_ID=${KEEPALIVED_VIRTUAL_ROUTER_ID:-1}
  KEEPALIVED_ADVERT_INT=${KEEPALIVED_ADVERT_INT:-1}
  KEEPALIVED_AUTH_PASS=${KEEPALIVED_AUTH_PASS:-"pwd$KEEPALIVED_VIRTUAL_ROUTER_ID"}

  if [[ ! $KEEPALIVED_UNICAST_SRC_IP ]]; then
    bind_target="$(ip addr show "$KEEPALIVED_INTERFACE" | \
      grep -m 1 -E -o 'inet [0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | awk '{print $2}')"
    KEEPALIVED_UNICAST_SRC_IP="$bind_target"
  fi

  {
    echo 'global_defs {'
    echo 'router_id LVS_MAIN'
    echo '}'
  } > "$KEEPALIVED_CONF"

  if [[ ${KEEPALIVED_KUBE_APISERVER_CHECK,,} == 'true' ]]; then
    # if no address supplied, assume its the first (or only) VIP
    if [[ ! $KUBE_APISERVER_ADDRESS ]]; then
      kube_api_vip="$(compgen -A variable | grep -E 'KEEPALIVED_VIRTUAL_IPADDRESS_[0-9]{1,3}' | head -1)"
      KUBE_APISERVER_ADDRESS="$(echo "${!kube_api_vip}" | grep -o -E '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}')"
    fi
    KUBE_APISERVER_PORT=${KUBE_APISERVER_PORT:-6443}
    KUBE_APISERVER_CHK_INTERVAL=${KUBE_APISERVER_CHK_INTERVAL:-'3'}
    KUBE_APISERVER_CHK_WEIGHT=${KUBE_APISERVER_CHK_WEIGHT:-'-50'}
    KUBE_APISERVER_CHK_FALL=${KUBE_APISERVER_CHK_FALL:-'10'}
    KUBE_APISERVER_CHK_RISE=${KUBE_APISERVER_CHK_RISE:-'2'}
    {
      echo 'vrrp_script chk_kube_apiserver {'
      echo "  script \"/usr/lib/keepalived/scripts/chk_kube_apiserver.sh $KUBE_APISERVER_ADDRESS $KUBE_APISERVER_PORT\""
      echo "  interval $KUBE_APISERVER_CHK_INTERVAL"
      echo "  fall $KUBE_APISERVER_CHK_FALL"
      echo "  rise $KUBE_APISERVER_CHK_RISE"
      echo "  weight $KUBE_APISERVER_CHK_WEIGHT"
      echo '}'
    } >> "$KEEPALIVED_CONF"
  fi

  {
    echo 'vrrp_instance MAIN {'
    echo "  state $KEEPALIVED_STATE"
    echo "  interface $KEEPALIVED_INTERFACE"
    echo "  virtual_router_id $KEEPALIVED_VIRTUAL_ROUTER_ID"
    echo "  priority $KEEPALIVED_PRIORITY"
    echo "  advert_int $KEEPALIVED_ADVERT_INT"
    echo "  unicast_src_ip $KEEPALIVED_UNICAST_SRC_IP"
    echo '  unicast_peer {'
  } >> "$KEEPALIVED_CONF"
  for peer in $(compgen -A variable | grep -E "KEEPALIVED_UNICAST_PEER_[0-9]{1,3}"); do
    echo "    ${!peer}" >> "$KEEPALIVED_CONF"
  done
  {
    echo '  }'
    echo '  authentication {'
    echo '    auth_type PASS'
    echo "    auth_pass $KEEPALIVED_AUTH_PASS"
    echo '  }'
    echo '  virtual_ipaddress {'
  }  >> "$KEEPALIVED_CONF"
  for vip in $(compgen -A variable | grep -E 'KEEPALIVED_VIRTUAL_IPADDRESS_[0-9]{1,3}'); do
    echo "    ${!vip}" >> "$KEEPALIVED_CONF"
  done
  echo '  }' >> "$KEEPALIVED_CONF"

  if compgen -A variable | grep -q -E 'KEEPALIVED_VIRTUAL_IPADDRESS_EXCLUDED_[0-9]{1,3}'; then
    echo '  virtual_ipaddress_excluded {' >> "$KEEPALIVED_CONF"
    for evip in $(compgen -A variable | grep -E 'KEEPALIVED_VIRTUAL_IPADDRESS_EXCLUDED_[0-9]{1,3}'); do
      echo "    ${!evip}" >> "$KEEPALIVED_CONF"
    done
    echo '  }' >> "$KEEPALIVED_CONF"
  fi

  if compgen -A variable | grep -q -E 'KEEPALIVED_TRACK_INTERFACE_[0-9]{1,3}'; then
    echo '  track_interface {' >> "$KEEPALIVED_CONF"
    for interface in $(compgen -A variable | grep -E 'KEEPALIVED_TRACK_INTERFACE_[0-9]{1,3}'); do
      echo "    ${!interface}" >> "$KEEPALIVED_CONF"
    done
    echo '  }' >> "$KEEPALIVED_CONF"
  else
    {
      echo '  track_interface {'
      echo "    $KEEPALIVED_INTERFACE"
      echo '}'
    } >> "$KEEPALIVED_CONF"
 fi
 if [[ ${KEEPALIVED_KUBE_APISERVER_CHECK,,} == 'true' ]]; then
   {
     echo '  track_script {'
     echo '    chk_kube_apiserver'
     echo '  }'
   } >> "$KEEPALIVED_CONF"
 fi

  echo '}' >> "$KEEPALIVED_CONF"

  return 0
}

init_vars() {
  KEEPALIVED_AUTOCONF=${KEEPALIVED_AUTOCONF:-true}
  KEEPALIVED_DEBUG=${KEEPALIVED_DEBUG:-false}
  KEEPALIVED_KUBE_APISERVER_CHECK=${KEEPALIVED_KUBE_APISERVER_CHECK:-false}
  KEEPALIVED_CONF=${KEEPALIVED_CONF:-/etc/keepalived/keepalived.conf}
  KEEPALIVED_VAR_RUN=${KEEPALIVED_VAR_RUN:-/var/run/keepalived}
  if [[ ${KEEPALIVED_DEBUG,,} == 'true' ]]; then
    local kd_cmd="/usr/sbin/keepalived -n -l -D -f $KEEPALIVED_CONF"
  else
    local kd_cmd="/usr/sbin/keepalived -n -l -f $KEEPALIVED_CONF"
  fi
  KEEPALIVED_CMD=${KEEPALIVED_CMD:-"$kd_cmd"}
}

main() {
  init_vars
  if [[ ${KEEPALIVED_AUTOCONF,,} == 'true' ]]; then
    config_keepalived
  fi
  rm -fr "$KEEPALIVED_VAR_RUN"
  # shellcheck disable=SC2086
  exec $KEEPALIVED_CMD
}

main
