# 6. The deploy pipeline

File: [`pipelines/sample-project-sky-47/Jenkinsfile`](../pipelines/sample-project-sky-47/Jenkinsfile)
Job: `sample-project-sky-47-deploy`. To create it, see [jobs/sample-project-sky-47-deploy.md](../jobs/sample-project-sky-47-deploy.md).

## Flow
```
Checkout app ──► Resolve tag ──► Build images ──► Push to SWR ──► Deploy to CCE ──► Verify
 (git clone)     branch-sha-#     docker build     docker push     set image +       get pods
                                                                   rollout status
                                                                   (auto-undo on fail)

ACTION=rollback:  Resolve ──► Rollback (kubectl rollout undo) ──► Verify
```

## Service map
| `SERVICES` value | App repo dir | SWR image | Deployment/container |
|---|---|---|---|
| `backend` | `backend/` | `swr.pk-isb-1.sky47.com/pk-beta-repo/sample-backend` | `backend` |
| `orders-backend` | `orders-backend/` | `.../sample-orders-backend` | `orders-backend` |
| `frontend` | `frontend/` | `.../sample-frontend` | `frontend` |

With `all`, the services deploy in that order: backends first, then the frontend.

## Image tags
- **Default:** `<branch>-<shortSHA>-<buildNumber>`, for example `main-aa54b9a-12`. Every build gets a unique tag that points to an exact commit.
- **Release:** set `IMAGE_TAG=1.3.0`. Use this for versions people should notice.
- The build description in the Jenkins UI shows the action, the services and the tag.

> The image tags hardcoded in the app repo's `k8s/*.yaml` are only used for the first `kubectl apply`. After that, Jenkins sets the live image with `kubectl set image`. Don't run `kubectl apply -f k8s/` again without updating those tags first, because it would roll the images back to the old ones.

## Common runs
| Goal | Parameters |
|---|---|
| Deploy everything from `main` | `ACTION=deploy`, `SERVICES=all` |
| Ship only the frontend | `SERVICES=frontend` |
| Test a feature branch | `BRANCH=feature/xyz`, `SERVICES=backend` |
| Build and push only, deploy later | untick `DEPLOY` |
| Release tag | `IMAGE_TAG=1.3.0` |
| Undo the last frontend deploy | `ACTION=rollback`, `SERVICES=frontend` |

## Failure handling
- If `rollout status` doesn't succeed within `ROLLOUT_TIMEOUT` (180 s), the pipeline runs `kubectl rollout undo` for that service and marks the build **failed**. Services that came later in the list are not touched.
- A failed build or push never touches the cluster.
- Docker login data is kept in `$WORKSPACE/.docker`. The pipeline logs out at the end of the push stage, and the workspace is deleted after every build.

## Deploying to a specific older image
`rollback` only goes back **one** revision. To return to any earlier tag:
- Run `ACTION=deploy`, `IMAGE_TAG=<old tag>` on the commit that produced it. This rebuilds the image from that commit.
- Or run it by hand on the VM with the stored kubeconfig: `kubectl -n sample-app set image deployment/frontend frontend=swr.../sample-frontend:<old tag>`.
- You can see the history with `kubectl -n sample-app rollout history deployment/<svc>`.

## Changing constants
The registry, org, namespace and app repo URL are in the Jenkinsfile's `environment {}` block. Edit them there and commit. The job reads the Jenkinsfile from git on every build.
