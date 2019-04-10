# DNS Proxy For AWS EC2 & Cloudformation

Based on Jim Hale's amazing [DNS Proxy](https://github.com/jmhale/dns-proxy)

## Description
Creates a single DNS proxy instance on EC2 (by default t3.nano ~ $5/mo.) and re-uses existing elastic IP whenever the stack is updated.
So you never ever have to update your client's DNS settings.

Utilizes EC2 security group to grant clients access to EC2 instance, those IPs are added automatically and each client can have one IP active at the same time.  

To make this work all you need is one, or many dynamic DNS domains that are updated with the IPs of your clients (friends, family etc).
These domains are then checked every minute for IP changes, and EC2 security groups are updated accordingly (one entry per client/dyndns domain).

## Requirements:
- awscli installed & configured. To run commands without region parameter you also need a default profile in `~/.aws/credentials`
- SSH key set up in AWS (Best to assign your `~/.ssh/id_rsa.pub`)
- Manually created VPC Elastic IP

## What Cloudformation creates:
- Single EC2 Instance (t3.nano Ubuntu 18.04 Minimal) (~$5/mo.)
- Security Group: dnsProxy

## How To Use:
- Have as many dynamic DNS domains as you need, and add them to `example.dynamic-dns-domains.txt`. Rename file to `dynamic-dns-domains.txt`.
- Add the domains you want to proxy to the `domains.txt`.
- Rename `example.parameters.json` to `parameters.json` and adjust the parameters to your needs.
- Run Cloudformation command, wait for stack to be finished building in the [UI Console](https://console.aws.amazon.com/cloudformation/home)
- Run the Setup bash script
- Now you should be ready to get the popcorn out.

This shouldn't take more than maybe 5 minutes from start to finish!  

#### Daily Usage:
- The command for Cloudformation needs to be executed to create a new stack. Only if you make changes to the `stack.yaml` you need to run the `update-stack` command again.  

- If you simply update `domains.txt` or `dynamic-dns-domains.txt`, you only need to run the bash script.  

- If you should ever delete the stack permanently, you have to manually remove the Elastic IP. I chose to keep the EIP out of the `stack.yaml`, so it's guaranteed to always be reused and I never ever have to update my DNS later on.   

### 1. Create EC2 Stack
```
$ aws --region us-east-1 \
cloudformation create-stack \
--stack-name dnsProxy \
--template-body file://stack.yaml \
--parameters file://parameters.json \
--capabilities CAPABILITY_NAMED_IAM
```

#### 1.1 Update EC2 Stack
```
$ aws --region us-east-1 \
cloudformation update-stack \
--stack-name dnsProxy \
--template-body file://stack.yaml \
--parameters file://parameters.json \
--capabilities CAPABILITY_NAMED_IAM
```

#### 1.2 Delete EC2 Stack
```
$ aws --region us-east-1 \
cloudformation delete-stack \
--stack-name dnsProxy
```

### 2. Install / Update DNS Proxy
Run after initial Cloudformation setup, or whenever you made updates to the `domains.txt` or `dynamic-dns-domains.txt`.  
`$ bash dnsProxy.sh`  

or, if you are not using your ~/.ssh/id_rsa.pub key:
`$ bash dnsProxy.sh ~/.ssh/your-key.pub`

 
## Automatic IP Updates:
If you're on macOS, you can use the small script in `ip-updater/`. Just fill in your credentials, then run it like `$ bash ip-updater/dynDnsUpdater.sh` and it will create a cronjob on your system which will update
dynamic dns providers.

#### Supported providers:
(The script expects you to fill in details for both providers)
- https://duckdns.org
- https://goip.de


	- The End -