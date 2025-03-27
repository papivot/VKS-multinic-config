#!/bin/bash

NETWORK_NAME="Workload1-VDS-PG"
NETWORK_SWITCH="Pacific-VDS"
MAX_RETRIES=12
RETRY_INTERVAL=10
MANIFEST_FILE="/etc/kubernetes/manifests/kube-apiserver.yaml"
PROCESS_NAME="kube-apiserver"
NUM_NIC=""
NEW_NIC=""
CONFIGURE_NODE_IP_DHCP=0 # Set 1 to configure Node IP with DHCP. 
LOG_FILE="/tmp/nic-request.log"

# Wait for the new NIC to appear
check_new_nic() {
#    ORIG_NUM_NIC=$(ip -o link show | awk -F': ' '{print $2}' | grep -Ec '^ens|^eth')
    for ((i=1; i<=MAX_RETRIES; i++)); do
        NUM_NIC=$(ip -o link show | awk -F': ' '{print $2}' | grep -Ec '^ens|^eth')
        echo "Found ${NUM_NIC}" | tee -a "${LOG_FILE}"  
        if [ "${NUM_NIC}" == "2" ]; then
            NEW_NIC=$(ip -o link show | awk -F': ' '{print $2}' | grep -E '^ens|^eth' | tail -n 1)
            if [ -n "${NEW_NIC}" ]; then
                echo "New network interface detected: ${NEW_NIC}" | tee -a "${LOG_FILE}"
                break
            fi
        fi
        echo "Waiting for NIC to appear... ($i/$MAX_RETRIES)" | tee -a "${LOG_FILE}"
        sleep $RETRY_INTERVAL
    done
    if [[ -z "$NEW_NIC" ]]; then
        echo "NIC did not appear within the expected time." | tee -a "${LOG_FILE}"
        exit 1
    fi
}

# Function to configure the new NIC with DHCP.
# Parameters: None (uses global variables for configuration)
configure_new_nic_with_ip() {
    echo "Configuring ${NEW_NIC} with DHCP..." | tee -a "${LOG_FILE}"
    OS_NAME=$(grep ^NAME /etc/os-release | cut -d'=' -f2 | tr -d '"')

    # Configure the new NIC
    if [[ "$OS_NAME" == *"Photon"* ]]; then
        echo "Found Photon OS. Configuring $NEW_NIC with DHCP..." | tee -a "${LOG_FILE}"
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
    elif [[ "$OS_NAME" == "Ubuntu" ]]; then
        # Ubuntu with netplan
        echo "Found Ubuntu OS. Configuring $NEW_NIC with DHCP using netplan..." | tee -a "${LOG_FILE}"
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
        echo "Unsupported Linux distribution. Supported distributions are Photon and Ubuntu." | tee -a "${LOG_FILE}"
        exit 1
    fi

    echo "NIC $NEW_NIC configured successfully." | tee -a "${LOG_FILE}"
}

#### MAIN ####

# Check if running on a Control Plane node
if [[ -f "${MANIFEST_FILE}" ]]; then
    echo "kube-apiserver Manifest file found. Waiting for kube-apiserver to start..." | tee -a "${LOG_FILE}"

    # Wait until kube-apiserver is running
    while ! ps aux | grep "${PROCESS_NAME}" | grep -v grep > /dev/null; do
        echo "kube-apiserver is not running. Retrying in 30 seconds..." | tee -a "${LOG_FILE}"
        sleep 30
    done
    echo "kube-apiserver is running. Proceeding with execution..." | tee -a "${LOG_FILE}"
else
    echo "Manifest file not found. Proceeding with execution..." | tee -a "${LOG_FILE}"
fi

# Request to add a new network interface
vmtoolsd --cmd "info-set guestinfo.request_nic_add 1"
# Set the port group for the new network interface
vmtoolsd --cmd "info-set guestinfo.request_nic_pg ${NETWORK_NAME}"
# Set the virtual switch for the new network interface
vmtoolsd --cmd "info-set guestinfo.request_nic_switch ${NETWORK_SWITCH}"

# Check if a new NIC has been added by the Supervisor Service.
check_new_nic || exit 1
echo "New NIC detected: $NEW_NIC" | tee -a "${LOG_FILE}"

# If the flag is set, configure the VM with an IP address. Else, let Antrea use the NIC for SecondaryNetwork. 
if [ "$CONFIGURE_NODE_IP_DHCP" -eq 1 ]; then
    configure_new_nic_with_ip || exit 1
    echo "NIC $NEW_NIC configured." | tee -a "${LOG_FILE}"
fi

# Indicate that the NIC addition process is complete
vmtoolsd --cmd "info-set guestinfo.request_nic_add 0"