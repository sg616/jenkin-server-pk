# Job: `sample-project-sky-47-deploy`

This job is a Pipeline. It loads its Jenkinsfile from **this repo** (`jenkin-server-pk`). The app repo (`sample-project-sky-47-deploy-test`) needs no Jenkins files at all, because the pipeline clones the app repo by itself.

## Before you start
- The plugins from `config/plugins.txt` are installed. `scripts/05-install-plugins.sh` does this.
- The `swr-login` and `cce-kubeconfig` credentials exist. See [docs/04-credentials.md](../docs/04-credentials.md).

## Create the job (UI)
1. **Dashboard → New Item**
   - Name: `sample-project-sky-47-deploy`
   - Type: **Pipeline** → OK
2. **General**
   - Description: `Build, push to SWR and deploy sample-app services to sky47 CCE`
   - ☑ **Do not allow concurrent builds**. The Jenkinsfile sets this too.
   - ☐ This project is parameterized: leave it unticked. The Jenkinsfile defines the parameters (see the note below).
3. **Triggers**: leave everything unticked. Builds are started by hand only.
4. **Pipeline**
   - Definition: **Pipeline script from SCM**
   - SCM: **Git**
     - Repository URL: `https://github.com/sg616/jenkin-server-pk.git`
     - Credentials: `- none -` for a public repo. For a private repo, pick `github-sg616`.
     - Branch Specifier: `*/main`
   - Script Path: `pipelines/sample-project-sky-47/Jenkinsfile`
   - ☑ Lightweight checkout
5. **Save**

## First run (registers the parameters)
Parameters declared in a Jenkinsfile only show up after the job has run once.

1. Click **Build Now**. Build **#1** only registers the parameters: the Jenkinsfile skips every stage, so nothing is built or deployed. Its description reads *Parameters registered, nothing deployed*.
2. Reload the page. The button now reads **Build with Parameters**.

## Parameters
| Name | Default | Meaning |
|---|---|---|
| `ACTION` | `deploy` | `deploy` builds, pushes and rolls out. `rollback` runs `kubectl rollout undo` and builds nothing. |
| `SERVICES` | `all` | `all`, `backend`, `orders-backend`, `frontend` |
| `BRANCH` | `main` | Branch of the app repo to build |
| `IMAGE_TAG` | empty | When empty, the tag is `<branch>-<shortSHA>-<build#>`. Set something like `1.3.0` for a release tag. |
| `DEPLOY` | ☑ | Untick it to only build and push the images |

The usage examples are in [docs/06-pipeline.md](../docs/06-pipeline.md).
