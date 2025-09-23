<img width="1321" height="429" alt="diagram-export-9-23-2025-11_41_00-PM" src="https://github.com/user-attachments/assets/e49a2172-9be3-48e3-94e0-2a552d5a9452" />

# CI/CD Pipeline for Flask Application Deployment on AWS EC2

## Overview

This CI/CD pipeline automates the deployment of a Flask web application to an AWS EC2 instance using GitHub Actions and Terraform. The pipeline is split into two workflows:

1. **Provision and Build Workflow**: Triggered on push to the `main` branch. It uses Terraform to manage AWS infrastructure (EC2, RDS, ECR), builds a Docker image of the Flask app, pushes it to Amazon Elastic Container Registry (ECR), and uploads Terraform outputs as artifacts.

2. **Deployment Workflow**: Triggered upon successful completion of the first workflow. It downloads Terraform outputs, SSHs into the EC2 instance, installs Docker (if needed), pulls the image from ECR, and runs the Flask container with environment variables for database connectivity.

### Assumptions
- The Flask application resides in the repository root with a `Dockerfile` for containerization.
- Terraform configuration files are in a `terraform/` directory.
- The application connects to an AWS RDS PostgreSQL database.
- AWS credentials and SSH keys are securely stored as GitHub secrets.
- The EC2 instance is configured with security groups allowing SSH (port 22) and HTTP (port 80).

### Repository Structure
```
.
├── .github/
│   └── workflows/
│       ├── deploy.yml        # Terraform deploy pipeline
│       └── run-container.yml # Docker build/run pipeline
├── templates/                # Optional Terraform templates/modules
├── terraform/                # Terraform infrastructure configs
│   ├── alb.tf
│   ├── backend.tf
│   ├── dynamodb.tf
│   ├── ec2.tf
│   ├── main.tf
│   ├── output.tf
│   ├── rds.tf
│   ├── variables.tf
├── Dockerfile                # Flask app container definition
├── app.py                    # Flask application code
├── requirements.txt          # Python dependencies
├── README.md                 # Documentation

```

## Prerequisites

### Software Requirements
- **GitHub Repository**: Contains the Flask app and Terraform configs.
- **AWS Account**: With permissions for EC2, ECR, RDS, and IAM.
- **Docker**: The Flask app is containerized using a `Dockerfile`.
- **Terraform**: Infrastructure is defined in `terraform/` directory.

### Example Flask Dockerfile
```dockerfile
# Use official Python image
FROM python:3.10-slim

# Set working directory
WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y gcc libpq-dev

# Copy files
COPY requirements.txt requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

# Expose Flask port
EXPOSE 5000

# Run app
CMD ["python", "app.py"]
```

## Workflow Triggers and Job Dependencies

### Workflow Triggers
1. **Provision and Build Workflow** (`.github/workflows/deploy.yml`):
   - Triggered on push to `main`:
     ```yaml
     on:
       push:
         branches:
           - main
     ```
   - Runs on every merge to `main`, ensuring infrastructure and Docker image are updated.

2. **Deployment Workflow** (`.github/workflows/deploy.yml`):
   - Triggered on successful completion of the "Provision and Build" workflow:
     ```yaml
           on:
        workflow_run:
          workflows: [Deploy Flask App with Terraform]
          types:
            - completed
     ```
   - Ensures deployment only proceeds if provisioning succeeds.

### Job Dependencies
- **Provision and Build Workflow**:
  - `setup-terraform`: Configures Terraform CLI and AWS credentials.
  - `terraform-destroy-apply`: Destroys (optional) and applies Terraform configs. Depends on `setup-terraform`.
  - `build-push-docker`: Builds and pushes Docker image to ECR. Depends on `terraform-destroy-apply` to ensure ECR exists.
  - `upload-artifacts`: Uploads Terraform outputs as artifacts. Depends on `terraform-destroy-apply`.

  Example dependency:
  ```yaml
  jobs:
    terraform-destroy-apply:
      needs: setup-terraform
      # ...
  ```

