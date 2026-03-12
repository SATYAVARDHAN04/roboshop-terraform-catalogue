#! /bin/bash
dnf install ansible -y
ansible-pull -U https://github.com/SATYAVARDHAN04/ansible-roles-roboshop-tf.git -e component=$1 -e env=$2 main.yaml