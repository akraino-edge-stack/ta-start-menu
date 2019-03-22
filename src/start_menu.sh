#!/bin/bash

# Copyright 2019 Nokia

# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

DEFAULT_WIDTH=120
DEFAULT_HEIGHT=40

USER_CONFIG_FILE=/etc/userconfig/user_config.yaml
LOG_DIR=/var/log/start-menu
RC_FILE=/tmp/start_menu.rc
DEBUG_FLAG=/opt/start-menu/config/__debug

function ask_for_device()
{
  device=$1
  shift 1

  declare -a devices
  devices=($(ls /sys/class/net))
  radiolist=""
  if [ -z "$device" ]; then
    device=${devices[0]}
  fi
  for dev in ${devices[*]}; do
    if [ "$dev" != "lo" ]; then
      mac=$(cat /sys/class/net/$dev/address)
      if [ "$dev" == "$device" ]; then
        status="on"
      else
        status="off"
      fi
      radiolist="${radiolist}$dev $mac $status "
    fi
  done
  device=$(dialog --clear --stdout --no-cancel --radiolist "Select network device:" 0 $DEFAULT_WIDTH 10 $radiolist)
  RC=$?
  if [ "$RC" -eq 0 ]; then
    echo $device
  fi

  return $RC
}

function ask_for_ip()
{
  device=$1
  address=$2

  rc=1
  while [ "$rc" -ne 0 ]; do
    address=$(dialog --clear --stdout --inputbox "Enter IP address for $device (CIDR format):" 0 $DEFAULT_WIDTH $address)
    if [ "$?" -ne 0 ]; then
      return 1
    fi

    if [ -z "$address" ]; then
      dialog --clear --stdout --msgbox "No address entered" 0 0
    else
      # check if valid address
      err=$(ipcalc -c $address 2>&1)
      rc=$?
      if [ "$rc" -ne 0 ]; then
        dialog --clear --stdout --msgbox "$err" 0 0
      else
        # check if network address (prefix given)
        if [[ $address != */* ]]; then
          dialog --clear --stdout --msgbox "No CIDR prefix given" 0 0
        fi
      fi
    fi
  done

  echo $address

  return 0
}

function ask_for_gateway()
{
  device=$1
  gateway=$2

  rc=1
  while [ "$rc" -ne 0 ]; do
    gateway=$(dialog --clear --stdout --inputbox "Enter gateway address for $device:" 0 $DEFAULT_WIDTH $gateway)
    if [ "$?" -ne 0 ]; then
      return 1
    fi

    if [ -z "$gateway" ]; then
      dialog --clear --stdout --msgbox "No address entered" 0 0
    else
      err=$(ipcalc -c $gateway 2>&1)
      rc=$?
      if [ "$rc" -ne 0 ]; then
        dialog --clear --stdout --msgbox "$err" 0 0
      fi
    fi
  done

  echo $gateway

  return 0
}

function ask_for_vlan()
{
  device=$1
  vlanid=$2

  rc=255
  while [ "$rc" -eq 255 ]; do
    dialog --clear --stdout --yesno "Set VLAN for $device?" 0 0
    rc=$?
    if [ "$rc" -eq 0 ]; then
      id_rc=1
      while [ "$id_rc" -ne 0 ]; do
        vlanid=$(dialog --clear --stdout --inputbox "Enter VLAN ID:" 0 $DEFAULT_WIDTH $vlanid)
        id_rc=$?
        if [ "$id_rc" -eq 255 ]; then
          return 1
        fi
      done
    fi
  done

  echo $vlanid
}

function wait_for_gateway()
{
  GATEWAY=$1
  for i in {1..180}; do
    echo "$(date)"
    if [[ $GATEWAY = *:* ]]; then
        ping -6 -w 1 -c 1 $GATEWAY
    else
        ping -w 1 -c 1 $GATEWAY
    fi
    if [ "$?" -eq 0 ]; then
      echo -e "\nping to network gateway OK.\n"
      return 0
    else
      sleep 1
    fi
  done

  echo -e "\nping to network gateway failed."

  if [ "$vlanid" != "" ] ; then
    ip link delete vlan$vlanid
    rm -f /etc/sysconfig/network-scripts/*vlan$vlanid*
  else
    ip a delete $address dev $device
    rm -f /etc/sysconfig/network-scripts/*$device*
  fi
  ip link set $device down
  dialog --colors --stdout --clear --cr-wrap --title "ERROR" \
         --msgbox '\n\Z1 Can not ping gateway! \n Shut down link!' 8 29
}

function run_external_network_create_command()
{
  local if_status
  local max_retries
  local i

  echo -e "Creating external network."
  echo -e " Device : $device"
  echo -e "Address : $address"
  echo -e "Gateway : $gateway"
  [ -z "$vlanid" ] || echo -e " VlanId : $vlanid"

  mkdir -p /etc/os-net-config/
  if [[ $gateway = *:* ]]; then
    defaultroute=::/0
  else
    defaultroute=0.0.0.0/0
  fi
  if [ "$vlanid" != "" ]; then
    sed  "s|PHYDEV|${device}|g;s|VLANID|${vlanid}|g;s|IPADDR|${address}|g;s|DEFAULTROUTE|${defaultroute}|g;s|GATEWAY|${gateway}|g" os_net_config_vlan_template.yml > /etc/os-net-config/config.yaml
  else
    sed  "s|PHYDEV|${device}|g;s|IPADDR|${address}|g;s|DEFAULTROUTE|${defaultroute}|g;s|GATEWAY|${gateway}|g" os_net_config_template.yml > /etc/os-net-config/config.yaml
  fi

  /bin/os-net-config
  rm -rf /etc/os-net-config/config.yaml

  max_retries=180
  i=0
  while [ $i -lt $max_retries ]; do
    echo "Waiting for interface ${device} to come up..."
    if_status="$(cat /sys/class/net/${device}/operstate)"
    [ "$if_status" = "up" ] && break
    sleep 1;
    i=$((i+1))
  done
  echo "Link status of interface $device : $if_status"
  [ "$if_status" != "up" ] && \
    dialog --colors --stdout --clear --cr-wrap --title "ERROR" --msgbox '\n\Z1 Link does not come up!' 8 29
}

function set_external_network()
{
  device=$1
  address=$2
  gateway=$3
  vlanid=$4
  shift 4

  device=$(ask_for_device "$device")
  if [ "$?" -ne 0 ]; then
    return 1
  fi

  address=$(ask_for_ip "$device" "$address")
  if [ "$?" -ne 0 ]; then
    return 1
  fi

  addr_no_mask=$(awk -F\/ '{print $1}' <<< "$address")

  gateway=$(ask_for_gateway "$device" "$gateway")
  if [ "$?" -ne 0 ]; then
    return 1
  fi

  vlanid=$(ask_for_vlan "$device" "$vlanid")
  if [ "$?" -ne 0 ]; then
    return 1
  fi

  # echo is an ugly hack to workaround dialog bug (ok button loses two first lines of output)
  (echo -e -n "\n\n"; run_external_network_create_command 2>&1) | tee $LOG_DIR/external_net_create.log | dialog --clear --stdout --progressbox "Setting up external network:" $DEFAULT_HEIGHT $DEFAULT_WIDTH

  # echo is an ugly hack to workaround dialog bug (ok button loses two first lines of output)
  
  (echo -e -n "\n\n"; wait_for_gateway $gateway 2>&1) | tee $LOG_DIR/wait_for_gateway.log | sed -ru "s/.{$[DEFAULT_WIDTH-4]}/&\n   /g" | dialog --clear --stdout --programbox "Verify ping to gateway:" $DEFAULT_HEIGHT $DEFAULT_WIDTH

}


function installation_start()
{
  local config_file
  config_file=${1}
  local mode
  mode=${2}
  if validate_user_config ${config_file}; then
    pushd /opt/cmframework/scripts/
    if ./bootstrap.sh ${config_file} ${mode}; then
      echo -e "################################################################################"
      echo -e "#########################  All Done!!  ########################################"
      echo -e "################################################################################"
      return 0
    else
      echo -e "Installation failed!!!"
    fi
  else
    echo -e "Validation failed!!!"
    return 1
  fi
}

function start_install()
{
  local config_file
  config_file=${1}

  (echo -e -n "\n\n";installation_start ${config_file} --install 2>&1) | tee $LOG_DIR/start_install.log
}

function validate_user_config()
{
  local config_file
  config_file=${1}
  if [ -e ${config_file} ]; then
    return 0
  else
    return 1
  fi
}

function main_menu()
{
  echo -e "Starting main menu"
  selection="0"
  while [ "$selection" != "X" ]; do
    rc=255
    while [ "$rc" -ne 0 ]; do
      rm -f /tmp/dialog.out
      selection=$(dialog --clear --stdout --no-cancel --menu "Installation" 0 0 10 \
                                        0 "Set external network" \
                                        1 "Start installation")
      rc=$?
    done
    case $selection in
      0)
        set_external_network
        ;;
      1)
        if start_install ${USER_CONFIG_FILE}; then
          echo "0" > $RC_FILE
          exit 0
        else
          /usr/bin/bash
        fi
        ;;
      *)
        ;;
    esac
  done
}

function create_config_user()
{
  mkdir -p /etc/userconfig/
  userconfig_passwd=$(python -c "import crypt, getpass, pwd; print crypt.crypt('userconfig')")
  useradd --home-dir=/etc/userconfig/ --password=$userconfig_passwd userconfig
  chown userconfig:userconfig /etc/userconfig
}

function delete_config_user()
{
  pkill -u userconfig
  userdel userconfig
}

while [[ "$(systemctl is-system-running)" == "starting" ]]; do
  echo "start-menu waiting for systemctl to finish startup..."
  sleep 10
done

clear

# disable kernel logs to console
echo 3 > /proc/sysrq-trigger
 
mkdir -p $LOG_DIR

if [ -e $DEBUG_FLAG ]; then
  logger "start-menu in debug mode"
  /usr/bin/bash
fi

if [ -e ${USER_CONFIG_FILE} ]; then
  if start_install ${USER_CONFIG_FILE}; then
    echo "Install succeeded"
    echo "0" > $RC_FILE
    exit 0
  else
    echo "Install failed, check logs ($LOG_DIR)"
    echo "1" > $RC_FILE
    /usr/bin/bash
    exit 1
  fi
else
  main_menu
fi