- **Deployment Workflow**:
  - `download-artifacts`: Downloads Terraform outputs from Workflow 1.
  - `deploy-to-ec2`: SSHs into EC2, pulls image, and runs container. Depends on `download-artifacts`.

This structure ensures sequential execution and proper error propagation.

## Required GitHub Secrets and Their Purpose

Store sensitive data as GitHub repository secrets under **Settings > Secrets and variables > Actions**. Required secrets:

- `AWS_ACCESS_KEY_ID`: AWS IAM access key for Terraform (EC2, ECR, RDS provisioning) and ECR login.
- `AWS_SECRET_ACCESS_KEY`: Corresponding secret key for AWS IAM authentication.
- `SSH_PRIVATE_KEY`: PEM-encoded private key for SSH access to EC2. Used in deployment workflow.
- `DB_PASSWORD`: RDS database password, passed to the Flask container as an environment variable.
- `EC2_KEY_NAME`: Name of the AWS key pair for EC2 (e.g., `flask-ec2-key`). Matches Terraform config.
- `DB_USERNAME` (optional): RDS username if not hardcoded in Terraform.

Example usage:
```yaml
env:
  AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
  AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
```

## Terraform Output Variables and How They’re Consumed

Terraform outputs (`terraform/outputs.tf`) provide dynamic values post-provisioning, used across workflows:

- `ec2_public_ip`: Public IP of the EC2 instance (e.g., `54.123.45.67`). Used in Workflow 2 for SSH access.
- `db_endpoint`: RDS endpoint (e.g., `flaskdb.abc123.us-east-1.rds.amazonaws.com:5432`). Passed to Flask container as `DB_HOST`.
- `ecr_repo_url`: ECR repository URL (e.g., `123456789012.dkr.ecr.us-east-1.amazonaws.com/flask-app-repo`). Used in Workflow 1 to push image and Workflow 2 to pull it.

### Workflow 1: Capturing and Uploading Outputs

### Workflow 2: Consuming Outputs

## Security Considerations

### SSH Key Handling
- **Storage**: Store the private key as `SSH_PRIVATE_KEY` in GitHub secrets. The public key is associated with the EC2 instance via `EC2_KEY_NAME`.
- **Usage**: Write the key to a temporary file with restricted permissions during deployment:
  ```yaml
  - name: Write SSH Key
    run: |
      echo "${{ secrets.SSH_PRIVATE_KEY }}" > key.pem
      chmod 600 key.pem
  ```
- **Cleanup**: Remove the key file after use to prevent leaks.
- **Rotation**: Rotate keys periodically via AWS Console and update secrets.

### Secret Management
- Use GitHub secrets for all sensitive data (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `DB_PASSWORD`, etc.).
- For production, prefer AWS IAM roles for EC2 (e.g., attach a role to EC2 for ECR access) over long-term credentials.
- Store `DB_PASSWORD` in AWS Secrets Manager for runtime retrieval via user-data scripts if needed.
- Enable GitHub’s secret scanning to detect accidental leaks in commits.

### Other Security Measures
- **Network**: Restrict EC2 security group ingress to trusted IPs for SSH (e.g., CI runner IPs) in production.
- **Encryption**: Use HTTPS for ECR and RDS communications.
- **Least Privilege**: Limit IAM permissions to only required actions (e.g., `ecr:BatchGetImage` for EC2).
- **Logging**: Enable AWS CloudTrail to monitor API calls and detect unauthorized access.
- **Validation**: Sanitize inputs in SSH scripts to prevent injection attacks.
- **Artifact Security**: Encrypt sensitive artifacts if needed (GitHub supports encrypted artifacts).

### Environment Variables
- `DB_HOST`: RDS endpoint from Terraform output (`db_endpoint`).
- `DB_USER`: Database username (from secret or Terraform variable).
- `DB_PASSWORD`: Database password (from `DB_PASSWORD` secret).
- `DB_NAME`: Database name (hardcoded or from Terraform variable, e.g., `flaskdb`).

