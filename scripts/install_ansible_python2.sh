 #!/bin/bash -eux
sudo apt update -y
sudo apt-add-repository --yes --update ppa:ansible/ansible
sudo apt install ansible -y
