# Job: `sample-project-sky-47-deploy`

This job is a Pipeline. It loads its Jenkinsfile from **this repo** (`jenkin-server-pk`). The app repo (`sample-project-sky-47-deploy-test`) needs no Jenkins files at all, because the pipeline clones the app repo by itself.

## Before you start
- The plugins from `config/plugins.txt` are installed, including `git-parameter`, which provides the branch/tag dropdown. `scripts/05-install-plugins.sh` does this.
- The `swr-login` and `cce-kubeconfig` credentials exist. See [docs/04-credentials.md](../docs/04-credentials.md).

## Create the job as code (recommended)
`sudo bash scripts/09-jenkins-casc.sh` creates the job from [`config/casc/jobs.yaml`](../config/casc/jobs.yaml) with exactly the settings below (Job DSL via Configuration as Code).

It is **create-only**: the job is generated when it does not exist and is never rewritten, because regenerating it would drop the parameters the Jenkinsfile registered on build #1. To apply a change to `jobs.yaml`, run `sudo RECREATE_JOB=1 bash scripts/09-jenkins-casc.sh`. It deletes the job, including its build history, and recreates it. Then do the first run again.

The pipeline repo is private, so the job's SCM uses the `github-app` credential ([docs/04](../docs/04-credentials.md#github-app)).

## Create the job (UI, fallback)
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

## First run (registers parameters and the branch/tag list)
1. Click **Build Now**. Build **#1** only registers the parameters and checks out the app repo, so the `REF` dropdown can list its branches and tags. Nothing is built or deployed. Its description reads *Parameters registered, nothing deployed*.
2. Reload the page. The button now reads **Build with Parameters**, and `REF` shows a dropdown with a filter box.

## Parameters
| Name | Default | Meaning |
|---|---|---|
| `ACTION` | `deploy` | `deploy` builds `REF`, pushes a new image and rolls it out. `deploy-existing` rolls out an `IMAGE_TAG` that is already in SWR, without building. `rollback` runs `kubectl rollout undo`. |
| `SERVICES` | `all` | `all`, `backend`, `orders-backend`, `frontend` |
| `REF` | `origin/main` | **Dropdown** of the app repo's branches and git tags |
| `IMAGE_TAG` | empty | deploy: optional override (when empty, the tag comes from the git tag, or is `<branch>-<sha>-<build#>`). It must not exist in SWR yet. deploy-existing: **required**. |
| `DEPLOY` | ☑ | deploy only: untick it to build and push without rolling out |

The usage examples and rollback rules are in [docs/06-pipeline.md](../docs/06-pipeline.md).
