# Ansible

This directory contains automation playbooks.

Typical tasks:

- Configure servers
- Install packages
- Maintain Kubernetes nodes

Example:

```bash
ansible all -i inventory/hosts.ini -m ping
```