### Flask Application Usage
In `app.py`, access variables using `os.environ`:
```python
import os
from flask import Flask
from flask_sqlalchemy import SQLAlchemy

app = Flask(__name__)
db_host = os.environ.get('DB_HOST')
db_user = os.environ.get('DB_USER')
db_password = os.environ.get('DB_PASSWORD')
db_name = os.environ.get('DB_NAME')
app.config['SQLALCHEMY_DATABASE_URI'] = f'postgresql://{db_user}:{db_password}@{db_host}/{db_name}'
db = SQLAlchemy(app)
```

This decouples configuration from code, enhancing security and flexibility.

## Best Practices for Modularity, Reusability, and Error Handling

### Modularity
- **Terraform Modules**: Organize Terraform configs into modules (e.g., `terraform/modules/ec2`, `terraform/modules/rds`) for reusability across environments.
- **GitHub Actions**: Create reusable composite actions for common tasks (e.g., Terraform setup, Docker build).
- **Scripts**: Move complex logic to shell scripts (e.g., `scripts/deploy.sh`) and call them from workflows.

### Reusability
- **Parameterized Workflows**: Use inputs for environment-specific configs:
  ```yaml
  on:
    workflow_dispatch:
      inputs:
        aws_region:
          default: 'us-east-1'
  ```
- **Matrix Builds**: Use GitHub Actions matrix strategy for multi-environment deploys (e.g., dev/staging/prod).
- **Docker Tags**: Tag images with `github.sha` for traceability: `${{ env.ECR_REPO_URL }}:${{ github.sha }}`.

### Error Handling
- **Fail Fast**: Set `continue-on-error: false` for critical steps.
- **Terraform Plan**: Run `terraform plan` before `apply` to catch errors early:
  ```yaml
  - run: terraform plan -out=tfplan
  ```
- **Idempotent Scripts**: Ensure scripts are rerun-safe (e.g., `docker stop || true`).
- **Logging**: Use `echo` for debugging and `::error::` for failures:
  ```yaml
  - run: echo "::error::Failed to apply Terraform" && exit 1
    if: failure()
  ```
- **Notifications**: Add Slack/Email notifications on failure using actions like `slackapi/slack-github-action`.
- **Testing**: Enable `workflow_dispatch` for manual testing and use feature branches for CI testing.

## Example Workflows

### Provision and Build Workflow (`.github/workflows/deploy.yml`)
```yaml
name: Deploy Flask App with Terraform

on:
  push:
    branches: [ main ]
    
permissions:
  contents: read
  actions: write
  id-token: write
env:
  AWS_REGION: ca-central-1
  ECR_REPOSITORY: greeting-app
  IMAGE_TAG: latest

jobs:
  deploy:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout code
        uses: actions/checkout@v3

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3

      - name: Configure AWS Credentials
        uses: aws-actions/configure-aws-credentials@v2
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: ca-central-1

      - name: Login to Amazon ECR
        run: |
          aws ecr get-login-password --region ${AWS_REGION} |sudo docker login --username AWS --password-stdin ${{ secrets.AWS_ACCOUNT_ID }}.dkr.ecr.${AWS_REGION}.amazonaws.com  

      - name: Terraform Apply with DB creds
        env:
          TF_VAR_db_username: ${{ secrets.DB_USERNAME }}
          TF_VAR_db_password: ${{ secrets.DB_PASSWORD }}
        run: |
          cd terraform
          terraform init -reconfigure
          terraform destroy -auto-approve
          #terraform apply -auto-approve
          terraform output -json > terraform_outputs.json

      - name: Build, Tag, and Push Docker image
        run: |
            IMAGE_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPOSITORY}"
            aws ecr get-login-password --region ca-central-1 | sudo docker login --username AWS --password-stdin ${{ secrets.AWS_ACCOUNT_ID }}.dkr.ecr.${AWS_REGION}.amazonaws.com     
            
            sudo docker build -t python-app .
            docker tag python-app:latest ${{ secrets.AWS_ACCOUNT_ID }}.dkr.ecr.${AWS_REGION}.amazonaws.com/greeting-app:latest

            aws ecr get-login-password --region ca-central-1 | docker login --username AWS --password-stdin ${{ secrets.AWS_ACCOUNT_ID }}.dkr.ecr.${AWS_REGION}.amazonaws.com
            docker push ${{ secrets.AWS_ACCOUNT_ID }}.dkr.ecr.${AWS_REGION}.amazonaws.com/greeting-app:latest


      - name: Upload Terraform Outputs
        uses: actions/upload-artifact@v4
        with:
          name: deploy # The name of the artifact
          path: terraform/terraform_outputs.json
```

