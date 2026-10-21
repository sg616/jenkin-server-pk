# 3. Initial Jenkins configuration

## Setup wizard
1. **Create First Admin User.** Make a named admin account, for example `sajeewa`. Don't keep using the `admin` account with the initial password.
2. **Instance Configuration → Jenkins URL**: `http://<EIP>:8080/`. Use `http://<EIP>/` instead if nginx is in front.

## Manage Jenkins → Security
| Setting | Value |
|---|---|
| Security Realm | Jenkins' own user database. ☐ **Allow users to sign up** stays unticked. |
| Authorization | **Matrix-based security**: `Anonymous` gets nothing, and `Authenticated Users` get *Overall/Read* and *Job/Read*. Your admin user gets *Administer*. |
| Markup Formatter | Plain text |
| Agents → TCP port for inbound agents | **Disable**. There are no inbound agents; builds run on the built-in node. |
| CSRF Protection | enabled, which is the default |
| Git Host Key Verification | **Accept first connection** |

Add each extra user with **Manage Jenkins → Users → Create User**, then give them *Job/Build* in the matrix.

## Manage Jenkins → Nodes → Built-In Node → Configure
- **Number of executors: 2.** A single VM is enough here. The job sets `disableConcurrentBuilds`, so the same job never runs twice at once.
- Labels: `docker kubectl`

> If you add separate build agents later, set the built-in node to 0 executors and run builds on the agents.

## Manage Jenkins → System
- **# of executors**: see above.
- **Global properties → Environment variables**: none are needed. The pipeline keeps its constants (registry, org, namespace) in its own `environment {}` block.
- **Timestamper**: keep the default.

## Next
- [04-credentials.md](04-credentials.md)
- [05-kubeconfig-cce.md](05-kubeconfig-cce.md)
- Then create the job using [../jobs/sample-project-sky-47-deploy.md](../jobs/sample-project-sky-47-deploy.md)
