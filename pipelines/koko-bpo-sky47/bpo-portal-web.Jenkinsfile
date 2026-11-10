// Build -> push to SWR -> deploy the BPO portal SPA (Vue 3 + nginx) to Sky47 CCE.
// Job setup: jobs/koko-bpo-sky47-deploy.md   Usage: docs/06-pipeline.md
//
// Credentials (Manage Jenkins > Credentials, see docs/04-credentials.md):
//   swr-login            Username/password  pk-isb-1_<domain>@<AK> / long-term login key
//   cce-kubeconfig       Secret file        CCE internal-endpoint kubeconfig
//   github-darazapacig   Username/password  PAT for the DarazAPACIG org (private repos)
//
// This image is ENVIRONMENT-LOCKED, unlike the backend and Keycloak ones.
// The app Dockerfile is deliberately unchanged, and it bakes the VUE_APP_*
// values in at build time via ARG/ENV, so an image built for one environment
// cannot be promoted to another -- it must be rebuilt with different
// --build-arg values. That is why those values live in the ENVS map below.
// Making the image portable would need a runtime /config.json loaded before the
// Keycloak adapter initialises, which is an app-code change.
//
// No bnpl-build-config checkout and no Maven container here: the app Dockerfile
// is already multi-stage (node builder -> nginx) and needs nothing from outside
// the repo.
//
// Shell safety: user input reaches sh steps only through withEnv + single-quoted
// scripts, and only after the Validate stage has checked it.

// One entry per environment. Adding qa-sky47 later means adding an entry here,
// an overlay directory under k8-sky47-dev/overlays/, and (for the backend) a
// bnpl-build-config branch.
//
// keycloakUrl / apiBaseUrl must match the ApisixRoute hosts in that overlay, and
// keycloakUrl must match Keycloak's own KC_HOSTNAME, or the login redirect fails.
def envs() {
  return [
    'dev-sky47': [
      namespace      : 'dev-sky47',
      swrOrg         : 'pk-beta-repo',
      keycloakUrl    : 'https://dev-sky47-auth.paykoko.pk',
      keycloakRealm  : 'bpo-portal',
      keycloakClient : 'bpo-frontend',
      // Same origin as the SPA itself, so the browser makes no cross-origin
      // API calls. /api/bpo is the backend context-path, passed through as-is.
      apiBaseUrl     : 'https://dev-sky47-bpo.paykoko.pk/api/bpo',
    ],
  ]
}

def envCfg() {
  return envs()[params.ENV]
}

// Build #1 of a fresh job only registers the parameters (declarative pipelines
// learn them on first run) and checks out the app repo so the REF dropdown can
// list its branches/tags. It never builds or deploys.
def registerOnly() {
  return env.BUILD_NUMBER == '1'
}

def doing(String action) {
  return !registerOnly() && params.ACTION == action
}

// Git Parameter values: branches look like "origin/main", tags like "v1.3.0".
def ref() {
  return (params.REF ?: 'origin/main').trim()
}

def isBranch() {
  return ref().startsWith('origin/')
}

def refName() {
  return isBranch() ? ref().substring('origin/'.length()) : ref()
}

def dockerSafe(String s) {
  return s.replaceAll('[^A-Za-z0-9_.-]', '-')
}

def validTag(String s) {
  return s ==~ /^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$/
}

def imageRef() {
  return "${env.SWR_REGISTRY}/${env.SWR_ORG}/${env.IMAGE_NAME}:${env.TAG}"
}

def buildImage() {
  sh '''
    set -eu
    docker build --pull \
      --build-arg VUE_APP_KEYCLOAK_URL="$VUE_APP_KEYCLOAK_URL" \
      --build-arg VUE_APP_KEYCLOAK_REALM="$VUE_APP_KEYCLOAK_REALM" \
      --build-arg VUE_APP_KEYCLOAK_CLIENT_ID="$VUE_APP_KEYCLOAK_CLIENT_ID" \
      --build-arg VUE_APP_BPO_API_BASE_URL="$VUE_APP_BPO_API_BASE_URL" \
      --build-arg VUE_APP_GOOGLE_MAPS_API_KEY="${MAPS_KEY:-}" \
      -t "$IMAGE_REF" app
  '''
}

