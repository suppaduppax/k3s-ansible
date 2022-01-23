#!/bin/bash
source venv/bin/activate

echo "Deleting known_hosts file as a precaution"
rm $HOME/.ssh/known_hosts

echo "Running playbook: create_vms.yml"
ansible-playbook create_vms.yml
echo "Create vms play finished... sleeping for 30 seconds for vmware-tools to update in vcenter"
sleep 30

echo "Running playbook: provision_nodes.yml"
ansible-playbook provision_nodes.yml
echo "Provision vms play finished... sleeping for 1 min for vmware-tools to update in vcenter"
sleep 60

echo "Running playbook: install_loadbalancer.yml"
ansible-playbook install_loadbalancer.yml

echo "Running playbook: site.yml"
ansible-playbook site.yml
