#!/bin/bash

sudo labauto ansible
ansible-pull -i localhost, -U https://github.com/KarthikPalakurthy/ansible-roboshop roboshop.yml -e ROLE_NAME=${component} -e env=${env} | tee /opt/ansible.log