pipeline {
  agent any

  options {
    timestamps()
    ansiColor('xterm')
    disableConcurrentBuilds()
    buildDiscarder(logRotator(numToKeepStr: '20'))
    timeout(time: 30, unit: 'MINUTES')
    skipDefaultCheckout()
  }

  parameters {
    choice(name: 'ACTION', choices: ['deploy', 'deploy-existing', 'rollback'],
           description: '''deploy = build REF, push a new image, roll it out.
deploy-existing = roll out IMAGE_TAG that is already in SWR (no build). Use it to go back to any older version.
rollback = kubectl rollout undo to the previous revision.''')
    choice(name: 'ENV', choices: ['dev-sky47'],
           description: 'Target environment. Selects the namespace, the SWR org and the VUE_APP_* values baked into the image.')
    gitParameter(name: 'REF', type: 'PT_BRANCH_TAG', defaultValue: 'origin/main',
                 branchFilter: 'origin/.*', tagFilter: '*', selectedValue: 'DEFAULT',
                 sortMode: 'DESCENDING_SMART', quickFilterEnabled: true, listSize: '10',
                 useRepository: '.*bnpl-bpo-portal-web.*',
                 description: 'Branch (origin/...) or git tag of the app repo to build. Used by ACTION=deploy only.')
    string(name: 'IMAGE_TAG', defaultValue: '',
           description: '''deploy: optional override. Empty = git tag name, or <branch>-<shortSHA>-<build#> for branches. Must not exist in SWR yet.
deploy-existing: required, an image tag already in SWR (see past build descriptions).''')
    booleanParam(name: 'DEPLOY', defaultValue: true,
           description: 'deploy only: untick to build and push to SWR without rolling out.')
  }

  environment {
    APP_REPO        = 'https://github.com/DarazAPACIG/bnpl-bpo-portal-web.git'
    // The app repo is in the DarazAPACIG org, which the sg616 github-app
    // credential cannot read.
    REPO_CREDS      = 'github-darazapacig'
    SWR_REGISTRY    = 'swr.pk-isb-1.sky47.com'
    IMAGE_NAME      = 'bnpl-bpo-portal-web'
    // Deployment name == container name in k8-sky47-dev/base, which is what
    // makes `kubectl set image deployment/X X=<image>` work.
    K8S_DEPLOYMENT  = 'bnpl-bpo-portal-web'
    // Optional. Leave empty and the map on the onboarding detail screen simply
    // does not render; the rest of the SPA is unaffected. To enable it, create a
    // Jenkins "Secret text" credential and put its id here.
    // Note this value lands in the image history (docker history) and in the
    // client bundle regardless -- a Google Maps *browser* key is restricted by
    // HTTP referrer, not kept secret, so that is expected. Do not put a
    // server-side key here.
    MAPS_CREDENTIAL_ID = ''
    ROLLOUT_TIMEOUT = '180s'
    // Keep docker login state inside the workspace, never in ~jenkins/.docker
    DOCKER_CONFIG   = "${WORKSPACE}/.docker"
  }

  stages {
    stage('Validate') {
      steps {
        script {
          if (registerOnly()) {
            echo 'First build: registering parameters and the app repo refs only.'
            return
          }
          if (!envs().containsKey(params.ENV)) {
            error("Unknown ENV value: ${params.ENV}")
          }
          if (!(ref() ==~ /^[A-Za-z0-9][A-Za-z0-9._\/-]{0,199}$/) || ref().contains('..')) {
            error("Invalid REF: ${ref()}")
          }
          def tag = params.IMAGE_TAG?.trim()
          if (tag && !validTag(tag)) {
            error('IMAGE_TAG must match [A-Za-z0-9_][A-Za-z0-9_.-]{0,127} (Docker tag rules)')
          }
          if (params.ACTION == 'deploy-existing' && !tag) {
            error('ACTION=deploy-existing needs IMAGE_TAG (an image tag that is already in SWR)')
          }
          def cfg = envCfg()
          env.K8S_NAMESPACE             = cfg.namespace
          env.SWR_ORG                   = cfg.swrOrg
          env.VUE_APP_KEYCLOAK_URL      = cfg.keycloakUrl
          env.VUE_APP_KEYCLOAK_REALM    = cfg.keycloakRealm
          env.VUE_APP_KEYCLOAK_CLIENT_ID = cfg.keycloakClient
          env.VUE_APP_BPO_API_BASE_URL  = cfg.apiBaseUrl
          echo "ENV=${params.ENV} namespace=${env.K8S_NAMESPACE} swrOrg=${env.SWR_ORG}"
          echo "Baking: keycloak=${cfg.keycloakUrl} realm=${cfg.keycloakRealm} client=${cfg.keycloakClient} api=${cfg.apiBaseUrl}"
        }
      }
    }

    stage('Checkout app') {
      when { expression { registerOnly() || doing('deploy') } }
      steps {
        dir('app') {
          script {
            def remote = [url: env.APP_REPO,
                          credentialsId: env.REPO_CREDS,
                          refspec: '+refs/heads/*:refs/remotes/origin/* +refs/tags/*:refs/tags/*']
            def spec = isBranch() ? "refs/heads/${refName()}" : "refs/tags/${refName()}"
            checkout([$class: 'GitSCM',
                      branches: [[name: spec]],
                      userRemoteConfigs: [remote]])
          }
        }
      }
    }

    stage('Resolve') {
      steps {
        script {
          if (registerOnly()) {
            currentBuild.description = 'Parameters registered, nothing deployed'
            echo 'Done. Reload the job page and use "Build with Parameters" from now on.'
            return
          }
          def override = params.IMAGE_TAG?.trim()
          if (params.ACTION == 'deploy') {
            def sha = dir('app') { sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim() }
            if (override) {
              env.TAG = override
            } else if (!isBranch()) {
              env.TAG = dockerSafe(refName())
            } else {
              env.TAG = "${dockerSafe(refName())}-${sha}-${env.BUILD_NUMBER}"
            }
            env.SOURCE_REF = "${ref()}@${sha}"
          } else if (params.ACTION == 'deploy-existing') {
            env.TAG = override
            env.SOURCE_REF = 'existing image'
          } else {
            env.TAG = 'n/a'
            env.SOURCE_REF = 'rollout undo'
          }
          if (params.ACTION != 'rollback' && !validTag(env.TAG)) {
            error("Derived image tag '${env.TAG}' is not a valid Docker tag; set IMAGE_TAG explicitly")
          }
          currentBuild.description = "${params.ACTION} ${env.K8S_DEPLOYMENT} @ ${env.TAG} -> ${params.ENV} (${env.SOURCE_REF})"
          echo "Action: ${params.ACTION} | Env: ${params.ENV} | Tag: ${env.TAG} | Source: ${env.SOURCE_REF}"
        }
      }
    }

    stage('SWR login + tag check') {
      when { expression { doing('deploy') || doing('deploy-existing') } }
      steps {
        withCredentials([usernamePassword(credentialsId: 'swr-login',
                                          usernameVariable: 'SWR_USER',
                                          passwordVariable: 'SWR_PASS')]) {
          sh 'echo "$SWR_PASS" | docker login -u "$SWR_USER" --password-stdin "$SWR_REGISTRY"'
        }
        script {
          withEnv(["IMAGE_REF=${imageRef()}"]) {
            def exists = sh(script: 'docker manifest inspect "$IMAGE_REF" > /dev/null 2>&1', returnStatus: true) == 0
            if (params.ACTION == 'deploy' && exists) {
              // Overwriting a tag would make `set image` a no-op: nothing rolls out.
              error("${imageRef()} already exists in SWR. Use ACTION=deploy-existing to roll it out, or pick another IMAGE_TAG.")
            }
            if (params.ACTION == 'deploy-existing' && !exists) {
              error("${imageRef()} not found in SWR")
            }
          }
        }
      }
    }

    stage('Build image') {
      when { expression { doing('deploy') } }
      steps {
        script {
          withEnv(["IMAGE_REF=${imageRef()}"]) {
            if (env.MAPS_CREDENTIAL_ID?.trim()) {
              withCredentials([string(credentialsId: env.MAPS_CREDENTIAL_ID.trim(),
                                      variable: 'MAPS_KEY')]) {
                buildImage()
              }
            } else {
              echo 'MAPS_CREDENTIAL_ID is empty: building without a Google Maps key (the location map will not render).'
              buildImage()
            }
            env.BUILT_IMAGES = "${env.BUILT_IMAGES ?: ''} ${imageRef()}".trim()
          }
        }
      }
    }

    stage('Push to SWR') {
      when { expression { doing('deploy') } }
      steps {
        script {
          withEnv(["IMAGE_REF=${imageRef()}"]) {
            sh 'docker push "$IMAGE_REF"'
          }
        }
      }
    }

    stage('Deploy to CCE') {
      when { expression { (doing('deploy') && params.DEPLOY) || doing('deploy-existing') } }
      steps {
        withCredentials([file(credentialsId: 'cce-kubeconfig', variable: 'KUBECONFIG')]) {
          script {
            withEnv(["SVC=${env.K8S_DEPLOYMENT}", "IMAGE_REF=${imageRef()}",
                     "CHANGE_CAUSE=jenkins #${env.BUILD_NUMBER} ${env.TAG} (${env.SOURCE_REF})"]) {
              def current = sh(script: 'kubectl -n "$K8S_NAMESPACE" get "deployment/$SVC" -o jsonpath="{.spec.template.spec.containers[0].image}"',
                               returnStdout: true).trim()
              if (current == imageRef()) {
                echo "${env.K8S_DEPLOYMENT} already runs ${current}, nothing to roll out"
                return
              }
              // Annotate first: the new ReplicaSet copies it, so `rollout history` shows it.
              sh 'kubectl -n "$K8S_NAMESPACE" annotate "deployment/$SVC" kubernetes.io/change-cause="$CHANGE_CAUSE" --overwrite'
              sh 'kubectl -n "$K8S_NAMESPACE" set image "deployment/$SVC" "$SVC=$IMAGE_REF"'
              try {
                sh 'kubectl -n "$K8S_NAMESPACE" rollout status "deployment/$SVC" --timeout="$ROLLOUT_TIMEOUT"'
              } catch (err) {
                echo "Rollout failed, rolling back to the previous ReplicaSet"
                sh 'kubectl -n "$K8S_NAMESPACE" rollout undo "deployment/$SVC"'
                sh 'kubectl -n "$K8S_NAMESPACE" rollout status "deployment/$SVC" --timeout="$ROLLOUT_TIMEOUT"'
                error("Deploy of ${env.K8S_DEPLOYMENT}:${env.TAG} failed and was rolled back")
              }
            }
          }
        }
      }
    }

    stage('Rollback') {
      when { expression { doing('rollback') } }
      steps {
        withCredentials([file(credentialsId: 'cce-kubeconfig', variable: 'KUBECONFIG')]) {
          withEnv(["SVC=${env.K8S_DEPLOYMENT}"]) {
            sh 'kubectl -n "$K8S_NAMESPACE" rollout undo "deployment/$SVC"'
            sh 'kubectl -n "$K8S_NAMESPACE" rollout status "deployment/$SVC" --timeout="$ROLLOUT_TIMEOUT"'
          }
        }
      }
    }

    stage('Verify') {
      when { expression { doing('rollback') || doing('deploy-existing') || (doing('deploy') && params.DEPLOY) } }
      steps {
        withCredentials([file(credentialsId: 'cce-kubeconfig', variable: 'KUBECONFIG')]) {
          withEnv(["SVC=${env.K8S_DEPLOYMENT}"]) {
            sh '''
              kubectl -n "$K8S_NAMESPACE" get "deployment/$SVC" -o wide
              kubectl -n "$K8S_NAMESPACE" get pods -l "app=$SVC" -o wide
            '''
          }
        }
      }
    }
  }

  post {
    success {
      echo "Done: ${currentBuild.description}"
    }
    always {
      sh 'docker logout "$SWR_REGISTRY" > /dev/null 2>&1 || true'
      // Tagged images are not removed by `image prune`; drop what this build created.
      // BUILT_IMAGES holds validated image refs only, so word splitting is intended.
      sh 'if [ -n "${BUILT_IMAGES:-}" ]; then docker rmi $BUILT_IMAGES || true; fi'
      sh 'docker image prune -f || true'
      cleanWs()
    }
  }
}
