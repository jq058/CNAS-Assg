def appImage

pipeline {
    agent any

    options {
        disableConcurrentBuilds()
        timestamps()
        timeout(time: 45, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '20', artifactNumToKeepStr: '10'))
        skipDefaultCheckout(true)
    }

    environment {
        DOCKER_REGISTRY_CREDENTIALS_ID = 'docker-hub-credentials'
        DOCKER_IMAGE_NAME = 'sinoceratops/cnas-php-app'
        KUBERNETES_CREDENTIALS_ID = 'kubeconfig-cluster-secret'
        DB_CREDENTIALS_ID = 'cnas-db-credentials'
        MYSQL_ROOT_PASSWORD_CREDENTIALS_ID = 'cnas-mysql-root-password'
        REDIS_PASSWORD_CREDENTIALS_ID = 'cnas-redis-password'
        K8S_NAMESPACE = 'cnas'
        DEPLOYMENT_NAME = 'php-app'
        DEPLOY_STARTED = 'false'
    }

    stages {
        stage('Checkout and identify source') {
            steps {
                checkout scm
                script {
                    env.GIT_SHA = sh(
                        script: 'git rev-parse --short=12 HEAD',
                        returnStdout: true
                    ).trim()
                    env.IMAGE_TAG = "${env.BUILD_NUMBER}-${env.GIT_SHA}"
                    currentBuild.displayName = "#${env.BUILD_NUMBER} ${env.GIT_SHA}"
                }
                sh 'test -z "$(git status --porcelain)"'
            }
        }

        stage('Lint and unit tests') {
            steps {
                sh '''
                    set -eu
                    docker run --rm \
                      -v "$WORKSPACE:/workspace:ro" \
                      -w /workspace \
                      php:8.2-cli-alpine \
                      sh -c 'find php-app tests/php -type f -name "*.php" -print0 | xargs -0 -n1 php -l'

                    docker run --rm \
                      -v "$WORKSPACE:/workspace:ro" \
                      -w /workspace \
                      php:8.2-cli-alpine \
                      php tests/php/run.php

                    DB_PASSWORD=ci-validation-only \
                    MYSQL_ROOT_PASSWORD=ci-validation-only \
                    REDIS_PASSWORD=ci-validation-only \
                      docker compose config --quiet
                    kubectl kustomize k8s > rendered-kubernetes.yaml
                '''
            }
        }

        stage('Repository security gates') {
            steps {
                sh '''
                    set -eu
                    trivy fs \
                      --exit-code 1 \
                      --severity HIGH,CRITICAL \
                      --scanners vuln,misconfig,secret \
                      --skip-files tests/k8s/policy-deny-latest.yaml \
                      --skip-files tests/k8s/policy-disallow-privileged.yaml \
                      --skip-files tests/k8s/policy-require-nonroot.yaml \
                      --skip-files tests/k8s/policy-require-resources.yaml \
                      --no-progress \
                      .
                '''
            }
        }

        stage('Build immutable image') {
            steps {
                script {
                    appImage = docker.build("${DOCKER_IMAGE_NAME}:${IMAGE_TAG}")
                }
            }
        }

        stage('Image security and SBOM') {
            steps {
                sh '''
                    set -eu
                    trivy image \
                      --exit-code 1 \
                      --severity HIGH,CRITICAL \
                      --ignore-unfixed \
                      --no-progress \
                      "$DOCKER_IMAGE_NAME:$IMAGE_TAG"

                    trivy image \
                      --format cyclonedx \
                      --output sbom.cdx.json \
                      "$DOCKER_IMAGE_NAME:$IMAGE_TAG"
                '''
                archiveArtifacts artifacts: 'sbom.cdx.json,rendered-kubernetes.yaml', fingerprint: true
            }
        }

        stage('Push immutable image') {
            steps {
                script {
                    docker.withRegistry('', env.DOCKER_REGISTRY_CREDENTIALS_ID) {
                        appImage.push()
                    }
                }
            }
        }

        stage('Bootstrap platform controls') {
            steps {
                withKubeConfig([credentialsId: env.KUBERNETES_CREDENTIALS_ID]) {
                    sh '''
                        set -eu
                        bash k8s/scripts/install-platform.sh
                        kubectl apply -f k8s/00-namespace.yaml
                        bash k8s/scripts/bootstrap-local-tls.sh
                    '''
                }
            }
        }

        stage('Inject runtime secrets') {
            steps {
                withKubeConfig([credentialsId: env.KUBERNETES_CREDENTIALS_ID]) {
                    withCredentials([
                        usernamePassword(
                            credentialsId: env.DB_CREDENTIALS_ID,
                            usernameVariable: 'CNAS_DB_USER',
                            passwordVariable: 'CNAS_DB_PASSWORD'
                        ),
                        string(
                            credentialsId: env.MYSQL_ROOT_PASSWORD_CREDENTIALS_ID,
                            variable: 'CNAS_MYSQL_ROOT_PASSWORD'
                        ),
                        string(
                            credentialsId: env.REDIS_PASSWORD_CREDENTIALS_ID,
                            variable: 'CNAS_REDIS_PASSWORD'
                        )
                    ]) {
                        sh '''
                            set +x
                            kubectl create secret generic cnas-secret \
                              --namespace "$K8S_NAMESPACE" \
                              --from-literal=DB_USER="$CNAS_DB_USER" \
                              --from-literal=DB_PASSWORD="$CNAS_DB_PASSWORD" \
                              --from-literal=MYSQL_ROOT_PASSWORD="$CNAS_MYSQL_ROOT_PASSWORD" \
                              --from-literal=REDIS_PASSWORD="$CNAS_REDIS_PASSWORD" \
                              --dry-run=client -o yaml | kubectl apply -f -
                            set -x
                            kubectl get secret cnas-secret -n "$K8S_NAMESPACE" -o name
                        '''
                    }
                }
            }
        }

        stage('Deploy exact build') {
            steps {
                withKubeConfig([credentialsId: env.KUBERNETES_CREDENTIALS_ID]) {
                    script {
                        env.DEPLOY_STARTED = 'true'
                        sh 'mkdir -p k8s/overlays/ci-runtime'
                        writeFile(
                            file: 'k8s/overlays/ci-runtime/kustomization.yaml',
                            text: """apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../..
images:
  - name: sinoceratops/cnas-php-app
    newName: ${env.DOCKER_IMAGE_NAME}
    newTag: ${env.IMAGE_TAG}
"""
                        )
                    }
                    sh '''
                        set -eu
                        kubectl apply -f k8s/kyverno/
                        kubectl apply -k k8s/overlays/ci-runtime
                        kubectl wait \
                          --for=condition=complete \
                          job/db-migration-v2 \
                          -n "$K8S_NAMESPACE" \
                          --timeout=5m
                        kubectl annotate deployment "$DEPLOYMENT_NAME" \
                          -n "$K8S_NAMESPACE" \
                          kubernetes.io/change-cause="git=$GIT_SHA image=$DOCKER_IMAGE_NAME:$IMAGE_TAG" \
                          cnas.assignment/git-sha="$GIT_SHA" \
                          cnas.assignment/image="$DOCKER_IMAGE_NAME:$IMAGE_TAG" \
                          --overwrite
                        kubectl rollout status deployment/"$DEPLOYMENT_NAME" \
                          -n "$K8S_NAMESPACE" \
                          --timeout=5m
                    '''
                }
            }
        }

        stage('Verify deployment') {
            steps {
                withKubeConfig([credentialsId: env.KUBERNETES_CREDENTIALS_ID]) {
                    sh '''
                        set -eu
                        kubectl wait \
                          --for=condition=Ready \
                          pod \
                          -l app=php-app \
                          -n "$K8S_NAMESPACE" \
                          --timeout=180s
                        bash scripts/ci-smoke-test.sh
                        kubectl get pods,svc,deployment,hpa,pdb \
                          -n "$K8S_NAMESPACE" \
                          -o wide
                        kubectl get deployment "$DEPLOYMENT_NAME" \
                          -n "$K8S_NAMESPACE" \
                          -o jsonpath='{.spec.template.spec.containers[?(@.name=="php-app")].image}' \
                          | grep -F "$DOCKER_IMAGE_NAME:$IMAGE_TAG"
                    '''
                }
            }
        }
    }

    post {
        failure {
            script {
                if (env.DEPLOY_STARTED == 'true') {
                    withKubeConfig([credentialsId: env.KUBERNETES_CREDENTIALS_ID]) {
                        sh '''
                            kubectl rollout undo deployment/"$DEPLOYMENT_NAME" \
                              -n "$K8S_NAMESPACE" || true
                            kubectl rollout status deployment/"$DEPLOYMENT_NAME" \
                              -n "$K8S_NAMESPACE" \
                              --timeout=3m || true
                        '''
                    }
                } else {
                    echo 'Failure occurred before deployment; no rollback was attempted.'
                }
            }
        }
        always {
            archiveArtifacts artifacts: 'sbom.cdx.json,rendered-kubernetes.yaml,test-results/**/*', allowEmptyArchive: true, fingerprint: true
            cleanWs()
        }
        success {
            echo "Deployed ${DOCKER_IMAGE_NAME}:${IMAGE_TAG} from commit ${GIT_SHA}."
        }
    }
}
