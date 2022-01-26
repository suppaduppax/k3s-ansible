# Build a Kubernetes cluster using k3s via Ansible in VMWare vCenter

Original Author: <https://github.com/itwars0> \
Adapted by: <https://github.com/suppaduppax>

## K3s Ansible Playbook

Build a Kubernetes cluster using Ansible with k3s. The goal is easily install a Kubernetes cluster on machines running:

- [X] Debian
- [X] Ubuntu
- [X] CentOS

on processor architecture:

- [X] x64
- [X] arm64
- [X] armhf

Easily spin up virtual machines to add k3s servers and nodes on your VMWare vCenter managed datacenter.

## System requirements

Deployment environment must have Ansible 2.4.0+
Master and nodes must have passwordless SSH access

## Usage

First create a new directory based on the `sample` directory within the `inventory` directory:

```bash
cp -R inventory/sample inventory/my-cluster
```

Second, edit `inventory/my-cluster/hosts` to match the system information gathered above. For example:

```bash
all:
  hosts:
    localhost:
      # uncomment if using a python virtual environment. Set 'venv' folder to match your setup
      # ansible_python_interpreter: "{{ playbook_dir }}/venv/bin/python3"

  children:
    vcenter_template:
      vars:
        # place common variables inside parent group to redundant variable definitions on each host
        esxi_hostname: "michael.home"
        vm_iso: "[isos] os/debian-bullseye-faime.iso"
        vm_datastore: michael-ssd-intel-01
        vm_os: debian10_64Guest
        vm_disk_type: thin
        vm_state: poweredon
        vm_scsi: paravirtual
        vm_network: VM Network

      hosts:
        # hostnames of templates will match vm names in vcenter
        k3s-server-template:
          vm_name: "k3s-server-template"
          vm_num_cpus: 2
          vm_memory_mb: 2048
          vm_disk_size_gb: 16

        k3s-agent-template:
          vm_name: "k3s-agent-template"
          vm_num_cpus: 2
          vm_memory_mb: 2048
          vm_disk_size_gb: 16

    loadbalancer:
      # nginx loadbalancer setup
      hosts:
        k3s-loadbalancer:
          vm_template: k3s-agent-template
          ip: 192.168.0.245/24
          esxi_hostname: michael.home
          datastore: michael-ssd-intel-01
          reverse_proxy:
            - name: k3s_http_upstream
              port: 80
            - name: k3s_https_upstream
              port: 443

    k3s_cluster:
      children:
        master:
          vars:
            # all master nodes will clone k3s-server-template. set vm_template in individual hosts if 
            # you want some hosts to use a different template
            vm_template: k3s-server-template
            taint: True

          hosts:
            k3s-server-01:
              ip: 192.168.0.230/24                  # the ip address you want to assign to the server
              esxi_hostname: michael.home           # the esxi host you want to assign this vm to
              datastore: michael-ssd-intel-01       # the datastore you want to create this vm in

            k3s-server-03:
              ip: 192.168.0.232/24
              esxi_hostname: michael.home
              datastore: michael-ssd-intel-01

            k3s-server-02:
              ip: 192.168.0.231/24
              esxi_hostname: eleanor.home
              datastore: eleanor-ssd-intel-01

        node:
          vars:
            vm_template: k3s-agent-template

          hosts:
            k3s-agent-01:
              ip: 192.168.0.235/24
              esxi_hostname: michael.home
              datastore: michael-ssd-intel-01

            k3s-agent-02:
              ip: 192.168.0.236/24
              esxi_hostname: michael.home
              datastore: michael-ssd-intel-01

            k3s-agent-03:
              ip: 192.168.0.237/24
              esxi_hostname: eleanor.home
              datastore: eleanor-ssd-intel-01
```

If you want to have a less populated hosts file, you can set these variables as directories in your inventory under `inventory/group_vars/<group_name>` and `inventory/host_vars/<host_name>`. Being able to see all the node settings at a glance however, may be more useful.