### Deployment Workflow (`.github/workflows/run-container.yml`)
```yaml
name: Deploy Flask App on EC2

on:
  workflow_run:
    workflows: [Deploy Flask App with Terraform]
    types:
      - completed

permissions:
  contents: read
  actions: read

jobs:
  run-docker:
    runs-on: ubuntu-latest

    steps:
      - name: Download Terraform Outputs
        uses: actions/download-artifact@v4
        with:
          name: deploy
          path: ./outputs
          github-token: ${{ secrets.GITHUB_TOKEN }}
          run-id: ${{ github.event.workflow_run.id }}

      - name: Parse Terraform Outputs
        id: vars
        run: |
          DB_HOST=$(jq -r '.db_endpoint.value' ./outputs/terraform_outputs.json)
          EC2_IP=$(jq -r '.ec2_public_ip.value' ./outputs/terraform_outputs.json)
          ECR_REPO=$(jq -r '.ecr_repo_url.value' ./outputs/terraform_outputs.json)

          echo "DB_HOST=$DB_HOST" >> $GITHUB_ENV
          echo "EC2_IP=$EC2_IP" >> $GITHUB_ENV
          echo "ECR_REPO=$ECR_REPO" >> $GITHUB_ENV

      - name: Setup SSH Key
        run: |
          echo "${{ secrets.EC2_SSH_KEY }}" > Python.pem
          chmod 600 Python.pem

      - name: SSH into EC2 and run Docker
        run: |
          ssh -o StrictHostKeyChecking=no -i Python.pem ec2-user@${{ env.EC2_IP }} << EOF
            # Install Docker if not present
            sudo yum update -y
            sudo yum install -y docker
            sudo systemctl enable docker
            sudo systemctl start docker
            sudo usermod -aG docker ec2-user

            # ECR login
            aws ecr get-login-password --region ca-central-1 | sudo docker login --username AWS --password-stdin ${ECR_REPO}

            # Pull and run the latest image
            sudo docker pull ${ECR_REPO}:latest
            sudo docker rm -f flask-app || true

            sudo docker run -d --name flask-app -p 5001:5000 \
              -e DB_HOST=${DB_HOST} \
              -e DB_NAME=greetings_db \
              -e DB_USER=${DB_USERNAME} \
              -e DB_PASS=${DB_PASSWORD} \
              ${ECR_REPO}:latest
          EOF
        env:
          DB_HOST: ${{ env.DB_HOST }}
          EC2_IP: ${{ env.EC2_IP }}
          ECR_REPO: ${{ env.ECR_REPO }}
          DB_USERNAME: ${{ secrets.DB_USERNAME }}
          DB_PASSWORD: ${{ secrets.DB_PASSWORD }}
```

## Troubleshooting
- **Terraform Errors**: Check `terraform plan` output or enable debug logging (`TF_LOG=DEBUG`).
- **SSH Failures**: Verify `EC2_IP`, `SSH_PRIVATE_KEY`, and security group rules.
- **Docker Pull Issues**: Ensure ECR permissions and AWS credentials are valid.
- **DB Connectivity**: Validate `DB_ENDPOINT`, `DB_USER`, and `DB_PASSWORD`.

## Next Steps
- Add health checks post-deployment (e.g., curl the Flask app endpoint).
- Implement blue-green deployments for zero downtime.
- Use AWS Auto Scaling for high availability.
- Monitor with CloudWatch and integrate alerts.
