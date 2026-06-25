# Task 7 — Terraform and Jenkins CI/CD Deployment

This project demonstrates a clean CI/CD workflow for deploying a **FoodExpress Node.js API** to **AWS EC2** using **GitHub**, **Jenkins**, **Docker**, and **Terraform**.

The main flow is:

```text
GitHub → Jenkins → Docker Build → Terraform EC2 → Docker Deploy → Postman Test
```

---

## 1. High-Level Flow

```text
Developer pushes code
        ↓
GitHub repository
        ↓
Jenkins pipeline checks out the repo
        ↓
Jenkins builds a Docker image
        ↓
Jenkins runs Terraform
        ↓
Terraform creates the App EC2 server
        ↓
Jenkins copies the Docker image to App EC2
        ↓
App EC2 runs the FoodExpress API container
        ↓
User tests the API by EC2 public IP
```

### EC2 responsibilities

| Server | Responsibility |
|---|---|
| Jenkins EC2 | Runs Jenkins, Docker build, Terraform, AWS CLI, SSH/SCP |
| App EC2 | Created by Terraform and runs only the Dockerized API |

The **App EC2 does not need to clone the GitHub repository**. Jenkins builds the Docker image and sends it to the App EC2.

---

## 2. Repository Structure

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
└── README.md
```

---

## 3. Tools Used

| Tool | Purpose |
|---|---|
| GitHub | Stores source code |
| Jenkins | Runs the CI/CD pipeline |
| Docker | Builds and runs the API container |
| Terraform | Provisions AWS infrastructure |
| AWS EC2 | Hosts Jenkins and the API server |
| Postman | Tests API endpoints |

---

## 4. FoodExpress API

The API is a simple Express.js application with authentication and item CRUD routes.

### API port

```text
7000
```

### Public endpoints

| Method | Endpoint | Description |
|---|---|---|
| GET | `/` | API home check |
| GET | `/health` | Health check |
| POST | `/auth/register` | Register a user |
| POST | `/auth/login` | Login and receive JWT token |

### Protected endpoints

| Method | Endpoint | Description |
|---|---|---|
| GET | `/auth/me` | Get current user |
| GET | `/items` | Get all items for logged-in user |
| POST | `/items` | Create item |
| GET | `/items/:id` | Get one item |
| PUT | `/items/:id` | Update item |
| DELETE | `/items/:id` | Delete item |

Protected endpoints require this header:

```text
Authorization: Bearer <JWT_TOKEN>
```

---

## 5. Required App Configuration

### `package.json`

The Dockerfile runs `npm start`, so the app must include a start script.

```json
{
  "scripts": {
    "start": "node index.js",
    "test": "echo \"No tests configured\" && exit 0"
  }
}
```

If this script is missing, Docker will fail with:

```text
npm error Missing script: "start"
```

### `index.js`

The app must listen on `0.0.0.0` so it can receive traffic from outside the container.

```js
const PORT = process.env.PORT || 7000;

app.listen(PORT, "0.0.0.0", () => {
  console.log(`Server start running on port ${PORT}`);
});
```

---

## 6. Docker Flow

Docker builds the API from:

```text
Food-Express-API/Dockerfile
```

The container maps:

```text
Host port 7000 → Container port 7000
```

### Local Docker test

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

## 7. Terraform Flow

Terraform files are inside:

```text
terraform/
```

Terraform creates:

- App EC2 instance
- Security group
- SSH key pair
- Public IP output
- Application URL output
- Health check URL output

### Required App EC2 inbound ports

| Port | Purpose |
|---|---|
| 22 | SSH access |
| 7000 | FoodExpress API access |

### Required Jenkins EC2 inbound ports

| Port | Purpose |
|---|---|
| 22 | SSH access |
| 8080 | Jenkins web UI |

### Duplicate resource protection

The Jenkinsfile uses unique names per build:

```groovy
PROJECT_NAME = "foodexpress-${env.BUILD_NUMBER}"
KEY_NAME = "foodexpress-auto-key-${env.BUILD_NUMBER}"
```

This prevents duplicate AWS errors such as:

```text
InvalidKeyPair.Duplicate
InvalidGroup.Duplicate
```

---

## 8. Jenkins Server Setup

Run `deploy.sh` only on the **Jenkins EC2 server**.

Do not run it on the App EC2.

### SSH to Jenkins EC2

```bash
ssh -i your-jenkins-key.pem ubuntu@JENKINS_EC2_PUBLIC_IP
```

### Run setup script

```bash
chmod +x deploy.sh
sudo bash deploy.sh
```

### Open Jenkins

```text
http://JENKINS_EC2_PUBLIC_IP:8080
```

### Verify Jenkins server tools

```bash
docker --version
terraform version
aws --version
git --version
ssh -V
```

### Docker permission for Jenkins user

```bash
sudo usermod -aG docker jenkins
sudo systemctl restart jenkins
```

Then log back into Jenkins and rebuild the pipeline.

---

## 9. Jenkins Credentials

In Jenkins, go to:

```text
Manage Jenkins → Credentials → System → Global credentials → Add Credentials
```

Create these credentials exactly:

| Credential ID | Kind | Description |
|---|---|---|
| `aws-access-key-id` | Secret text | AWS access key ID |
| `aws-secret-access-key` | Secret text | AWS secret access key |
| `foodexpress-jwt-secret` | Secret text | JWT secret for API runtime |

If using AWS Academy or temporary credentials, also create:

| Credential ID | Kind | Description |
|---|---|---|
| `aws-session-token` | Secret text | AWS session token |

For the GitHub repository field in Jenkins, use:

```text
Credentials: none
```

This is correct because the repository is public. AWS credentials are used inside the Jenkinsfile, not in the Git dropdown.

---

## 10. Jenkins Job Configuration

Create a Jenkins Pipeline job:

```text
New Item → Pipeline → OK
```

Recommended job name:

```text
Food-express-api
```

Pipeline configuration:

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
Save → Build Now
```

