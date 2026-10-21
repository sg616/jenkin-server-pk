# 9. Security model and accepted risks

This setup was chosen for a **beta / R&D** environment. Its trade-offs are listed here so that nobody runs into them by surprise.

## Accepted risk: builds run on the Jenkins server
- Builds run on the built-in node of the server itself, as the `jenkins` user.
- That user can read `$JENKINS_HOME/secrets/master.key` and `credentials.xml`. Together they decrypt **every** stored credential: the SWR key, the kubeconfig and the GitHub token.
- The `jenkins` user is also in the `docker` group, which is **effectively root** on the VM.

**What follows from this:** anyone who can change what a build runs can get every credential and root on the VM. That includes:
- pushing to `jenkin-server-pk` (where the Jenkinsfile lives)
- having *Job/Configure* in Jenkins
- in principle, changing the app repo's Dockerfiles. `RUN` steps run inside build containers, which can't see Jenkins credentials. The risk there is lower, but it isn't zero.

## Required controls (they keep that risk acceptable)
1. **GitHub branch protection on `sg616/jenkin-server-pk` → `main`**:
   - Require a pull request with at least 1 approval.
   - Block force pushes and branch deletion.
   - Optional: require signed commits.
   - Settings → Branches → Add rule, or Rulesets.
2. **Do the same on `sample-project-sky-47-deploy-test` → `main`.** That's the code that ends up running in the cluster.
3. **Jenkins permissions** ([03-initial-config.md](03-initial-config.md)):
   - Only admins get *Overall/Administer* and *Job/Configure*.
   - Deployers get *Job/Build*, *Job/Read* and *Job/Cancel* only.
   - Anonymous users get nothing, and sign-up stays off.
4. **Least-privilege cluster access.** Make `cce-kubeconfig` the `jenkins-deployer` ServiceAccount, which can only patch Deployments in `sample-app` ([05-kubeconfig-cce.md](05-kubeconfig-cce.md#least-privilege-recommended-now)). Don't use the console kubeconfig, which carries the IAM user's permissions on the whole cluster.
5. **Dedicated IAM user for SWR.** Give it push rights on the `pk-beta-repo` organization only and no console login. Rotate its AK/SK yearly ([04-credentials.md](04-credentials.md#rotation)).
6. **Network:**
   - The security group lets only admin IPs reach 22 and 8080 (or 80/443).
   - Put TLS in front before real use ([02-install.md](02-install.md#tls-do-this-before-real-use)).
   - Harden SSH (`scripts/07-harden-ssh.sh`).
7. **Backups are secrets.** Encrypt any copy that leaves the VM ([07-operations.md](07-operations.md#backups)).

## What the pipeline does to limit exposure
- **Input checks:** user input is validated (`REF`, `SERVICES`, `IMAGE_TAG`) and reaches shell commands only through environment variables in single-quoted scripts.
- **Secrets in shell:** the shell reads secrets from environment variables (`--password-stdin`). They are never pasted into the command text, so Jenkins masks them in logs.
- **Docker login:** login data is kept per build in `$WORKSPACE/.docker`, logged out in `post`, and the workspace is deleted after every build.
- **Kubeconfig:** it's a Secret file that only exists for the duration of the `withCredentials` block.
- **No inbound agent port, no CLI over remoting, CSRF on.**

## When to move to a separate build agent
Move when any of these happens: more people get build rights, a production environment is added, or the beta cluster starts holding real data. The steps:
1. Create a second VM in the same VPC. Run `00`, `01`, `03` and `04` on it (no Jenkins).
2. In Jenkins, go to **Manage Jenkins → Nodes → New Node**, choose SSH launch, and give it the label `docker kubectl`.
3. Set the built-in node to **0 executors**.
4. In the Jenkinsfile, change `agent any` → `agent { label 'docker kubectl' }`.

After that, builds can no longer read `$JENKINS_HOME`. Credentials reach the agent only for the duration of each `withCredentials` block.
