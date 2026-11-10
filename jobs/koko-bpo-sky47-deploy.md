# Jobs: `koko-bpo-sky47-*-deploy`

Three Pipeline jobs that build, push to SWR and deploy the **KOKO BPO portal
stack** to sky47 CCE:

| Job | Jenkinsfile | Deployment | App repo |
|---|---|---|---|
| `koko-bpo-sky47-portal-deploy` | `pipelines/koko-bpo-sky47/bpo-portal.Jenkinsfile` | `bnpl-bpo-portal` | `DarazAPACIG/bnpl-bpo-portal-service` |
| `koko-bpo-sky47-web-deploy` | `pipelines/koko-bpo-sky47/bpo-portal-web.Jenkinsfile` | `bnpl-bpo-portal-web` | `DarazAPACIG/bnpl-bpo-portal-web` |
| `koko-bpo-sky47-keycloak-deploy` | `pipelines/koko-bpo-sky47/keycloak.Jenkinsfile` | `bnpl-keycloak` | `DarazAPACIG/bnpl-keycloak-service` |

As with `sample-project-sky-47-deploy`, each job loads its Jenkinsfile from
**this repo**; the app repos carry no Jenkins files and are cloned by the
pipelines themselves.

The k8s manifests are **not** applied by these jobs. They live in
`bnpl-infrastructure-provisioning-service-pk/k8-sky47-dev/` and are applied by
hand once, with `kubectl apply -k`. The pipelines only ever run
`kubectl set image` / `rollout`. See that repo's README for first-time bring-up.

## Before you start

- Plugins from `config/plugins.txt` are installed, including `git-parameter`.
- Credentials `swr-login` and `cce-kubeconfig` exist
  ([docs/04-credentials.md](../docs/04-credentials.md)).
