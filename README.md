# Task 7: Terraform and Jenkins CI/CD Deployment

This repository contains a complete CI/CD implementation for deploying a **FoodExpress Node.js API** to **AWS EC2** using **Jenkins**, **Terraform**, **Docker**, and **GitHub**.

The pipeline automatically pulls the application source code from GitHub, builds a Docker image, provisions a new EC2 instance using Terraform, copies the Docker image to the EC2 instance, runs the container, and verifies the API through the EC2 public IP.

---

## Table of Contents

- [Project Objective](#project-objective)
- [Architecture Overview](#architecture-overview)
- [Repository Structure](#repository-structure)
- [Technology Stack](#technology-stack)
- [Prerequisites](#prerequisites)
- [Application Configuration](#application-configuration)
- [Docker Configuration](#docker-configuration)
- [Terraform Configuration](#terraform-configuration)
- [Jenkins Server Setup](#jenkins-server-setup)
- [Jenkins Credentials](#jenkins-credentials)
- [Jenkins Pipeline Flow](#jenkins-pipeline-flow)
- [How to Run the Pipeline](#how-to-run-the-pipeline)
- [How to Verify the Deployment](#how-to-verify-the-deployment)
- [Postman Testing](#postman-testing)
- [Common Errors and Fixes](#common-errors-and-fixes)
- [Useful Commands](#useful-commands)
- [Required Assignment Screenshots](#required-assignment-screenshots)
- [Final Result](#final-result)

---

## Project Objective

The goal of this task is to implement a complete DevOps deployment workflow:

1. Jenkins pulls the source code from GitHub.
2. Jenkins builds the FoodExpress API Docker image.
3. Jenkins runs Terraform to create an AWS EC2 instance.
4. Terraform creates:
   - EC2 instance
   - Security group
   - SSH key pair
5. Jenkins copies the Docker image to the new EC2 instance.
6. Jenkins runs the Docker container on the EC2 instance.
7. The API becomes accessible using the EC2 public IP.

Final API format:

```bash
http://EC2_PUBLIC_IP:7000/health
```

---

## Architecture Overview

```text
Developer
   |
   | git push
   v
GitHub Repository
   |
   | Jenkins Pipeline Checkout
   v
Jenkins Server EC2
   |
   | Build Docker image
   | Run Terraform
   | Copy Docker image by SCP
   v
AWS EC2 App Server
   |
   | Run Docker container
   v
FoodExpress API
   |
   v
Postman / Browser / curl
```

Important separation:

```text
Jenkins EC2
- Runs Jenkins
- Runs Docker build
- Runs Terraform
- Runs AWS CLI
- Connects to App EC2 by SSH

App EC2
- Created by Terraform
- Runs Docker only
- Does not run Jenkins
- Does not need to clone the GitHub repo
```

---

## Repository Structure

```text
Task7-Terraform-and-Jenkins/
├── Food-Express-API/
│   ├── Dockerfile
│   ├── index.js
│   ├── package.json
│   └── package-lock.json
│
├── terraform/
│   ├── main.tf
│   ├── outputs.tf
│   ├── provider.tf
│   ├── user_data.sh
│   └── variables.tf
│
├── deploy.sh
├── Jenkinsfile
├── .gitignore
├── LICENSE
└── README.md
```

---

## Technology Stack

| Tool | Purpose |
|---|---|
| GitHub | Source code repository |
| Jenkins | CI/CD automation server |
| Docker | Build and run the API container |
| Terraform | Provision AWS infrastructure |
| AWS EC2 | Host the application container |
| AWS Security Group | Control inbound and outbound traffic |
| Node.js / Express | FoodExpress API backend |
| Postman | Test deployed API endpoint |

---

## Prerequisites

Before running the pipeline, prepare the following:

### Local machine

- Git installed
- GitHub repository created
- Project pushed to GitHub

### Jenkins EC2 server

Install:

- Java
- Jenkins
- Docker
- Terraform
- AWS CLI
- Git
- SSH / SCP

### AWS account

Prepare:

- AWS Access Key ID
- AWS Secret Access Key
- AWS Session Token, if using AWS Academy or temporary credentials
- AWS region, for example `us-east-1`

---

## Application Configuration

The FoodExpress API runs on port `7000`.

### Required `package.json`

The application must include a `start` script. Without this script, Docker will fail with:

```text
npm error Missing script: "start"
```

Correct configuration:

```json
{
  "name": "task7-terraform-and-jenkins",
  "version": "1.0.0",
  "description": "FoodExpress API for Terraform and Jenkins deployment",
  "main": "index.js",
  "scripts": {
    "start": "node index.js",
    "test": "echo \"No tests configured\" && exit 0"
  },
  "keywords": [],
  "author": "Dapravith",
  "license": "ISC",
  "dependencies": {
    "bcryptjs": "^3.0.3",
    "express": "^5.2.1",
    "jsonwebtoken": "^9.0.3"
  }
}
```

### Required Express listen configuration

In `Food-Express-API/index.js`, the server should listen on `0.0.0.0` so it is reachable from outside the container.

```javascript
const PORT = process.env.PORT || 7000;

app.listen(PORT, "0.0.0.0", () => {
  console.log(`FoodExpress API running on port ${PORT}`);
});
```

### Required health endpoint

```javascript
app.get("/health", (req, res) => {
  res.status(200).json({
    status: "healthy",
    service: "FoodExpress API"
  });
});
```

---

## Docker Configuration

The Dockerfile is located at:

```text
Food-Express-API/Dockerfile
```

Example Dockerfile:

```dockerfile
FROM node:18-alpine

WORKDIR /app

ENV NODE_ENV=production
ENV PORT=7000

COPY package*.json ./

RUN npm ci --omit=dev && npm cache clean --force

COPY . .

RUN addgroup -S appgroup && adduser -S appuser -G appgroup

USER appuser

EXPOSE 7000

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD wget -qO- http://127.0.0.1:7000/health || exit 1

CMD ["npm", "start"]
```

### Test Docker locally

From the repository root:

```bash
docker rm -f foodexpress || true

docker build -t foodexpress-api:v1 ./Food-Express-API

docker run -d \
  --name foodexpress \
  -p 7000:7000 \
  -e PORT=7000 \
  -e JWT_SECRET=my_secret_key \
  foodexpress-api:v1

curl http://localhost:7000/health
```

Expected response:

```json
{
  "status": "healthy",
  "service": "FoodExpress API"
}
```

---

## Terraform Configuration

Terraform files are located in:

```text
terraform/
```

Terraform creates:

- EC2 instance
- Security group
- SSH key pair
- Public IP output
- App URL output
- Health check URL output

### Required ports

The application EC2 security group should allow:

| Port | Purpose |
|---|---|
| 22 | SSH from Jenkins |
| 7000 | FoodExpress API |

Jenkins EC2 security group should allow:

| Port | Purpose |
|---|---|
| 22 | SSH |
| 8080 | Jenkins web UI |

Do not add Jenkins port `8080` to the application EC2 unless Jenkins is installed there. The app EC2 only needs Docker and port `7000`.

### Example Terraform variables

```hcl
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "foodexpress"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t2.micro"
}

variable "key_name" {
  description = "EC2 key pair name"
  type        = string
  default     = "foodexpress-auto-key"
}

variable "public_key" {
  description = "Public SSH key used to access EC2"
  type        = string
  sensitive   = true
}
```

### Important Terraform naming rule

To avoid duplicate AWS resource errors, the Jenkinsfile uses unique names per build:

```groovy
PROJECT_NAME = "foodexpress-${env.BUILD_NUMBER}"
KEY_NAME = "foodexpress-auto-key-${env.BUILD_NUMBER}"
```

This prevents errors like:

```text
InvalidKeyPair.Duplicate: The keypair already exists
InvalidGroup.Duplicate: The security group already exists
```

---

## Jenkins Server Setup

Run `deploy.sh` only on the Jenkins EC2 server.

Do not run `deploy.sh` on the app EC2.

### Run setup script

SSH into the Jenkins EC2 server:

```bash
ssh -i your-key.pem ubuntu@JENKINS_EC2_PUBLIC_IP
```

Create or copy the setup script:

```bash
nano deploy.sh
```

Make it executable:

```bash
chmod +x deploy.sh
```

Run it:

```bash
sudo bash deploy.sh
```

Open Jenkins:

```text
http://JENKINS_EC2_PUBLIC_IP:8080
```

### Jenkins server Docker permission

If Jenkins cannot run Docker commands, run:

```bash
sudo usermod -aG docker jenkins
sudo systemctl restart jenkins
```

For assignment testing only, if Docker permission still fails:

```bash
sudo chmod 666 /var/run/docker.sock
sudo systemctl restart jenkins
```

---

## Jenkins Credentials

Go to:

```text
Manage Jenkins → Credentials → System → Global credentials → Add Credentials
```

Create these credentials exactly:

| Credential ID | Kind | Value |
|---|---|---|
| `aws-access-key-id` | Secret text | AWS Access Key ID |
| `aws-secret-access-key` | Secret text | AWS Secret Access Key |
| `foodexpress-jwt-secret` | Secret text | JWT secret for the API |

If using AWS Academy or temporary AWS credentials, also create:

| Credential ID | Kind | Value |
|---|---|---|
| `aws-session-token` | Secret text | AWS Session Token |

For the GitHub repository section in Jenkins Pipeline configuration, use:

```text
Credentials: none
```

This is correct if the repository is public. AWS credentials do not appear in the Git credentials dropdown because they are used inside `Jenkinsfile` through `withCredentials(...)`.

---

## Jenkins Pipeline Flow

The Jenkins pipeline performs these stages:

```text
Checkout Code
Verify Project Structure
Verify Required Tools
Validate AWS Credentials
Generate SSH Key Pair
Validate Node App
Build Docker Image
Save Docker Image to TAR
Terraform Init Validate Plan
Terraform Apply
Get EC2 Public IP
Wait for EC2 SSH
Wait for Cloud Init
Verify Docker on EC2
Prepare Runtime Env File
Copy Files to EC2
Deploy Container on EC2
Verify Application
```

### Pipeline responsibilities

| Stage | Purpose |
|---|---|
| Checkout Code | Clone the repository from GitHub |
| Verify Project Structure | Confirm required folders and files exist |
| Verify Required Tools | Check Docker, Terraform, AWS CLI, SSH |
| Validate AWS Credentials | Confirm Jenkins can access AWS |
| Generate SSH Key Pair | Create temporary key for Jenkins to access app EC2 |
| Validate Node App | Confirm package.json has a start script |
| Build Docker Image | Build FoodExpress API Docker image |
| Save Docker Image to TAR | Export Docker image as a `.tar` file |
| Terraform Init Validate Plan | Initialize, validate, and plan infrastructure |
| Terraform Apply | Create AWS EC2 resources |
| Get EC2 Public IP | Read EC2 public IP from Terraform output |
| Wait for EC2 SSH | Wait until EC2 accepts SSH |
| Wait for Cloud Init | Wait until EC2 initialization finishes |
| Verify Docker on EC2 | Confirm Docker is installed and running |
| Prepare Runtime Env File | Create environment file for container |
| Copy Files to EC2 | Copy Docker image and env file to EC2 |
| Deploy Container on EC2 | Load image and run container on port `7000` |
| Verify Application | Test `/health` endpoint through EC2 public IP |

---

## How to Run the Pipeline

### Step 1: Create Jenkins Pipeline job

In Jenkins:

```text
New Item → Pipeline → OK
```

Example job name:

```text
Food-express-api
```

### Step 2: Configure pipeline from GitHub

In the Pipeline section:

```text
Definition: Pipeline script from SCM
SCM: Git
Repository URL: https://github.com/Dapravith/Task7-Terraform-and-Jenkins.git
Credentials: none
Branch Specifier: */main
Script Path: Jenkinsfile
```

Click:

```text
Save
```

### Step 3: Run build

```text
Food-express-api → Build Now
```

Open:

```text
Build Number → Console Output
```

Watch until the final stage succeeds:

```text
Verify Application
```

---

## How to Verify the Deployment

After successful deployment, Jenkins prints:

```text
Application URL: http://EC2_PUBLIC_IP:7000
Health Check URL: http://EC2_PUBLIC_IP:7000/health
```

Example:

```text
http://18.212.231.44:7000/health
```

Test from terminal:

```bash
curl http://EC2_PUBLIC_IP:7000/health
```

Expected response:

```json
{
  "status": "healthy",
  "service": "FoodExpress API"
}
```

---

## Postman Testing

Use this request:

```http
GET http://EC2_PUBLIC_IP:7000/health
```

Important:

```text
Body: none
```

Do not send JSON body to `/health`.

Expected response:

```json
{
  "status": "healthy",
  "service": "FoodExpress API"
}
```

---

## Common Errors and Fixes

### 1. `npm error Missing script: "start"`

Cause:

`package.json` does not have a start script.

Fix:

```json
"scripts": {
  "start": "node index.js"
}
```

---

### 2. `node: not found` in Jenkins

Cause:

Jenkins server does not have Node.js installed.

Fix:

Do not run Node commands directly in Jenkins unless Node is installed. The application should build inside Docker using:

```dockerfile
FROM node:18-alpine
```

For Jenkins validation, use shell commands such as `grep` instead of `node -e`.

---

### 3. `InvalidKeyPair.Duplicate`

Cause:

AWS key pair with the same name already exists.

Fix:

Use unique key names per Jenkins build:

```groovy
KEY_NAME = "foodexpress-auto-key-${env.BUILD_NUMBER}"
```

---

### 4. `InvalidGroup.Duplicate`

Cause:

Security group with the same name already exists.

Fix:

Use unique project names per Jenkins build:

```groovy
PROJECT_NAME = "foodexpress-${env.BUILD_NUMBER}"
```

---

### 5. `InvalidClientTokenId`

Cause:

AWS credentials are invalid, expired, or missing session token.

Fix:

Check credentials:

```bash
aws sts get-caller-identity
```

If using AWS Academy, add `aws-session-token` in Jenkins credentials and export it inside the Jenkinsfile.

---

### 6. `Connection refused` on port `7000`

Possible causes:

- Docker container is restarting
- API is not listening on `0.0.0.0`
- Missing package start script
- Port `7000` is not open in Security Group
- Container did not start correctly

Debug on app EC2:

```bash
sudo docker ps -a
sudo docker logs foodexpress --tail 100
sudo ss -tulnp | grep 7000
curl http://localhost:7000/health
```

---

### 7. Jenkins cannot run Docker

Cause:

Jenkins user does not have permission to access Docker socket.

Fix:

```bash
sudo usermod -aG docker jenkins
sudo systemctl restart jenkins
```

For assignment testing only:

```bash
sudo chmod 666 /var/run/docker.sock
sudo systemctl restart jenkins
```

---

## Useful Commands

### Check Jenkins server tools

```bash
docker --version
terraform version
aws --version
git --version
ssh -V
```

### Check AWS credentials

```bash
aws sts get-caller-identity
```

### Check Docker container on app EC2

```bash
sudo docker ps -a
sudo docker logs foodexpress --tail 100
sudo docker images
```

### Stop and remove container manually

```bash
sudo docker stop foodexpress || true
sudo docker rm foodexpress || true
```

### Test API locally on app EC2

```bash
curl http://localhost:7000/health
```

### Test API publicly

```bash
curl http://EC2_PUBLIC_IP:7000/health
```

### Clean local Docker image on Jenkins server

```bash
docker rmi foodexpress-api:latest || true
```

---

## Required Assignment Screenshots

Capture these screenshots for submission:

1. GitHub repository with project files.
2. Jenkins Pipeline job configuration.
3. Jenkinsfile script.
4. Jenkins successful pipeline stages.
5. Jenkins console output showing:
   - Docker build success
   - Terraform apply success
   - EC2 public IP output
   - Container deployment success
   - Health check success
6. AWS EC2 instance running.
7. AWS Security Group showing:
   - Port `22`
   - Port `7000`
8. Docker container running on app EC2:

```bash
sudo docker ps
```

9. Postman test:

```http
GET http://EC2_PUBLIC_IP:7000/health
```

10. Successful API response.

---

## Final Result

When the pipeline succeeds, the FoodExpress API is available at:

```bash
http://EC2_PUBLIC_IP:7000
```

Health check endpoint:

```bash
http://EC2_PUBLIC_IP:7000/health
```

Expected health response:

```json
{
  "status": "healthy",
  "service": "FoodExpress API"
}
```

---

## Notes

- The repository is cloned only by Jenkins.
- The app EC2 does not need to clone the repository.
- The app EC2 only needs Docker and the runtime container.
- Jenkins is responsible for CI/CD automation.
- Terraform is responsible for infrastructure provisioning.
- Docker is responsible for packaging and running the API.
- Port `7000` is used for the FoodExpress API.
- Port `8080` is used only for Jenkins UI.

---

## Author

Rotha Dapravith

GitHub: [Dapravith](https://github.com/Dapravith)
