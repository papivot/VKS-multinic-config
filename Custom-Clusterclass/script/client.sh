#!/bin/bash

NETWORK_NAME="Workload1-VDS-PG"
NETWORK_SWITCH="Pacific-VDS"
MAX_RETRIES=20
RETRY_INTERVAL=6
ORIG_NUM_NIC=""
NUM_NIC=""
NEW_NIC=""

# Wait for the new NIC to appear
check_new_nic() {
    ORIG_NUM_NIC=$(ip -o link show | awk -F': ' '{print $2}' | grep -Ec '^ens|^eth')
    for ((i=1; i<=MAX_RETRIES; i++)); do
        NUM_NIC=$(ip -o link show | awk -F': ' '{print $2}' | grep -Ec '^ens|^eth')
        if [ "${NUM_NIC}" != "${ORIG_NUM_NIC}" ]; then
            NEW_NIC=$(ip -o link show | awk -F': ' '{print $2}' | grep -E '^ens|^eth' | tail -n 1)
            if [ -n "${NEW_NIC}" ]; then
                echo "New network interface detected: $NEW_NIC"
                break
            fi
        fi
        echo "Waiting for NIC to appear... ($i/$MAX_RETRIES)"
        sleep $RETRY_INTERVAL
    done
    if [[ -z "$NEW_NIC" ]]; then
        echo "NIC did not appear within the expected time."
        exit 1
    fi
}

# Function to configure the new NIC with DHCP.
# Parameters: None (uses global variables for configuration)
configure_new_nic_with_ip() {
    echo "Configuring $NEW_NIC with DHCP..."

    # Configure the new NIC
    if [ -d /etc/systemd/network ]; then
    # Photon
cat <<EOF | sudo tee -a /etc/systemd/network/20-dhcp-"$NEW_NIC".network
[Address]

[Match]
Name="$NEW_NIC"

[Network]
DHCP=yes
EOF
        sudo chown systemd-network:systemd-network /etc/systemd/network/20-dhcp-"$NEW_NIC".network
        sudo systemctl restart systemd-networkd
    elif [ -d /etc/sysconfig/network-scripts ]; then
        # RHEL/CentOS/Fedora (just in case)
cat <<EOF | sudo tee /etc/sysconfig/network-scripts/ifcfg-"$NEW_NIC"
DEVICE=$NEW_NIC
BOOTPROTO=dhcp
ONBOOT=yes
EOF
        sudo systemctl restart network
    elif [ -d /etc/netplan ]; then
        # Ubuntu with netplan
        NETPLAN_FILE="/etc/netplan/02-netcfg.yaml"

cat <<EOF | sudo tee -a $NETPLAN_FILE
network:
    version: 2
    ethernets:
        $NEW_NIC:
            dhcp4: true
            dhcp4-overrides:
                route-metric: 200
EOF
        sudo chmod 600 $NETPLAN_FILE
        sudo netplan apply
    else
        echo "Unsupported Linux distribution. Supported distributions are Photon, RHEL/CentOS/Fedora, and Ubuntu."
        exit 1
    fi

    echo "NIC $NEW_NIC configured successfully."
}

# Request to add a new network interface
vmtoolsd --cmd "info-set guestinfo.request_nic_add 1"
# Set the port group for the new network interface
vmtoolsd --cmd "info-set guestinfo.request_nic_pg ${NETWORK_NAME}"
# Set the virtual switch for the new network interface
vmtoolsd --cmd "info-set guestinfo.request_nic_switch ${NETWORK_SWITCH}"

check_new_nic || exit 1
echo "New NIC detected: $NEW_NIC"

configure_new_nic_with_ip || exit 1
echo "NIC $NEW_NIC configured."

# Indicate that the NIC addition process is complete
vmtoolsd --cmd "info-set guestinfo.request_nic_add 0"