pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '10'))
        skipDefaultCheckout(true)
    }

    environment {
        AWS_REGION = "us-east-1"

        IMAGE_NAME = "foodexpress-api"
        IMAGE_TAR  = "foodexpress-api.tar"
        TAG = "${env.BUILD_NUMBER}"

        CONTAINER_NAME = "foodexpress"

        APP_PORT = "7000"
        HOST_PORT = "7000"

        // Important: unique names to avoid duplicate AWS resource errors
        PROJECT_NAME = "foodexpress-${env.BUILD_NUMBER}"
        KEY_NAME = "foodexpress-auto-key-${env.BUILD_NUMBER}"

        TF_DIR = "terraform"
        APP_DIR = "Food-Express-API"
    }

    stages {
        stage("Checkout Code") {
            steps {
                git branch: "main", url: "https://github.com/Dapravith/Task7-Terraform-and-Jenkins.git"
            }
        }

        stage("Verify Project Structure") {
            steps {
                sh '''
                    set -e

                    echo "Checking project structure..."
                    pwd
                    ls -la

                    echo "Checking app directory..."
                    test -d ${APP_DIR}
                    test -f ${APP_DIR}/Dockerfile
                    test -f ${APP_DIR}/package.json

                    echo "Checking terraform directory..."
                    test -d ${TF_DIR}
                    test -f ${TF_DIR}/main.tf
                    test -f ${TF_DIR}/provider.tf
                    test -f ${TF_DIR}/variables.tf
                    test -f ${TF_DIR}/outputs.tf

                    echo "Project structure is valid."
                '''
            }
        }

        stage("Verify Required Tools") {
            steps {
                sh '''
                    set -e

                    echo "Checking required tools..."

                    docker --version
                    terraform version
                    aws --version
                    ssh -V || true

                    echo "Required tools are available."
                '''
            }
        }

        stage("Validate AWS Credentials") {
            steps {
                withCredentials([
                    string(credentialsId: 'aws-access-key-id', variable: 'AWS_ACCESS_KEY_ID'),
                    string(credentialsId: 'aws-secret-access-key', variable: 'AWS_SECRET_ACCESS_KEY')
                ]) {
                    sh '''
                        set -e

                        echo "Validating AWS credentials..."

                        export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID}"
                        export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY}"
                        export AWS_DEFAULT_REGION="${AWS_REGION}"

                        aws sts get-caller-identity

                        echo "AWS credentials are valid."
                    '''
                }
            }
        }

        stage("Generate SSH Key Pair") {
            steps {
                sh '''
                    set -e

                    rm -rf sshkey
                    mkdir -p sshkey

                    echo "Generating SSH key pair..."
                    ssh-keygen -t rsa -b 4096 -f sshkey/id_rsa -N ""

                    chmod 600 sshkey/id_rsa
                    chmod 644 sshkey/id_rsa.pub

                    echo "Public key format:"
                    head -c 20 sshkey/id_rsa.pub
                    echo ""

                    echo "SSH key pair is ready."
                '''
            }
        }

        stage("Validate Node App") {
            steps {
                sh '''
                    set -e

                    echo "Validating Node.js app package.json..."

                    test -f ${APP_DIR}/package.json
                    test -f ${APP_DIR}/index.js

                    if ! grep -q '"start"[[:space:]]*:' ${APP_DIR}/package.json; then
                        echo "ERROR: package.json is missing scripts.start"
                        echo "Please add: \\"start\\": \\"node index.js\\""
                        exit 1
                    fi

                    echo "package.json has start script."
                    echo "Node.js app validation passed."
                '''
            }
        }

        stage("Build Docker Image") {
            steps {
                sh '''
                    set -e

                    echo "Building Docker image from ${APP_DIR}..."

                    docker build \
                        -t ${IMAGE_NAME}:${TAG} \
                        -t ${IMAGE_NAME}:latest \
                        ${APP_DIR}

                    echo "Docker image built successfully:"
                    docker images | grep ${IMAGE_NAME}
                '''
            }
        }

        stage("Save Docker Image to TAR") {
            steps {
                sh '''
                    set -e

                    echo "Saving Docker image to TAR..."
                    rm -f ${IMAGE_TAR}

                    docker save -o ${IMAGE_TAR} ${IMAGE_NAME}:${TAG}

                    echo "Docker TAR file:"
                    ls -lh ${IMAGE_TAR}
                '''
            }
        }

        stage("Terraform Init Validate Plan") {
            steps {
                dir("${TF_DIR}") {
                    withCredentials([
                        string(credentialsId: 'aws-access-key-id', variable: 'AWS_ACCESS_KEY_ID'),
                        string(credentialsId: 'aws-secret-access-key', variable: 'AWS_SECRET_ACCESS_KEY')
                    ]) {
                        sh '''
                            set -e

                            export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID}"
                            export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY}"
                            export AWS_DEFAULT_REGION="${AWS_REGION}"

                            echo "Initializing Terraform..."
                            terraform init -input=false -reconfigure

                            echo "Formatting Terraform files..."
                            terraform fmt -recursive

                            echo "Validating Terraform..."
                            terraform validate

                            echo "Creating Terraform plan..."
                            rm -f tfplan

                            terraform plan -input=false -out=tfplan \
                                -var="aws_region=${AWS_REGION}" \
                                -var="project_name=${PROJECT_NAME}" \
                                -var="key_name=${KEY_NAME}" \
                                -var="public_key=$(cat ../sshkey/id_rsa.pub)"
                        '''
                    }
                }
            }
        }

        stage("Terraform Apply") {
            steps {
                dir("${TF_DIR}") {
                    withCredentials([
                        string(credentialsId: 'aws-access-key-id', variable: 'AWS_ACCESS_KEY_ID'),
                        string(credentialsId: 'aws-secret-access-key', variable: 'AWS_SECRET_ACCESS_KEY')
                    ]) {
                        sh '''
                            set -e

                            export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID}"
                            export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY}"
                            export AWS_DEFAULT_REGION="${AWS_REGION}"

                            echo "Applying Terraform..."
                            terraform apply -auto-approve -input=false tfplan

                            echo "Terraform apply completed."
                        '''
                    }
                }
            }
        }

        stage("Get EC2 Public IP") {
            steps {
                dir("${TF_DIR}") {
                    script {
                        env.EC2_PUBLIC_IP = sh(
                            script: "terraform output -raw public_ip",
                            returnStdout: true
                        ).trim()
                    }
                }

                echo "EC2 Public IP: ${env.EC2_PUBLIC_IP}"
                echo "Application URL: http://${env.EC2_PUBLIC_IP}:${HOST_PORT}"
            }
        }

        stage("Wait for EC2 SSH") {
            steps {
                sh '''
                    set -e

                    echo "Waiting for EC2 SSH..."

                    for i in $(seq 1 60); do
                        if ssh -o StrictHostKeyChecking=no \
                               -o UserKnownHostsFile=/dev/null \
                               -o ConnectTimeout=10 \
                               -i sshkey/id_rsa \
                               ubuntu@${EC2_PUBLIC_IP} "echo READY" >/dev/null 2>&1; then
                            echo "EC2 SSH is ready."
                            exit 0
                        fi

                        echo "EC2 SSH not ready yet. Waiting 10 seconds..."
                        sleep 10
                    done

                    echo "EC2 SSH did not become ready in time."
                    exit 1
                '''
            }
        }

        stage("Wait for Cloud Init") {
            steps {
                sh '''
                    set -e

                    echo "Waiting for cloud-init..."

                    ssh -o StrictHostKeyChecking=no \
                        -o UserKnownHostsFile=/dev/null \
                        -i sshkey/id_rsa \
                        ubuntu@${EC2_PUBLIC_IP} \
                        "sudo cloud-init status --wait"

                    echo "cloud-init completed."
                '''
            }
        }

        stage("Verify Docker on EC2") {
            steps {
                sh '''
                    set -e

                    echo "Checking Docker on EC2..."

                    ssh -o StrictHostKeyChecking=no \
                        -o UserKnownHostsFile=/dev/null \
                        -i sshkey/id_rsa \
                        ubuntu@${EC2_PUBLIC_IP} "
                            set -e

                            sudo docker --version
                            sudo systemctl is-active docker

                            echo 'Docker is ready on EC2.'
                        "
                '''
            }
        }

        stage("Prepare Runtime Env File") {
            steps {
                withCredentials([
                    string(credentialsId: 'foodexpress-jwt-secret', variable: 'JWT_SECRET')
                ]) {
                    sh '''
                        set -e

                        echo "Creating runtime environment file..."

                        cat > foodexpress.env <<EOF
NODE_ENV=production
PORT=${APP_PORT}
JWT_SECRET=${JWT_SECRET}
EOF

                        chmod 600 foodexpress.env

                        echo "Runtime env file created."
                    '''
                }
            }
        }

        stage("Copy Files to EC2") {
            steps {
                sh '''
                    set -e

                    echo "Copying Docker image and env file to EC2..."

                    scp -o StrictHostKeyChecking=no \
                        -o UserKnownHostsFile=/dev/null \
                        -i sshkey/id_rsa \
                        ${IMAGE_TAR} \
                        ubuntu@${EC2_PUBLIC_IP}:/home/ubuntu/

                    scp -o StrictHostKeyChecking=no \
                        -o UserKnownHostsFile=/dev/null \
                        -i sshkey/id_rsa \
                        foodexpress.env \
                        ubuntu@${EC2_PUBLIC_IP}:/home/ubuntu/

                    echo "Files copied to EC2."
                '''
            }
        }

        stage("Deploy Container on EC2") {
            steps {
                sh '''
                    set -e

                    echo "Deploying container on EC2..."

                    ssh -o StrictHostKeyChecking=no \
                        -o UserKnownHostsFile=/dev/null \
                        -i sshkey/id_rsa \
                        ubuntu@${EC2_PUBLIC_IP} "
                            set -e

                            echo 'Files in /home/ubuntu:'
                            ls -lh /home/ubuntu/

                            echo 'Loading Docker image...'
                            sudo docker load -i /home/ubuntu/${IMAGE_TAR}

                            echo 'Stopping old containers if they exist...'
                            sudo docker stop ${CONTAINER_NAME} || true
                            sudo docker rm ${CONTAINER_NAME} || true
                            sudo docker stop foodexpress-api || true
                            sudo docker rm foodexpress-api || true

                            echo 'Starting new container on port ${HOST_PORT}:${APP_PORT}...'
                            sudo docker run -d \
                                --name ${CONTAINER_NAME} \
                                --restart unless-stopped \
                                -p ${HOST_PORT}:${APP_PORT} \
                                --env-file /home/ubuntu/foodexpress.env \
                                ${IMAGE_NAME}:${TAG}

                            echo 'Running containers:'
                            sudo docker ps

                            echo 'Container logs:'
                            sudo docker logs ${CONTAINER_NAME} --tail 50 || true

                            echo 'Cleaning temporary TAR file...'
                            rm -f /home/ubuntu/${IMAGE_TAR}

                            echo 'Deployment on EC2 completed.'
                        "
                '''
            }
        }

        stage("Verify Application") {
            steps {
                sh '''
                    set -e

                    APP_URL="http://${EC2_PUBLIC_IP}:${HOST_PORT}/health"

                    echo "Checking application health..."
                    echo "Testing ${APP_URL}"

                    for i in $(seq 1 30); do
                        if curl -fsS "${APP_URL}"; then
                            echo ""
                            echo "Application is healthy."
                            exit 0
                        fi

                        echo "Application not ready yet. Waiting 5 seconds..."
                        sleep 5
                    done

                    echo "Application did not become ready in time."

                    echo "Debugging from EC2..."
                    ssh -o StrictHostKeyChecking=no \
                        -o UserKnownHostsFile=/dev/null \
                        -i sshkey/id_rsa \
                        ubuntu@${EC2_PUBLIC_IP} "
                            sudo docker ps -a || true
                            sudo docker logs ${CONTAINER_NAME} --tail 100 || true
                            sudo ss -tulnp | grep -E ':${HOST_PORT}|:${APP_PORT}' || true
                        "

                    exit 1
                '''
            }
        }
    }

    post {
        success {
            echo "Deployment successful."
            echo "Application URL: http://${EC2_PUBLIC_IP}:${HOST_PORT}"
            echo "Health Check URL: http://${EC2_PUBLIC_IP}:${HOST_PORT}/health"
        }

        failure {
            echo "Deployment failed. Please check Jenkins console output."
        }

        always {
            sh '''
                rm -f ${IMAGE_TAR} || true
                rm -f foodexpress.env || true
            '''
        }
    }
}