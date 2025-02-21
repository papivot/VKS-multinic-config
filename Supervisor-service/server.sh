#!/bin/bash

# vCenter credentials and URL
export GOVC_INSECURE=1  # Set to 0 if using a valid certificate
env

# Infinite loop to check and add NICs
while true; do
    vms=$(kubectl get vm -A --selector cluster.x-k8s.io/cluster-name -o json|jq -r '.items[].metadata.name')
    echo "Starting the loop"
    for vm_name in ${vms}; do

        # read the extraConfig settings that have been added to the VM
        vm_info=$(govc vm.info -json -e "$vm_name")
        nic_add_request=$(echo "$vm_info" | jq -r '.virtualMachines[0].config.extraConfig[]| select(.key=="guestinfo.request_nic_add") | .value')
        nic_network=$(echo "$vm_info" | jq -r '.virtualMachines[0].config.extraConfig[] | select(.key=="guestinfo.request_nic_pg") | .value')
        nic_switch=$(echo "$vm_info" | jq -r '.virtualMachines[0].config.extraConfig[] | select(.key=="guestinfo.request_nic_switch") | .value')
        if [[ "$nic_add_request" == "1" ]]; then
            echo "NIC Add Request Detected for VM: $vm_name"
            echo "Network to add NIC to: ${nic_network:-None}"
            echo "VDS Switch to add NIC to: ${nic_switch:-None}"
            if [[ -z "$nic_network" || -z "$nic_switch" ]]; then
                echo "NIC network or switch is not set for VM: $vm_name. Skipping."
                continue
            fi
            pg_id=$(govc dvs.portgroup.info --json --pg "$nic_network" "$nic_switch" | jq -r '.port[0].portgroupKey')
            if [[ -z "${pg_id}" ]]; then
                echo "Portgroup '$nic_network' on VDS '$nic_switch' does not exist in vCenter!"
                continue
            fi
            connected_portgroup=$(govc vm.info -json "$vm_name"| jq -r '.virtualMachines[0].config.hardware.device[] | select (.backing.port.portgroupKey == "'"$pg_id"'")')
            if [[ -n "${connected_portgroup}" ]]; then
                echo "Portgroup '$nic_network' on VDS '${nic_switch}' is already connected to VM. Skipping"
                continue
            fi
            govc vm.network.add --net.adapter=vmxnet3 --net="${nic_switch}"/"${nic_network}" --vm "${vm_name}"
            govc vm.change -e guestinfo.request_nic_add=0 --vm "${vm_name}"
        else
            echo "No NIC Add Request found for VM: ${vm_name}"
        fi
    done
    sleep 60 # Sleep for 1 minutes
done