If needed, you can also edit `inventory/my-cluster/group_vars/all.yml` to match your environment.
You can use this sample inventory:
plugin: vmware_vm_inventory
strict: False
hostname: photon-machine.home
username: administrator@vsphere.local
password: MySecretPassword123
validate_certs: False
with_tags: True
hostnames:
  # sets the hostname to the simple name of the host without the extra identifiers attached to the end of it
  - config.name

# this compose definition is necessary for when vCenter has trouble finding the correct ipAddress in k3s servers due to the extra network interfaces
# that are created for k3s. This finds the interface assigned with the default 'VM Network' in vCenter and gets its ipv4 address. Edit the 'VM Network'
# match to suit your environment
compose:
  ansible_host: "(guest.net | selectattr('network', 'match', 'VM Network') | first ) ['ipAddress'] | select('search', '[0-9]+[.][0-9]+[.][0-9]+[.][0-9]+') | first"

resources:
  - resources:
      - folder:
          # the vcenter folder to store the vms in
          - "ansible-managed"

# since we need 'guest.net' as a property, we need to define the rest of the default properties as well
properties:
  - "name"
  - "config.cpuHotAddEnabled"
  - "config.cpuHotRemoveEnabled"
  - "config.instanceUuid"
  - "config.hardware.numCPU"
  - "config.template"
  - "config.name"
  - "config.uuid"
  - "guest.net"
  - "guest.hostName"
  - "guest.ipAddress"
  - "guest.guestId"
  - "guest.guestState"
  - "runtime.maxMemoryUsage"
  - "customValue"
  - "summary.runtime.powerState"
  - "config.guestId"
```

## Prepare you vmware dynamic inventory file.
In the `inventory/my-cluster` directory, create a the vmware dynamic inventory file `hosts.vmware.yml`
<br>
<br>

> For an automated install run the deployment script. This script is prone to errors due to slow vmware-tools syncing and may have to be run several times to complete installation.
```bash
deploy_k3s.sh
```
<br>
<br>

> For a more consistent installation, run each playbook separately.

First create the templates. *** iso file should be a fully automated installer (see <https://fai-project.org> for a fully automated Debian install)
```bash
ansible-playbook create_templates.yml
```

Wait a moment for the templates to complete their installation. This could take several minutes. \
Next, create the virtual machine nodes which will clone the templates you just created.
```bash
ansible-playbook create_vms.yml
```

Wait a couple minutes for each node to update their ips on vcenter. If the following fails, wait a few more minutes, then re-run.
Provision the newly created nodes, which will set the ip and hostname of each node.
```bash
ansible-playbook provision_nodes.yml
```

The ips will now need to be refreshed on vcenter which could take another few minutes. Once again, re-run if errors occur.
Install the external nginx loadbalancer.
```bash
ansible-playbook install_loadbalancer.yml
```

Finally, start provisioning of the cluster using the following command:
```bash
ansible-playbook site.yml
```
Again, if that fails, re-run.

## Kubeconfig

To get access to your **Kubernetes** cluster just

```bash
scp debian@master_ip:~/.kube/config ~/.kube/config
```

## Snapshots

Once k3s has finished deploying, it recommended to create a snapshot for easy recovery.
```bash
ansible-playbook create_snapshot.yml
```

To restore to the latest snapshot, run:
```bash
ansible-playbook restore_snapshot.yml
```

## Other playbooks

Here is a list of other playbooks in this repo and a brief description of its use.
In most cases, you can use -e limit=<host_name> to target a specific host if the playbook
targets localhost. In other cases you must use -l for host target limiting.


playbook | description
---|---
delete_nodes.yml   | Delete the vms associated with this k3s deployment in vcenter.
list_snapshots.yml | List all the snapshots of the cluster/loadbalancer.
poweron_nodes.yml  | Power on all nodes. 
poweroff_nodes.yml | Power off all nodes.