- **`github-darazapacig` exists.** This is new and specific to these jobs. The
  app repos are in the `DarazAPACIG` org, and the existing `github-app`
  credential is scoped to owner `sg616`, so it **cannot** clone them. Create the
  two secret files and re-run the CasC script:

  ```sh
  sudo bash -c 'read -rp "GitHub login: " v; printf %s "$v" > /etc/jenkins/secrets/GITHUB_DARAZ_USER'
  sudo bash -c 'read -rsp "GitHub fine-grained PAT (Contents: Read-only): " v; printf %s "$v" > /etc/jenkins/secrets/GITHUB_DARAZ_TOKEN'
  sudo bash scripts/09-jenkins-casc.sh
  ```

  Scope that token to **only** the four repos it clones
  (`bnpl-bpo-portal-service`, `bnpl-bpo-portal-web`, `bnpl-keycloak-service`,
  `bnpl-build-config`) with `Contents: Read-only` and an expiry date. A classic
  PAT with the `repo` scope would grant read *and write* across the whole org,
  which this does not need. Better still, have a `DarazAPACIG` owner install a
  GitHub App and use a `gitHubApp` credential instead — not tied to a person,
  short-lived tokens. See
  [docs/04-credentials.md](../docs/04-credentials.md#scope-the-darazapacig-token-narrowly).
- The target namespace, Secrets and Deployments already exist in the cluster
  (see `k8-sky47-dev/README.md`). Until they do, the deploy stage fails on
  `kubectl get deployment/...`.

## Create the jobs as code

`sudo bash scripts/09-jenkins-casc.sh` creates all three from
[`config/casc/jobs.yaml`](../config/casc/jobs.yaml).

It is **create-only**: a job is generated when it does not exist and is never
rewritten, because regenerating it would drop the parameters the Jenkinsfile
registered on build #1. To apply a `jobs.yaml` change, run
`sudo RECREATE_JOB=1 bash scripts/09-jenkins-casc.sh` — that deletes the jobs,
including build history, and recreates them. Then do the first run again.

## First run (registers parameters and the branch/tag list)

For **each** job: click **Build Now**. Build **#1** only registers the
parameters and checks out the app repo so the `REF` dropdown can list its
branches and tags. Nothing is built or deployed; the description reads
*Parameters registered, nothing deployed*. Reload the page and the button
becomes **Build with Parameters**.

## Parameters

| Name | Default | Meaning |
|---|---|---|
| `ACTION` | `deploy` | `deploy` builds `REF`, pushes a new image and rolls it out. `deploy-existing` rolls out an `IMAGE_TAG` already in SWR, without building. `rollback` runs `kubectl rollout undo`. |
| `ENV` | `dev-sky47` | Target environment. Selects the namespace, the SWR org, the `bnpl-build-config` branch (backend) and the `VUE_APP_*` values (web). |
| `REF` | `origin/main` | **Dropdown** of the app repo's branches and git tags. |
| `IMAGE_TAG` | empty | deploy: optional override; empty means the git tag name, or `<branch>-<sha>-<build#>`. Must not already exist in SWR. deploy-existing: **required**. |
| `DEPLOY` | ticked | deploy only: untick to build and push without rolling out. |

## Multi-environment

`ENV` is the whole mechanism. Each Jenkinsfile holds an `envs()` map:

```groovy
def envs() {
  return [
    'dev-sky47': [namespace: 'dev-sky47', configBranch: 'dev-sky47', swrOrg: 'pk-beta-repo'],
  ]
}
```

Adding, say, `qa-sky47` means:

1. one new entry in that map, in each of the three Jenkinsfiles;
2. one new overlay directory, `k8-sky47-dev/overlays/qa-sky47/`;
3. one new `bnpl-build-config` branch (backend only);
4. adding the value to the `ENV` `choice` list;
5. `sudo RECREATE_JOB=1 bash scripts/09-jenkins-casc.sh`, then re-run build #1
   so the new choice is registered.

Because the **backend and Keycloak images are environment-agnostic** — config
reaches them at runtime through `envFrom` — a tag tested in one environment can
be promoted to another with `ACTION=deploy-existing`, no rebuild.

The **web image cannot be promoted**: its `VUE_APP_*` values are baked in at
`docker build`, so it must be rebuilt per environment. That is a property of the
app's unchanged Dockerfile, not of this pipeline.

## What is different from the sample-project pipeline

The sample app's three services are near-identical, so one Jenkinsfile with a
`SERVICES` parameter covers them. These three have genuinely different build
shapes, which is why there are three files:

- **Backend** has two extra stages. Its Dockerfile is unchanged from the Alibaba
  build, so it `COPY`s `application.properties` and `supervisord.conf`, neither
  of which is in the app repo — both come from `bnpl-build-config` at the branch
  for the selected `ENV`. (On the Sky47 branches `application.properties` is
  intentionally **empty**; real config is injected at runtime.) That same
  Dockerfile also starts `FROM` a JRE and expects a prebuilt `target/`, and this
  VM has `openjdk-25-jre` only — no JDK, no Maven — so the jar is built inside a
  `maven:3.8-eclipse-temurin-11` container, run as the `jenkins` uid so
  `cleanWs()` can still delete the artifacts, with `~/.m2` cached outside the
  workspace.
- **Web** passes the five `VUE_APP_*` build args its Dockerfile declares. The
  Google Maps key is optional: leave `MAPS_CREDENTIAL_ID` empty in the
  Jenkinsfile and the location map simply does not render.
- **Keycloak** is a plain `docker build` with no args.

Deploy **Keycloak first** on a fresh environment: the backend fetches its JWKS
at startup.

## Gotchas

- **Realm import is one-shot.** Redeploying the Keycloak image does *not*
  re-apply `realm-export/bpo-portal-realm.json`; `start --import-realm` skips a
  realm that already exists. Realm changes need a fresh schema or an
  admin-console edit. The admin console is deliberately not exposed through the
  gateway — reach it with
  `kubectl -n dev-sky47 port-forward deploy/bnpl-keycloak 8080:8080`.
- **Keycloak rollouts are slow** (~3 min). `KC_DB` is a Keycloak *build* option
  and the image has no `kc.sh build` step, so it re-augments on every start.
  `ROLLOUT_TIMEOUT` is 300s for this reason.
- **Image tags will not match the committed manifests** after the first build,
  because deploys use `kubectl set image`. That is expected. Re-applying the
  overlay would roll pods back to its placeholder tag.
- **A failed rollout auto-undoes itself** and then fails the build, same as the
  sample pipeline. Check `kubectl -n <ns> rollout history deploy/<name>`; each
  revision carries a `jenkins #N` change-cause.
