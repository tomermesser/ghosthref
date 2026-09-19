pipeline {
    agent any

    environment {
        IMAGE_NAME = "tomermes/ghosthref-bouncer"
        SHORT_SHA  = "${env.GIT_COMMIT.take(7)}"
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        // Runs before Build/Deploy, so bad code or a bad robots.txt edit
        // never reaches the cluster. Tests against the real data host.
        stage('Test') {
            steps {
                withCredentials([string(credentialsId: 'data-host-ip', variable: 'DATA_HOST_IP')]) {
                    sh '''
                        docker run --rm \
                            -v $(pwd):/repo -w /repo/bouncer \
                            -e REDIS_HOST=$DATA_HOST_IP -e PG_HOST=$DATA_HOST_IP \
                            -e PG_USER=ghosthref -e PG_PASSWORD=ghosthref -e PG_DATABASE=ghosthref \
                            -e ROBOTS_TXT_PATH=/repo/robots.txt \
                            node:20-alpine sh -c "npm install && npm test"
                    '''
                }
            }
        }

        stage('Compile robots.txt') {
            steps {
                withCredentials([file(credentialsId: 'k8s-kubeconfig', variable: 'KUBECONFIG_FILE')]) {
                    sh '''
                        export KUBECONFIG="$KUBECONFIG_FILE"
                        kubectl create configmap ghosthref-config \
                            --from-file=robots.txt=robots.txt \
                            --from-file=nginx.conf=nginx/nginx.conf \
                            --from-file=index.html=site/index.html \
                            --dry-run=client -o yaml | kubectl apply -f -
                    '''
                }
            }
        }

        stage('Build') {
            steps {
                sh "docker build -t ${IMAGE_NAME}:${SHORT_SHA} bouncer/"
            }
        }

        stage('Push') {
            steps {
                withCredentials([usernamePassword(
                    credentialsId: 'dockerhub-creds',
                    usernameVariable: 'DOCKERHUB_USER',
                    passwordVariable: 'DOCKERHUB_PASS'
                )]) {
                    sh '''
                        echo "$DOCKERHUB_PASS" | docker login -u "$DOCKERHUB_USER" --password-stdin
                        docker push ${IMAGE_NAME}:${SHORT_SHA}
                    '''
                }
            }
        }

        stage('Deploy') {
            steps {
                withCredentials([file(credentialsId: 'k8s-kubeconfig', variable: 'KUBECONFIG_FILE')]) {
                    sh '''
                        export KUBECONFIG="$KUBECONFIG_FILE"
                        kubectl set image deployment/bouncer bouncer=${IMAGE_NAME}:${SHORT_SHA}
                        kubectl rollout restart deployment/nginx-edge
                        kubectl rollout status deployment/bouncer --timeout=120s
                        kubectl rollout status deployment/nginx-edge --timeout=120s
                    '''
                }
            }
        }
    }

    post {
        always {
            sh 'docker logout || true'
        }
    }
}
