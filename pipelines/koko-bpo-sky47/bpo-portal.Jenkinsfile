// Build -> push to SWR -> deploy the BPO portal BACKEND to Sky47 CCE.
// Job setup: jobs/koko-bpo-sky47-deploy.md   Usage: docs/06-pipeline.md
//
// Credentials (Manage Jenkins > Credentials, see docs/04-credentials.md):
//   swr-login            Username/password  pk-isb-1_<domain>@<AK> / long-term login key
//   cce-kubeconfig       Secret file        CCE internal-endpoint kubeconfig
//   github-darazapacig   Username/password  PAT for the DarazAPACIG org (private repos)
//
// Why this pipeline has two stages the sample project does not:
//
//   1. The service Dockerfile is deliberately UNCHANGED from the Alibaba build.
//      It does `COPY application.properties /app` and `COPY supervisord.conf ...`,
//      and neither file lives in the app repo -- both come from bnpl-build-config
//      at the branch for this environment. So we check that repo out and copy them in.
//      On the dev-sky47 branch application.properties is intentionally EMPTY: real
//      config is injected at runtime through envFrom (see k8-sky47-dev/).
//
//   2. That same Dockerfile starts FROM a JRE and expects a prebuilt target/.
//      This VM has openjdk-25-jre only -- no JDK, no Maven -- so the jar is built
//      inside a maven:3.8-eclipse-temurin-11 container.
//
// Shell safety: user input reaches sh steps only through withEnv + single-quoted
// scripts, and only after the Validate stage has checked it.

// One entry per environment. Adding qa-sky47 later means adding an entry here,
// an overlay directory under k8-sky47-dev/overlays/, and a bnpl-build-config branch.
def envs() {
  return [
    'dev-sky47': [
      namespace   : 'dev-sky47',
      configBranch: 'dev-sky47',
      swrOrg      : 'pk-beta-repo',
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

pipeline {
  agent any

  options {
    timestamps()
    ansiColor('xterm')
    disableConcurrentBuilds()
    buildDiscarder(logRotator(numToKeepStr: '20'))
    timeout(time: 40, unit: 'MINUTES')
    skipDefaultCheckout()
  }

  parameters {
    choice(name: 'ACTION', choices: ['deploy', 'deploy-existing', 'rollback'],
           description: '''deploy = build REF, push a new image, roll it out.
deploy-existing = roll out IMAGE_TAG that is already in SWR (no build). Use it to go back to any older version.
rollback = kubectl rollout undo to the previous revision.''')
    choice(name: 'ENV', choices: ['dev-sky47'],
           description: 'Target environment. Selects the namespace, the bnpl-build-config branch and the SWR org.')
    gitParameter(name: 'REF', type: 'PT_BRANCH_TAG', defaultValue: 'origin/main',
                 branchFilter: 'origin/.*', tagFilter: '*', selectedValue: 'DEFAULT',
                 sortMode: 'DESCENDING_SMART', quickFilterEnabled: true, listSize: '10',
                 useRepository: '.*bnpl-bpo-portal-service.*',
                 description: 'Branch (origin/...) or git tag of the app repo to build. Used by ACTION=deploy only.')
    string(name: 'IMAGE_TAG', defaultValue: '',
           description: '''deploy: optional override. Empty = git tag name, or <branch>-<shortSHA>-<build#> for branches. Must not exist in SWR yet.
deploy-existing: required, an image tag already in SWR (see past build descriptions).''')
    booleanParam(name: 'DEPLOY', defaultValue: true,
           description: 'deploy only: untick to build and push to SWR without rolling out.')
  }

  environment {
    APP_REPO        = 'https://github.com/DarazAPACIG/bnpl-bpo-portal-service.git'
    CONFIG_REPO     = 'https://github.com/DarazAPACIG/bnpl-build-config.git'
    // Both repos are in the DarazAPACIG org, which the sg616 github-app
    // credential cannot read.
    REPO_CREDS      = 'github-darazapacig'
    SWR_REGISTRY    = 'swr.pk-isb-1.sky47.com'
    IMAGE_NAME      = 'bnpl-bpo-portal-service'
    // Deployment name == container name in k8-sky47-dev/base, which is what
    // makes `kubectl set image deployment/X X=<image>` work.
    K8S_DEPLOYMENT  = 'bnpl-bpo-portal'
    // Path inside bnpl-build-config holding this service's files.
    CONFIG_DIR      = 'bnpl-bpo-portal-service'
    MAVEN_IMAGE     = 'maven:3.8-eclipse-temurin-11'
    ROLLOUT_TIMEOUT = '300s'
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
          env.K8S_NAMESPACE = cfg.namespace
          env.CONFIG_BRANCH = cfg.configBranch
          env.SWR_ORG       = cfg.swrOrg
          echo "ENV=${params.ENV} namespace=${env.K8S_NAMESPACE} configBranch=${env.CONFIG_BRANCH} swrOrg=${env.SWR_ORG}"
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

    // The unchanged Dockerfile COPYs application.properties and supervisord.conf
    // from the build context, and neither is in the app repo.
    stage('Fetch build config') {
      when { expression { doing('deploy') } }
      steps {
        dir('cfg') {
          checkout([$class: 'GitSCM',
                    branches: [[name: "refs/heads/${env.CONFIG_BRANCH}"]],
                    userRemoteConfigs: [[url: env.CONFIG_REPO,
                                         credentialsId: env.REPO_CREDS]]])
        }
        sh '''
          set -eu
          cp "cfg/$CONFIG_DIR/application.properties" app/application.properties
          cp "cfg/$CONFIG_DIR/supervisord.conf"       app/supervisord.conf
          echo "application.properties is $(wc -c < app/application.properties) bytes (empty is expected on Sky47 branches)"
        '''
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

    // This VM has openjdk-25-JRE only: it can neither compile nor run a Spring
    // Boot 2.3 / Java 11 build, so Maven runs in a container.
    //   --user  keeps target/ owned by jenkins, so cleanWs() can delete it.
    //           (Without it the artifacts are root-owned and later builds fail.)
    //   ~/.m2   lives outside the workspace so cleanWs() does not wipe the cache,
    //           and MAVEN_CONFIG must be redirected because /root is unwritable
    //           for a non-root user.
    stage('Build jar') {
      when { expression { doing('deploy') } }
      steps {
        sh '''
          set -eu
          mkdir -p "$HOME/.m2"
          docker run --rm \
            --user "$(id -u):$(id -g)" \
            -v "$PWD/app":/src -w /src \
            -v "$HOME/.m2":/m2 -e MAVEN_CONFIG=/m2 \
            "$MAVEN_IMAGE" \
            mvn -B -Dmaven.repo.local=/m2/repository clean package -DskipTests
          # finalName is ${project.name}, and supervisord.conf launches exactly this name.
          test -f "app/target/bnpl-bpo-portal-service.jar"
        '''
      }
    }

    stage('Build image') {
      when { expression { doing('deploy') } }
      steps {
        script {
          withEnv(["IMAGE_REF=${imageRef()}"]) {
            sh 'docker build --pull -t "$IMAGE_REF" app'
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
