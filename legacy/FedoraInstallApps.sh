#!/bin/bash
# DEPRECATED — Ubuntu/yum-era bulk installer; not Fedora-ready (uses yum, wrong package names).
# Use scripts under ../dev/ and ../android/ instead.
# Moved to legacy/ during repo cleanup (2026-06).

echo "[DEPRECATED] Disabled. Use scripts under ../dev/ and ../android/" >&2
exit 1

# update system
sudo yum update -y
sudo yum upgrade -y

# IDE
sudo yum install geany -y

# Programming
sudo yum install git -y
sudo yum install g++ -y
sudo yum install ruby -y
sudo yum install rails -y
sudo yum install python -y
sudo yum install php -y
sudo yum install nodejs -y

# web server
sudo yum install apache2 -y

# database
sudo yum install mysql-server -y

# network tools
sudo yum install nmap -y
sudo yum install wireshark -y

# desktop enviroment
sudo yum install cinnamon -y