---

## 11. Jenkins Pipeline Stages

The Jenkinsfile runs these stages:

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

### Pipeline summary

| Stage | What happens |
|---|---|
| Checkout Code | Jenkins pulls code from GitHub |
| Build Docker Image | Jenkins builds API Docker image |
| Save Docker Image to TAR | Jenkins exports the image |
| Terraform Apply | Jenkins creates App EC2 through Terraform |
| Copy Files to EC2 | Jenkins copies image and environment file |
| Deploy Container | App EC2 runs the API container |
| Verify Application | Jenkins tests `/health` by public IP |

---

## 12. Verify Deployment

After a successful build, Jenkins prints:

```text
Application URL: http://EC2_PUBLIC_IP:7000
Health Check URL: http://EC2_PUBLIC_IP:7000/health
```

Test with curl:

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

## 13. SSH to App EC2

The App EC2 SSH key is generated by Jenkins during the pipeline.

The private key is on the Jenkins EC2 server:

```text
/var/lib/jenkins/workspace/Food-express-api/sshkey/id_rsa
```

SSH from Jenkins EC2 to App EC2:

```bash
sudo ssh -i /var/lib/jenkins/workspace/Food-express-api/sshkey/id_rsa \
  -o StrictHostKeyChecking=no \
  ubuntu@APP_EC2_PUBLIC_IP
```

Check container status:

```bash
sudo docker ps -a
sudo docker logs foodexpress --tail 100
curl http://localhost:7000/health
```

If SSH returns `Permission denied (publickey)`, the private key does not match the EC2 key pair.

---

## 14. Postman Test Order

Use this order:

```text
1. GET  /health
2. POST /auth/register
3. POST /auth/login
4. GET  /auth/me
5. POST /items
6. GET  /items
7. GET  /items/:id
8. PUT  /items/:id
9. DELETE /items/:id
```

### Register body

```json
{
  "username": "dapravith",
  "password": "Password123"
}
```

### Login body

```json
{
  "username": "dapravith",
  "password": "Password123"
}
```

### Create item body

```json
{
  "name": "Chicken Burger",
  "price": 3.5
}
```

---

## 15. Common Errors and Fixes

### `npm error Missing script: "start"`

Add this to `Food-Express-API/package.json`:

```json
"scripts": {
  "start": "node index.js"
}
```

### `node: not found` in Jenkins

The Jenkins server does not need Node.js if the app is built inside Docker. Validate the app with shell commands, or install Node.js if the pipeline requires direct Node commands.

### `InvalidKeyPair.Duplicate`

The AWS key pair name already exists. Use a unique `KEY_NAME` per build.

### `InvalidGroup.Duplicate`

The AWS security group name already exists. Use a unique `PROJECT_NAME` per build.

### `InvalidClientTokenId`

AWS credentials are invalid, expired, or missing a session token. Update Jenkins credentials and test with:

```bash
aws sts get-caller-identity
```

### `Connection refused` on port `7000`

Debug on App EC2:

```bash
sudo docker ps -a
sudo docker logs foodexpress --tail 100
sudo ss -tulnp | grep 7000
curl http://localhost:7000/health
```

Check that:

- The container is running
- `package.json` has `start`
- Express listens on `0.0.0.0`
- App EC2 security group allows port `7000`

---

## 16. Assignment Screenshot Checklist

Capture these screenshots:

- GitHub repository structure
- Jenkins job configuration
- Jenkinsfile script
- Successful Jenkins pipeline stages
- Jenkins console output with Terraform apply success
- AWS EC2 App instance running
- AWS security group with ports `22` and `7000`
- Docker container running on App EC2
- Postman API test by public IP
- Successful `/health` response

---

## 17. Final Result

Final application URL:

```text
http://EC2_PUBLIC_IP:7000
```

Health check URL:

```text
http://EC2_PUBLIC_IP:7000/health
```

Expected response:

```json
{
  "status": "healthy",
  "service": "FoodExpress API"
}
```

---

## Author

**Rotha Dapravith**

GitHub: [Dapravith](https://github.com/Dapravith)
