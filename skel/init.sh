#!/bin/bash

config_keepalived() {
  if ! compgen -A variable | grep -q -E "KEEPALIVED_VIRTUAL_IPADDRESS_[0-9]{1,3}"; then
    echo "[$(date)][KEEPALIVED] No KEEPALIVED_VIRTUAL_IPADDRESS_ varibles detected."
    return 1
  fi

  export KEEPALIVED_STATE=${KEEPALIVED_STATE:-MASTER}

  if [[ "${KEEPALIVED_STATE^^}" == "MASTER" ]]; then
    export KEEPALIVED_PRIORITY=${KEEPALIVED_PRIORITY:-200}
  elif [[ "${KEEPALIVED_STATE^^}" == "BACKUP" ]]; then
    export KEEPALIVED_PRIORITY=${KEEPALIVED_PRIORITY:-100}
  fi

  export KEEPALIVED_INTERFACE=${KEEPALIVED_INTERFACE:-eth0}
  export KEEPALIVED_VIRTUAL_ROUTER_ID=${KEEPALIVED_VIRTUAL_ROUTER_ID:-1}
  export KEEPALIVED_ADVERT_INT=${KEEPALIVED_ADVERT_INT:-1}
  export KEEPALIVED_AUTH_PASS=${KEEPALIVED_AUTH_PASS:-"pwd$KEEPALIVED_VIRTUAL_ROUTER_ID"}

  if [[ ! $KEEPALIVED_VRRP_UNICAST_BIND ]]; then
    bind_target="$(ip addr show "$KEEPALIVED_INTERFACE" | \
      grep -m 1 -P -o '(?<=inet )[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}')"
    export KEEPALIVED_VRRP_UNICAST_BIND="$bind_target"
  fi

  echo "vrrp_instance MAIN {" > "$KEEPALIVED_CONF"
  # shellcheck disable=SC2129
  echo "  state $KEEPALIVED_STATE" >> "$KEEPALIVED_CONF"
  echo "  interface $KEEPALIVED_INTERFACE" >> "$KEEPALIVED_CONF"
  echo "  virtual_router_id $KEEPALIVED_VIRTUAL_ROUTER_ID" >> "$KEEPALIVED_CONF"
  echo "  priority $KEEPALIVED_PRIORITY" >> "$KEEPALIVED_CONF"
  echo "  advert_int $KEEPALIVED_ADVERT_INT" >> "$KEEPALIVED_CONF"
  echo "  unicast_src_ip $KEEPALIVED_UNICAST_SRC_IP" >> "$KEEPALIVED_CONF"
  echo "  unicast_peer {" >> "$KEEPALIVED_CONF"
  for peer in $(compgen -A variable | grep -E "KEEPALIVED_UNICAST_PEER_[0-9]{1,3}"); do
    echo "    ${!peer}" >> "$KEEPALIVED_CONF"
  done
  # shellcheck disable=SC2129
  echo "  }" >> "$KEEPALIVED_CONF"
  echo "  authentication {" >> "$KEEPALIVED_CONF"
  echo "    auth_type PASS" >> "$KEEPALIVED_CONF"
  echo "    auth_pass $KEEPALIVED_AUTH_PASS" >> "$KEEPALIVED_CONF"
  echo "  }" >> "$KEEPALIVED_CONF"
  echo "  virtual_ipaddress {" >> "$KEEPALIVED_CONF"
  for vip in $(compgen -A variable | grep -E "KEEPALIVED_VIRTUAL_IPADDRESS_[0-9]{1,3}"); do
    echo "    ${!vip}" >> "$KEEPALIVED_CONF"
  done
  echo "  }" >> "$KEEPALIVED_CONF"

  if compgen -A variable | grep -q -E "KEEPALIVED_VIRTUAL_IPADDRESS_EXCLUDED_[0-9]{1,3}"; then
    echo "  virtual_ipaddress_excluded {" >> "$KEEPALIVED_CONF"
    for evip in $(compgen -A variable | grep -E "KEEPALIVED_VIRTUAL_IPADDRESS_EXCLUDED_[0-9]{1,3}"); do
      echo "    ${!evip}" >> "$KEEPALIVED_CONF"
    done
    echo "  }" >> "$KEEPALIVED_CONF"
  fi

  if compgen -A variable | grep -q -E "KEEPALIVED_TRACK_INTERFACE_[0-9]{1,3}"; then
    echo "  track_interface {" >> "$KEEPALIVED_CONF"
    for interface in $(compgen -A variable | grep -E "KEEPALIVED_TRACK_INTERFACE_[0-9]{1,3}"); do
      echo "    ${!interface}" >> "$KEEPALIVED_CONF"
    done
    echo "  }" >> "$KEEPALIVED_CONF"
  else
    # shellcheck disable=SC2129
    echo "  track_interface {" >> "$KEEPALIVED_CONF"
    echo "    $KEEPALIVED_INTERFACE" >> "$KEEPALIVED_CONF"
    echo "}" >> "$KEEPALIVED_CONF"
 fi

  echo "}" >> "$KEEPALIVED_CONF"

  return 0
}

init_vars() {
  export KEEPALIVED_AUTOCONF=${KEEPALIVED_AUTOCONF:-true}
  export KEEPALIVED_DEBUG=${KEEPALIVED_DEBUG:-false}
  export KEEPALIVED_CONF=${KEEPALIVED_CONF:-/etc/keepalived/keepalived.conf}
  if [[ ${KEEPALIVED_DEBUG,,} == 'true' ]]; then
    local kd_cmd="/usr/sbin/keepalived -n -l -D -f $KEEPALIVED_CONF"
  else
    local kd_cmd="/usr/sbin/keepalived -n -l -f $KEEPALIVED_CONF"
  fi
  export KEEPALIVED_CMD=${SERVICE_KEEPALIVED_CMD:-"$kd_cmd"}
}

main() {
  init_vars
  if [[ ${KEEPALIVED_AUTOCONF,,} == 'true' ]]; then
    config_keepalived
  fi
  # shellcheck disable=SC2086
  exec $KEEPALIVED_CMD
}

main
