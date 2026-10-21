# 4. Jenkins credentials

To add each entry: **Manage Jenkins → Credentials → System → Global credentials → Add Credentials**.
The **IDs must match exactly**, because the Jenkinsfile refers to them by ID.

| ID | Kind | Used for |
|---|---|---|
| `swr-login` | Username with password | `docker login` / `docker push` to SWR |
| `cce-kubeconfig` | Secret file | `kubectl` against the CCE cluster |
| `github-sg616` | Username with password | Optional. Only needed if a repo becomes private. |

No secret is ever committed to git.

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
