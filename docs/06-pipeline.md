# 6. The deploy pipeline

File: [`pipelines/sample-project-sky-47/Jenkinsfile`](../pipelines/sample-project-sky-47/Jenkinsfile)
Job: `sample-project-sky-47-deploy`. To create it, see [jobs/sample-project-sky-47-deploy.md](../jobs/sample-project-sky-47-deploy.md).

## Flow
```
deploy:           Validate ─► Checkout REF ─► Resolve tag ─► SWR login + tag must NOT exist
                  ─► Build ─► Push ─► Deploy to CCE (annotate, set image, rollout status,
                                                     auto-undo on failure) ─► Verify
deploy-existing:  Validate ─► Resolve ─► SWR login + tag MUST exist ─► Deploy to CCE ─► Verify
rollback:         Validate ─► Resolve ─► kubectl rollout undo ─► Verify
```
`Validate` runs first and checks every value you typed (`REF`, `SERVICES`, `IMAGE_TAG`). Shell commands only receive those values through environment variables, never by pasting them into the command text.

## Parameters
| Name | Used by | Meaning |
|---|---|---|
| `ACTION` | all | `deploy` / `deploy-existing` / `rollback` |
| `SERVICES` | all | `all`, `backend`, `orders-backend`, `frontend` |
| `REF` | deploy | **Dropdown** of the app repo's branches (`origin/main`, `origin/feature/...`) and git tags (`v1.3.0`). Has a quick filter box. |
| `IMAGE_TAG` | deploy (optional), deploy-existing (**required**) | See "Image tags" below |
| `DEPLOY` | deploy | Untick it to only build and push |

> The `REF` dropdown is filled from the app repo that an earlier build checked out. That's why build #1 checks out the app repo but deploys nothing. If the list ever looks stale, run any build: each deploy fetches all branches and tags again.

## Service map
| `SERVICES` | App repo dir | SWR image (`swr.pk-isb-1.sky47.com/pk-beta-repo/...`) | Deployment / container |
|---|---|---|---|
| `backend` | `backend/` | `sample-backend` | `backend` |
| `orders-backend` | `orders-backend/` | `sample-orders-backend` | `orders-backend` |
| `frontend` | `frontend/` | `sample-frontend` | `frontend` |

With `all`, the services deploy in that order: backends first, then the frontend.

## Image tags
| `REF` | `IMAGE_TAG` | Image tag |
|---|---|---|
| a branch, e.g. `origin/main` | empty | `main-<shortSHA>-<build#>`, e.g. `main-aa54b9a-12` |
| a git tag, e.g. `v1.3.0` | empty | `v1.3.0`. Releases get the same name in git and in SWR. |
| any | `1.3.0` | `1.3.0` |

- Allowed characters: `[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}`. In a branch name, characters that aren't allowed (like `/`) become `-`.
- **Tags never change once pushed.** `deploy` fails if the tag already exists in SWR. Overwriting a tag would make `kubectl set image` do nothing, because the spec wouldn't change, and the old pods would keep running even though the build looks green. To roll out a tag that already exists, use `deploy-existing`.
- The build description in the Jenkins UI shows the action, the services, the tag and the source (`REF@sha`). Use it to find the tags you deployed before.

## Common runs
| Goal | Parameters |
|---|---|
| Deploy everything from `main` | `ACTION=deploy`, `REF=origin/main`, `SERVICES=all` |
| Release a git tag | `ACTION=deploy`, `REF=v1.3.0` |
| Test a feature branch on one service | `REF=origin/feature/xyz`, `SERVICES=backend` |
| Build and push now, roll out later | `ACTION=deploy`, untick `DEPLOY`, then later `ACTION=deploy-existing` with the same tag |
| Go back to **any** older version | `ACTION=deploy-existing`, `IMAGE_TAG=<old tag>`, `SERVICES=<svc>` |
| Undo the last deploy of one service | `ACTION=rollback`, `SERVICES=frontend` |

## Rollback vs deploy-existing
- **`rollback`** runs `kubectl rollout undo`, which goes back **one** revision for each selected Deployment.
  - With `SERVICES=all`, **all three are undone**, even the ones the last deploy didn't touch. Their "previous" revision might be weeks old. Prefer rolling back one service at a time.
  - Running `rollback` twice goes back and forth between the last two revisions.
- **`deploy-existing`** sets an exact tag. It's predictable, so it's the better choice for anything other than "undo what I just did".
- If a deploy is already running that tag, it skips that service (`already runs ..., nothing to roll out`).

History for each Deployment, including who deployed what (`change-cause` is set by Jenkins):
```bash
kubectl -n sample-app rollout history deployment/frontend
# REVISION  CHANGE-CAUSE
# 3         jenkins #14 main-aa54b9a-14 (origin/main@aa54b9a)
# 4         jenkins #15 v1.3.0 (v1.3.0@5c1e2d0)
```

## Failure handling
- If `rollout status` doesn't succeed within `ROLLOUT_TIMEOUT` (180 s), the pipeline runs `kubectl rollout undo` for that service and marks the build **failed**. Services that came later in the list are not touched.
- A failed build or push never touches the cluster.
- Docker login data is kept in `$WORKSPACE/.docker` and logged out after every build. The images a build created are removed from the VM after it pushes them.

## Config drift: manifest changes are NOT deployed by Jenkins
Jenkins **only changes images** (`kubectl set image`). Any change to the app repo's `k8s/*.yaml` must still be applied by hand. That includes env vars, probes, resources, replicas, services and secrets.
1. In the app repo, first set the `image:` lines in `k8s/*.yaml` to the tags that are **currently running**. You can see them with `kubectl -n sample-app get deploy -o wide`. If you skip this, `kubectl apply` puts the old hardcoded tags back.
2. Run `kubectl apply -f k8s/<file>.yaml` and then `kubectl -n sample-app rollout status deployment/<svc>`.

> Later improvement, not done now: let the pipeline `kubectl apply` the manifests with the tag filled in by kustomize, so git stays the single source of truth.

## Changing constants
The registry, org, namespace and app repo URL are in the Jenkinsfile's `environment {}` block. Edit them there and commit through a PR ([09-security-model.md](09-security-model.md)). The job reads the Jenkinsfile from git on every build.
