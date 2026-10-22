# 4. Jenkins credentials

To add each entry: **Manage Jenkins → Credentials → System → Global credentials → Add Credentials**.
The **IDs must match exactly**, because the Jenkinsfile refers to them by ID.

| ID | Kind | Used for |
|---|---|---|
| `swr-login` | Username with password | `docker login` / `docker push` to SWR |
| `cce-kubeconfig` | Secret file | `kubectl` against the CCE cluster |
| `github-sg616` | Username with password | Optional. Only needed if a repo becomes private. |

No secret is ever committed to git.

## As code (recommended)
`swr-login` and `cce-kubeconfig` are created by Configuration as Code from [`config/casc/credentials.yaml`](../config/casc/credentials.yaml). That file contains only variable names; the values live in root-owned files on the VM:

| File | Contents |
|---|---|
| `/etc/jenkins/secrets/SWR_USER` | `pk-isb-1_<domain>@<AK>` (see below for how to get it) |
| `/etc/jenkins/secrets/SWR_PASS` | the SWR login key |
| `/etc/jenkins/secrets/cce-kubeconfig` | the kubeconfig from [05-kubeconfig-cce.md](05-kubeconfig-cce.md) |

Create them without the values touching shell history, then apply:
```bash
sudo install -d -m 0750 -o root -g jenkins /etc/jenkins/secrets
sudo bash -c 'read -rp "SWR user (pk-isb-1_<domain>@<AK>): " v; printf %s "$v" > /etc/jenkins/secrets/SWR_USER'
sudo bash -c 'read -rsp "SWR login key: " v; printf %s "$v" > /etc/jenkins/secrets/SWR_PASS'
sudo install -m 0640 -o root -g jenkins /path/to/kubeconfig.json /etc/jenkins/secrets/cce-kubeconfig
sudo bash scripts/09-jenkins-casc.sh      # also creates the pipeline job
```
- **Rotation:** replace the file, then **Manage Jenkins → Configuration as Code → Reload existing configuration** (or restart Jenkins).
- Configuration as Code owns the global credentials list: a credential added only in the UI is **removed** on the next restart or reload. Add new credentials to `credentials.yaml` instead.
- The secret files are covered by the same rules as `credentials.xml`: never copy them off the VM unencrypted.

The UI steps below remain as a fallback, and describe how to obtain each value.

## GitHub App
`sg616/jenkin-server-pk` (the Jenkinsfile repo) is **private**. Jenkins reads it through a **GitHub App**, credential ID `github-app`. It is not tied to a person, it is read-only, and Jenkins mints a 1-hour token per use, so there is nothing to rotate. The app repo `sample-project-sky-47-deploy-test` is public and needs no credential.

**Create the app** (once, in GitHub, signed in as the owner, `sg616`):
1. Go to **Settings → Developer settings → GitHub Apps → New GitHub App**.
   - Name: e.g. `jenkins-paykoko-beta` (must be unique on GitHub).
   - Homepage URL: `https://jenkins.paykoko.pk`
   - **Webhook: untick *Active*.** Builds are manual.
   - Repository permissions: **Contents: Read-only**. Metadata: Read-only is set automatically. Leave everything else as *No access*.
   - Where can this app be installed: **Only on this account**.
   - Click **Create GitHub App**.
2. On the app's page, note the **App ID**, a number.
3. Under **Private keys**, click **Generate a private key**. A file named `<app>.<date>.private-key.pem` downloads.
4. Click **Install App** (left menu) → **Install** → **Only select repositories** → `jenkin-server-pk` → **Install**.

**Give it to Jenkins** (on the VM):
```bash
sudo bash -c 'printf %s <App ID> > /etc/jenkins/secrets/GITHUB_APP_ID'
sudo install -m 0640 -o root -g jenkins ~/<app>.<date>.private-key.pem /etc/jenkins/secrets/
sudo RECREATE_JOB=1 bash scripts/09-jenkins-casc.sh   # converts the key to PKCS#8, recreates the job with the credential
```
To add another private repo later, add it to the app's installation (step 4). Nothing changes in Jenkins.

---

## `swr-login`: SWR long-term login
Don't use the temporary login command from the SWR console: it expires after about 24 hours. CI needs a long-term login.

1. Console → **IAM → My Credentials → Access Keys → Create Access Key**. Save the **AK** and **SK**. A dedicated IAM user for CI is best; it needs SWR push permissions on the org `pk-beta-repo`.
2. Find your **domain (account) name** under IAM → My Credentials.
3. Generate the login key from the SK. Run this on any Linux machine, and use a space before the command so it stays out of shell history:
   ```bash
    printf "%s" "<AK>" | openssl dgst -binary -sha256 -hmac "<SK>" | od -An -vtx1 | sed 's/[ \n]//g' | sed 'N;s/\n//'
   ```
   The output is the **login key**.
   Some consoles offer **SWR → Access Credentials / Generate Long-Term Login Command** instead. If yours does, copy the values from that.
4. In Jenkins:
   - Username: `pk-isb-1_<domain>@<AK>`. This is the same format shown in the app repo's `K8S-DEPLOYMENT.md` §3.
   - Password: `<login key>`
   - ID: `swr-login`

Test it on the VM:
```bash
sudo SWR_USER='pk-isb-1_<domain>@<AK>' SWR_PASS='<login key>' bash scripts/verify.sh
```

## `cce-kubeconfig`: cluster access
The steps are in [05-kubeconfig-cce.md](05-kubeconfig-cce.md). Then:
- Kind: **Secret file**
- File: the downloaded `kubeconfig.json`
- ID: `cce-kubeconfig`

## `github-sg616` (optional)
Both repos are public today, so you don't need this yet. If they become private:
1. GitHub → Settings → Developer settings → **Fine-grained token**. Give it read-only *Contents* access on `jenkin-server-pk` and `sample-project-sky-47-deploy-test`.
2. In Jenkins: Username `sg616`, Password = the token, ID `github-sg616`.
3. Select it in the job's SCM settings, and set `APP_REPO_CREDS = 'github-sg616'` in the Jenkinsfile.

## Rotation
- To rotate the SWR key: create a new AK/SK → update `swr-login` → delete the old AK in IAM.
- To rotate the kubeconfig: download it again → **Update** the `cce-kubeconfig` file.
