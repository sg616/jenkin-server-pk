# 1. Provision the Jenkins VM on sky47 (ECS)

Jenkins runs on a sky47 **ECS** VM (Elastic Cloud Server) in the **same VPC as the CCE cluster**. The CCE API server has only a private endpoint, so kubectl can reach it only from inside that VPC.

## Spec
| Item | Value |
|---|---|
| Region / AZ | `pk-isb-1`, the same as the CCE cluster |
| Image | Ubuntu 24.04 LTS (22.04 also works) |
| Flavor | at least 2 vCPU / 4 GB RAM. 4 vCPU / 8 GB is better: Maven and npm builds run inside Docker on this VM. |
| System disk | 50 GB or more, General Purpose SSD. Docker images and build cache grow over time. |
| VPC / subnet | **The same VPC as CCE.** Any subnet that can route to the CCE API's internal IP. |
| Key pair | an existing pair, e.g. `KeyPair-beta-sajeewa`, or a new one |
| EIP | Yes, for SSH and the Jenkins UI from your machine. Without an EIP the VM also needs a NAT gateway (see "Outbound internet" below). |

## Security group (inbound)
| Port | Source | Purpose |
|---|---|---|
| 22/tcp | your admin IP/32 | SSH |
| 8080/tcp | your admin IP/32 | Jenkins UI. Close it once nginx is in front. |
| 80/tcp, 443/tcp | your admin IP/32 | Only if you run `scripts/06-nginx-reverse-proxy.sh` |

Do **not** open 8080 to `0.0.0.0/0`. Jenkins holds the SWR and cluster credentials.

## Outbound internet (required)
The VM must be able to reach:
- `pkg.jenkins.io`, `updates.jenkins.io`, `get.jenkins.io`: Jenkins and plugins
- `download.docker.com`, `dl.k8s.io`, `github.com`, `api.github.com`: tooling and the app repo
- `registry-1.docker.io`: base images (`maven`, `eclipse-temurin`, `node`, `nginx`)
- `swr.pk-isb-1.sky47.com`: image push

An EIP on the VM covers all of these. Otherwise, add a NAT gateway with an SNAT rule for the subnet.

## Allow the VM to reach the CCE API
The cluster's security group (`<cluster>-cce-control-*`) must allow **5443/tcp** from the Jenkins VM's private IP, or from its subnet. Check the private API address under CCE → cluster → **Overview → Connection Info**.

## SSH in
```bash
# The .ppk key is for PuTTY. For OpenSSH, convert it first:
#   puttygen KeyPair-beta-sajeewa.ppk -O private-openssh -o ~/.ssh/sky47-beta.pem
ssh -i ~/.ssh/sky47-beta.pem root@<EIP>       # some images use the user "ubuntu"
```
Never commit the key file to this repo. `.gitignore` already blocks `*.ppk` and `*.pem`.

Next: [02-install.md](02-install.md)
