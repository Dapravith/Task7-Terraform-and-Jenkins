pipeline {
    agent any

    environment {
        AWS_REGION = "us-east-1"

        IMAGE_NAME = "foodexpress-api"
        IMAGE_TAR  = "foodexpress-api.tar"
        TAG = "${env.BUILD_NUMBER}"

        CONTAINER_NAME = "foodexpress"
        APP_PORT = "7000"
        HOST_PORT = "80"

        KEY_NAME = "foodexpress-auto-key"
        TF_DIR = "terraform"

        // If Dockerfile is inside app folder, keep "app"
        // If Dockerfile is in root folder, change to "."
        APP_DIR = "app"
    }

    stages {

        stage("Checkout Code") {
            steps {
                git branch: "main", url: "https://github.com/Dapravith/Task7-Terraform-and-Jenkins.git"
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
                withCredentials([[
                    $class: 'AmazonWebServicesCredentialsBinding',
                    credentialsId: 'aws-creds'
                ]]) {
                    sh '''
                        set -e

                        echo "Validating AWS credentials..."
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

                    mkdir -p sshkey

                    if [ ! -f sshkey/id_rsa ]; then
                        echo "Generating SSH key pair..."
                        ssh-keygen -t rsa -b 4096 -f sshkey/id_rsa -N ""
                    else
                        echo "SSH key pair already exists."
                    fi

                    chmod 600 sshkey/id_rsa
                    chmod 644 sshkey/id_rsa.pub

                    echo "SSH key pair is ready."
                '''
            }
        }

        stage("Build Docker Image") {
            steps {
                sh '''
                    set -e

                    echo "Building Docker image..."
                    docker build -t ${IMAGE_NAME}:${TAG} ${APP_DIR}
                    docker tag ${IMAGE_NAME}:${TAG} ${IMAGE_NAME}:latest

                    echo "Docker image built successfully:"
                    docker images | grep ${IMAGE_NAME}
                '''
            }
        }

        stage("Save Docker Image to TAR") {
            steps {
                sh '''
                    set -e

                    echo "Saving Docker image to tar..."
                    rm -f ${IMAGE_TAR}

                    docker save -o ${IMAGE_TAR} ${IMAGE_NAME}:${TAG}

                    echo "Docker image tar file:"
                    ls -lh ${IMAGE_TAR}
                '''
            }
        }

        stage("Terraform Init Validate Plan") {
            steps {
                dir("${TF_DIR}") {
                    withCredentials([[
                        $class: 'AmazonWebServicesCredentialsBinding',
                        credentialsId: 'aws-creds'
                    ]]) {
                        sh '''
                            set -e

                            echo "Initializing Terraform..."
                            terraform init -input=false

                            echo "Formatting Terraform files..."
                            terraform fmt -recursive

                            echo "Validating Terraform..."
                            terraform validate

                            echo "Creating Terraform plan..."
                            terraform plan -input=false -out=tfplan \
                                -var="aws_region=${AWS_REGION}" \
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
                    withCredentials([[
                        $class: 'AmazonWebServicesCredentialsBinding',
                        credentialsId: 'aws-creds'
                    ]]) {
                        sh '''
                            set -e

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

                            docker --version || sudo docker --version
                            sudo systemctl is-active docker

                            echo 'Docker is ready.'
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

                        echo "Creating runtime env file..."

                        cat > foodexpress.env <<EOF
NODE_ENV=production
PORT=${APP_PORT}
JWT_SECRET=${JWT_SECRET}
EOF

                        chmod 600 foodexpress.env
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

                            echo 'Loading Docker image...'
                            sudo docker load -i /home/ubuntu/${IMAGE_TAR}

                            echo 'Stopping old container if exists...'
                            sudo docker stop ${CONTAINER_NAME} || true
                            sudo docker rm ${CONTAINER_NAME} || true

                            echo 'Starting new container...'
                            sudo docker run -d \
                                --name ${CONTAINER_NAME} \
                                --restart unless-stopped \
                                -p ${HOST_PORT}:${APP_PORT} \
                                --env-file /home/ubuntu/foodexpress.env \
                                ${IMAGE_NAME}:${TAG}

                            echo 'Running containers:'
                            sudo docker ps

                            echo 'Container logs:'
                            sudo docker logs ${CONTAINER_NAME} --tail 30 || true

                            echo 'Cleaning temporary tar file...'
                            rm -f /home/ubuntu/${IMAGE_TAR}
                        "
                '''
            }
        }

        stage("Verify Application") {
            steps {
                sh '''
                    set -e

                    echo "Checking application health..."

                    for i in $(seq 1 20); do
                        if curl -fsS http://${EC2_PUBLIC_IP}/health; then
                            echo "Application is healthy."
                            exit 0
                        fi

                        echo "Application not ready yet. Waiting 5 seconds..."
                        sleep 5
                    done

                    echo "Application did not become ready in time."
                    exit 1
                '''
            }
        }
    }

    post {
        success {
            echo "Deployment successful."
            echo "Application URL: http://${EC2_PUBLIC_IP}"
            echo "Health Check URL: http://${EC2_PUBLIC_IP}/health"
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