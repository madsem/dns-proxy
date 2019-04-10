#!/usr/bin/env bash

## first things first, let's update the security group to accept our ip at port 22
IP=$(curl -s http://whatismyip.akamai.com/)

# Authorize access on port 22 & remove old rule(s) for port 22
OLD_RULES=$(aws ec2 describe-security-groups \
--group-name "dnsProxy" \
--query 'SecurityGroups[0].IpPermissions[?FromPort==`22`]')

echo "Revoking Old Rules For Port 22"
aws ec2 revoke-security-group-ingress --group-name "dnsProxy" --ip-permissions "${OLD_RULES}"

echo "Updating Port 22 Rules To Accept Connections From ${IP}"
aws ec2 authorize-security-group-ingress --group-name "dnsProxy" --protocol tcp --port 22   --cidr ${IP}/32

#########################################################################
#                             DNS Proxy
#########################################################################

## set ssh key to use
SSH_KEY='~/.ssh/id_rsa.pub'
[ -n "${1}" ] && SSH_KEY=${1}

## get public DNS name of our stack instance
PUBLIC_DNS="$(aws cloudformation describe-stacks \
--stack-name dnsProxy \
--query 'Stacks[0].Outputs[?OutputKey==`PublicDNS`].OutputValue' \
--output text)"

## transfer txt files to our ec2 instance
echo "Transferring dynamic dns domains to server"
scp -i ${SSH_KEY} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null dynamic-dns-domains.txt ubuntu@${PUBLIC_DNS}:~/dynamic-dns-domains.txt

echo "Transferring proxy domains to server"
scp -i ${SSH_KEY} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null domains.txt ubuntu@${PUBLIC_DNS}:~/domains.txt

## create script for execution on ec2 instance
ssh -tqi ${SSH_KEY} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ubuntu@${PUBLIC_DNS} <<'EOSSH'
cat <<'DNS' > ~/dns_proxy.sh
#!/usr/bin/env bash

export DEBIAN_FRONTEND=noninteractive

# run as root
echo "$(whoami)"
[ "$UID" -eq 0 ] || exec sudo bash "$0" "$@"

## get public IP of our stack instance
PUBLIC_IP="$(curl http://169.254.169.254/latest/meta-data/public-ipv4)"

## set dyn domains
IFS=$'\n' read -d '' -r -a DYN_DOMAINS < ~/dynamic-dns-domains.txt

## set proxy domains
IFS=$'\n' read -d '' -r -a DOMAINS < ~/domains.txt

if [ ! -f ~/.dns_proxy ]; then
apt-get install -y software-properties-common

## Update apt cache, install packages
apt-get -y update
apt-get install -y tzdata awscli sniproxy bind9 dnsutils

# create aws defaults
region=$(curl -s 169.254.169.254/latest/meta-data/placement/availability-zone | sed 's/.$//')
mkdir ~/.aws/
cat <<AWS > ~/.aws/config
[default]
output = json
region = ${region}
AWS

## sniproxy config
cat << EOF > /etc/sniproxy.conf
user daemon
pidfile /var/run/sniproxy.pid

error_log {
    filename /var/log/sniproxy/sniproxy.log
    priority notice
}

listen 80 {
    proto http
    table http_hosts
    access_log {
        filename /var/log/sniproxy/http_access.log
        priority notice
    }
}

listen 443 {
    proto tls
    table https_hosts
    access_log {
        filename /var/log/sniproxy/https_access.log
        priority notice
    }
}

table http_hosts {
    .* *
}

table https_hosts {
    .* *
}

table {
   .* *
}
EOF

## named configs
cat << EOF2 > /etc/bind/named.conf
include "/etc/bind/named.conf.options";
include "/etc/bind/named.conf.local";
include "/etc/bind/named.conf.default-zones";
EOF2

cat << EOF3 > /etc/bind/named.conf.local
acl "trusted" {
    any;
};
include "/etc/bind/zones.override";
EOF3

cat << EOF4 > /etc/bind/named.recursion.conf
allow-recursion { trusted; };
recursion yes;
additional-from-auth yes;
additional-from-cache yes;
EOF4

## Set BIND forwarders
cat << EOF5 > /etc/bind/named.conf.options
options {
  directory "/var/cache/bind";

  forwarders {
      2606:4700:4700::1111;
      1.1.1.1;
  };

  dnssec-validation auto;

  auth-nxdomain no;    # conform to RFC1035
  listen-on-v6 { any; };

  allow-query { trusted; };
  allow-transfer { none; };

  include "/etc/bind/named.recursion.conf";
};
EOF5

## Set DNS lookup information for overridden queries
# The below are escaped so that variable expansion will happen when run on remote server
\cat << EOF6 > /etc/bind/db.override
\$TTL  86400

@   IN  SOA ns1 root (
            2016061801  ; serial
            604800      ; refresh 1w
            86400       ; retry 1d
            2419200     ; expiry 4w
            86400)      ; minimum TTL 1d

    IN  NS  ns1

ns1 IN  A   127.0.0.1
@   IN  A   ${PUBLIC_IP}
*   IN  A   ${PUBLIC_IP}
EOF6

cat << EOF7 > /etc/default/sniproxy
# Additional options that are passed to the Daemon.
DAEMON_ARGS="-c /etc/sniproxy.conf"

# Whether or not to run the sniproxy daemon; set to 0 to disable, 1 to enable.
ENABLED=1
EOF7

else
	echo "DNS Proxy already installed - Updating Configuration..."
fi

## Set zones to override
rm /etc/bind/zones.override
touch /etc/bind/zones.override
for i in ${DOMAINS[@]} ; do
echo "zone \"${i%\n}.\" { type master; file \"/etc/bind/db.override\"; };" >> /etc/bind/zones.override
done

## Enable services on boot and start
update-rc.d bind9 defaults
update-rc.d sniproxy defaults

# restart services
service bind9 restart
systemctl restart sniproxy.service

# mark as installed
touch ~/.dns_proxy

## create script to update client ips from dyn domains
cat << CRONSCRIPT > ipupdater
#!/usr/bin/env bash
dns_domains=( "${DYN_DOMAINS[@]}" )

# get current rules for ports 53, 80 & 443
old_rule=\$(aws ec2 describe-security-groups \
--group-name "dnsProxy" \
--query 'SecurityGroups[0].IpPermissions[?FromPort!=\`22\`]')

# revoke old dyn dns ips
aws ec2 revoke-security-group-ingress --group-name "dnsProxy" --ip-permissions "\${old_rule}"

for domain in \${dns_domains[@]} ; do
	# get IP of current domain
	DYN_IP=\$(dig +short \${domain} | tail -1)

	# Authorize access on port 53, 80 & 443
	aws ec2 authorize-security-group-ingress --group-name "dnsProxy" --protocol udp --port 53   --cidr \${DYN_IP}/32
	aws ec2 authorize-security-group-ingress --group-name "dnsProxy" --protocol tcp --port 80   --cidr \${DYN_IP}/32
	aws ec2 authorize-security-group-ingress --group-name "dnsProxy" --protocol tcp --port 443  --cidr \${DYN_IP}/32
done
CRONSCRIPT

# make script executable
chmod +x ipupdater

# move executable
mv ipupdater /usr/bin/ipupdater

# create cronjob
if [ ! -f /etc/cron.d/ipupdate ]; then
sudo bash -c "echo '* * * * * ubuntu /usr/bin/ipupdater' > /etc/cron.d/ipupdate"
fi
DNS
EOSSH

## ssh into the instance and run the script
echo "Installing / Updating DNS Proxy"
ssh -i ${SSH_KEY} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ubuntu@${PUBLIC_DNS} "bash ~/dns_proxy.sh"

## that was it folks!
echo -e '\033[93mThat was it folks, \033[5mPopcorn Time!\033[0m'
exit 0