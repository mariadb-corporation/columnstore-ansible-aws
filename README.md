![logo](https://raw.githubusercontent.com/mariadb-corporation/mariadb-community-columnstore-docker/master/MDB-HLogo_RGB.jpg)

## MariaDB Enterprise 10.5 / ColumnStore 1.5 Cluster

### Prerequisites:

Please install the following applications:

Required:
*   [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html)
*   [MariaDB Enterprise Token](https://customers.mariadb.com/downloads/token/)

Optional:

*   [Vagrant](https://www.vagrantup.com/downloads.html)
*   [VirtualBox](https://www.virtualbox.org/wiki/Downloads)

***If you already have these applications installed, please upgrade to the latest versions before continuing.***

### About:

This automation project will create a 3 node MariaDB cluster with the ColumnStore engine enabled as well as a MaxScale load balancer.

By customizing the included [hosts](/inventory/hosts), [ansible.cfg](ansible.cfg) and [all.yml](/inventory/group_vars/all.yml) files, you may skip the Vagrant/VirtualBox portion of this tutorial and use the Ansible playbook to provision physical servers in your own data center.

Alternatively you could use a utility like [Terraform](https://www.terraform.io/) in place of Vagrant/VirtualBox to provision hardware in a cloud environment like [AWS](https://aws.amazon.com/).

Most of the work here is being done by Ansible through the [provision.yml](/provision.yml) playbook and [Jinja2](https://docs.ansible.com/ansible/latest/user_guide/playbooks_templating.html) templating functions.

#### Storage Manager (S3 Object Store)
To use the storagemanager function of MariaDB Columnstore, you will need to edit the [all.yml](/inventory/group_vars/all.yml) and supply your S3 bucket information.

***Note: Your S3 bucket should be emptied before attempting subsequent runs of this playbook.***

#### Tested On These Boxes
Vagrant Box|Provider
---|---
bento/ubuntu-20.04|(virtualbox, 202005.21.0)
centos/7|(virtualbox, 2004.01)
centos/8|(virtualbox, 1905.1)
ubuntu/bionic64|(virtualbox, 20200702.0.0)

### Build Instructions:

Open a terminal window and clone the repository:

1.  Visit our [website](https://customers.mariadb.com/downloads/token/) and grab your enterprise token
2.  `git clone https://github.com/mariadb-corporation/columnstore-ansible.git`
3.  `cd` into the newly cloned folder
4.  Edit [all.yml](/inventory/group_vars/all.yml)
5.  Choose Infrastructure
    *   Option 1: `vagrant up` *(To use virtuabox images)*
    *   Option 2: Edit [hosts](/inventory/hosts) *(To use your existing servers)*
6.  `ansible-playbook provision.yml`

#### Vagrant SSH Access:

```
vagrant ssh pm1
```
```
vagrant ssh pm2
```
```
vagrant ssh pm3
```
```
vagrant ssh mx1
```

#### MariaDB Connection Info
Node|IP Address|Port|Username|Password|Mode
---|---|---|---|---|---
pm1|10.10.10.10|3307|admin|DemoPassword1~|Read/Write
pm2|10.10.10.11|3308|admin|DemoPassword1~|Read Only
pm3|10.10.10.12|3309|admin|DemoPassword1~|Read Only
mx1|10.10.10.20|3310|admin|DemoPassword1~|Load Balancer

## REST-API Instructions

### Format of url endpoints for REST API:

```perl
https://{server}:{port}/cmapi/{version}/{route}/{command}
```

#### Examples urls for available endpoints:

*   `https://10.10.10.10:8640/cmapi/0.4.0/cluster/status`
*   `https://10.10.10.10:8640/cmapi/0.4.0/cluster/start`
*   `https://10.10.10.10:8640/cmapi/0.4.0/cluster/shutdown`
*   `https://10.10.10.10:8640/cmapi/0.4.0/cluster/add-node`
*   `https://10.10.10.10:8640/cmapi/0.4.0/cluster/remove-node`

### Request Headers Needed:

*   'x-api-key': 'somekey123'
*   'Content-Type': 'application/json'

*Note: x-api-key can be set to any value of your choice during the first call to the server. Subsequent connections will require this same key*

### Examples using curl:

#### Get Status:
```
curl -s https://10.10.10.10:8640/cmapi/0.4.0/cluster/status --header 'Content-Type:application/json' --header 'x-api-key:somekey123' -k | jq .
```
#### Start Cluster:
```
curl -s -X PUT https://10.10.10.10:8640/cmapi/0.4.0/cluster/start --header 'Content-Type:application/json' --header 'x-api-key:somekey123' --data '{"timeout":20}' -k | jq .
```
#### Stop Cluster:
```
curl -s -X PUT https://10.10.10.10:8640/cmapi/0.4.0/cluster/shutdown --header 'Content-Type:application/json' --header 'x-api-key:somekey123' --data '{"timeout":20}' -k | jq .
```
#### Add Node:
```
curl -s -X PUT https://10.10.10.10:8640/cmapi/0.4.0/cluster/add-node --header 'Content-Type:application/json' --header 'x-api-key:somekey123' --data '{"timeout":20, "node": "10.10.10.12"}' -k | jq .
```
#### Remove Node:
```
curl -s -X PUT https://10.10.10.10:8640/cmapi/0.4.0/cluster/remove-node --header 'Content-Type:application/json' --header 'x-api-key:somekey123' --data '{"timeout":20, "node": "10.10.10.12"}' -k | jq .
```

## MaxScale GUI Info

*   url: `http://10.10.10.20:8989`
*   username: `admin`
*   password: `mariadb`
