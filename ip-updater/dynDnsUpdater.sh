#!/usr/bin/env bash

##
# This script updates dynamic dns providers via cronjob.
# It is compatible with macOS, but can easily be adjusted.
#
# Supported providers:
# https://duckdns.org
# https://goip.de
#
##

##############################################################
# Duck DNS setup
##############################################################
# Auth Token
echo -e "\033[93mWhat is your DuckDNS.org Auth Token?\033[0m"
read -p 'Auth Token: ' DUCK_DNS_TOKEN

echo -e "\n\n"

# Comma separated list of sub domain names: one,two,three,etc
duckdns_domains=$(cat << EOF
Which domain name(s) should I update for DuckDNS.org?
Please write only the name, without domain.
If full domain is mydns.example.com, simply write 'mydns'
Separate multiple by comma: mydns,yourdns,thatdns

EOF
)

echo -e "\n\033[93m${duckdns_domains}\033[0m"

read -p 'Domain(s): ' DUCK_DNS_SUBDOMAINS

echo -e "\n\n"

##############################################################
# GoIP setup
##############################################################
# User & Pass
echo -e "\033[93mWhat is your GoIP.de Username?\033[0m"
read -p 'User: ' GOIP_USER

echo -e "\n\n"

echo -e "\033[93mWhat is your GoIP.de Password?\033[0m"
read -p 'Password: ' GOIP_PASS

echo -e "\n\n"

# Comma separated list of sub domains: one.goip.de,two.goip.de,three.goip.de
goip_domains=$(cat << EOF
Which domain name(s) should I update for GoIP.de?
Please write the full name, including domain.
If full domain is mydns.goip.de, write 'mydns.goip.de'
Separate multiple by comma: mydns.goip.de,yourdns.goip.de,thatdns.goip.de

EOF
)

echo -e "\n\033[93m${goip_domains}\033[0m"

read -p 'Domain(s): ' GOIP_SUBDOMAINS


# create a hidden directory in users home dir
cd ~
if [ ! -d ~/.ip_updater ]; then
	echo "Creating directory ~/.ip_updater"
	mkdir .ip_updater
fi

cd .ip_updater/
if [ -f dynDnsUpdater ]; then
 echo "Deleting old IP Updater script"
 rm dynDnsUpdater
fi

echo "Setting up / Updating Dynamic DNS Cronjob"
cat <<DYNDNS >> dynDnsUpdater
#!/bin/bash
IP=\$(curl -s http://whatismyip.akamai.com/)
echo "Your IP: \${IP}"
# DuckDNS
ducky=\$(echo \$(curl -s -k "https://www.duckdns.org/update?domains=${DUCK_DNS_SUBDOMAINS}&token=${DUCK_DNS_TOKEN}&ip="))
echo "DuckDNS Answer: \${ducky}"
if [[ "\${ducky}" == "KO" ]]; then
 osascript -e 'display notification "Better check your Ducks..." with title "Duck DNS Notification" subtitle "DNS Update Failed" sound name "Submarine"'
fi

# GoIP
goip=\$(echo \$(curl -s -k "https://www.goip.de/setip?username=${GOIP_USER}&password=${GOIP_PASS}&subdomain=${GOIP_SUBDOMAINS}&ip=\${IP}&shortResponse=true"))
echo "GoIp Answer: \${goip}"
if [[ ! "\${goip}" == *"\${IP}"* ]]; then
 osascript -e 'display notification "Better check your account, before you wreck your account..." with title "GOIP.de DNS Notification" subtitle "DNS Update Failed" sound name "Submarine"'
fi
DYNDNS

chmod 700 dynDnsUpdater
chmod +x dynDnsUpdater

##
# Create cronjob
##
crontab -l > ipupdater
echo "* * * * * ~/.ip_updater/dynDnsUpdater >/dev/null 2>&1" > ipupdater
crontab ipupdater
rm ipupdater

# aaand, we're done
echo -e '\033[93mIP Updater successfully scheduled!\033[0m'
osascript -e "display notification \"May the force be with you\" with title \"Hey $(id -un)\" subtitle \"Automatic IP Updates Enabled\" sound name \"Submarine\""

exit 0