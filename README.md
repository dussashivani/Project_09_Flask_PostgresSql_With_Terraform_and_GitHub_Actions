---

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
├── app.py                  # Flask application
├── requirements.txt        # Python dependencies
├── Dockerfile             # Docker image configuration
├── terraform/             # Terraform configurations
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
├── .github/workflows/     # GitHub Actions workflows
│   ├── provision-and-build.yml
│   ├── deploy.yml
```

## Prerequisites

### Software Requirements
- **GitHub Repository**: Contains the Flask app and Terraform configs.
- **AWS Account**: With permissions for EC2, ECR, RDS, and IAM.
- **Docker**: The Flask app is containerized using a `Dockerfile`.
- **Terraform**: Infrastructure is defined in `terraform/` directory.

### Example Flask Dockerfile
```dockerfile
FROM python:3.9-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

ENV FLASK_APP=app.py
ENV FLASK_ENV=production

CMD ["flask", "run", "--host=0.0.0.0", "--port=5000"]
```

### Example Terraform Configuration
In `terraform/main.tf`:
```hcl
provider "aws" {
  region = var.aws_region
}

resource "aws_ecr_repository" "flask_repo" {
  name = var.ecr_repository_name
}

resource "aws_instance" "flask_ec2" {
  ami           = var.ec2_ami
  instance_type = "t2.micro"
  key_name      = var.ec2_key_name
  security_groups = [aws_security_group.flask_sg.name]

  tags = {
    Name = "FlaskAppEC2"
  }
}

resource "aws_security_group" "flask_sg" {
  name = "flask-sg"
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_instance" "flask_db" {
  allocated_storage    = 20
  storage_type         = "gp2"
  engine               = "postgres"
  engine_version       = "13"
  instance_class       = "db.t3.micro"
  db_name              = var.db_name
  username             = var.db_username
  password             = var.db_password
  skip_final_snapshot  = true
}

output "ec2_public_ip" {
  value = aws_instance.flask_ec2.public_ip
}

output "db_endpoint" {
  value = aws_db_instance.flask_db.endpoint
}

output "ecr_repo_url" {
  value = aws_ecr_repository.flask_repo.repository_url
}
```

In `terraform/variables.tf`:
```hcl
variable "aws_region" { default = "us-east-1" }
variable "ecr_repository_name" { default = "flask-app-repo" }
variable "ec2_ami" { default = "ami-0abcdef1234567890" } # Replace with valid AMI
variable "ec2_key_name" { default = "flask-ec2-key" }
variable "db_name" { default = "flaskdb" }
variable "db_username" { default = "dbuser" }
variable "db_password" { sensitive = true }
```

## Workflow Triggers and Job Dependencies

### Workflow Triggers
1. **Provision and Build Workflow** (`.github/workflows/provision-and-build.yml`):
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
         workflows: ["Provision and Build"]
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
```yaml
- name: Get Terraform Outputs
  id: tf-outputs
  run: |
    echo "EC2_IP=$(terraform output -raw ec2_public_ip)" >> $GITHUB_ENV
    echo "DB_ENDPOINT=$(terraform output -raw db_endpoint)" >> $GITHUB_ENV
    echo "ECR_REPO_URL=$(terraform output -raw ecr_repo_url)" >> $GITHUB_ENV
    echo "EC2_IP=$(terraform output -raw ec2_public_ip)" > tf-outputs.env
    echo "DB_ENDPOINT=$(terraform output -raw db_endpoint)" >> tf-outputs.env
    echo "ECR_REPO_URL=$(terraform output -raw ecr_repo_url)" >> tf-outputs.env
- name: Upload Terraform Outputs
  uses: actions/upload-artifact@v3
  with:
    name: terraform-outputs
    path: tf-outputs.env
```

### Workflow 2: Consuming Outputs
```yaml
- name: Download Terraform Outputs
  uses: actions/download-artifact@v3
  with:
    name: terraform-outputs
- name: Load Outputs to Environment
  run: cat tf-outputs.env >> $GITHUB_ENV
```

These outputs are used for SSH (`${{ env.EC2_IP }}`), Docker pull (`${{ env.ECR_REPO_URL }}`), and DB connectivity (`${{ env.DB_ENDPOINT }}`).

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

## Environment Variable Usage in Container Runtime

The Flask container requires environment variables for database connectivity and runtime configuration. These are set during `docker run` in the deployment workflow:

```yaml
- name: Deploy via SSH
  uses: appleboy/ssh-action@v0.1.10
  with:
    host: ${{ env.EC2_IP }}
    username: ubuntu
    key: ${{ secrets.SSH_PRIVATE_KEY }}
    script: |
      sudo apt update && sudo apt install -y docker.io
      sudo systemctl start docker
      aws ecr get-login-password --region us-east-1 | sudo docker login --username AWS --password-stdin ${{ env.ECR_REPO_URL }}
      sudo docker pull ${{ env.ECR_REPO_URL }}:latest
      sudo docker stop flask-app || true
      sudo docker rm flask-app || true
      sudo docker run -d --name flask-app -p 80:5000 \
        -e DB_HOST=${{ env.DB_ENDPOINT }} \
        -e DB_USER=${{ secrets.DB_USERNAME }} \
        -e DB_PASSWORD=${{ secrets.DB_PASSWORD }} \
        -e DB_NAME=flaskdb \
        ${{ env.ECR_REPO_URL }}:latest
```

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

### Provision and Build Workflow (`.github/workflows/provision-and-build.yml`)
```yaml
name: Provision and Build

on:
  push:
    branches:
      - main

jobs:
  setup-terraform:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: hashicorp/setup-terraform@v2
        with:
          terraform_version: 1.5.0
      - run: terraform init
        working-directory: terraform
        env:
          AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
          AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}

  terraform-destroy-apply:
    needs: setup-terraform
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: hashicorp/setup-terraform@v2
      - run: terraform init
        working-directory: terraform
        env:
          AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
          AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
      - run: terraform destroy -auto-approve  # Optional
        working-directory: terraform
        env:
          AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
          AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
      - run: terraform apply -auto-approve
        working-directory: terraform
        env:
          AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
          AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}

  build-push-docker:
    needs: terraform-destroy-apply
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - run: |
          echo "ECR_REPO_URL=$(terraform output -raw ecr_repo_url)" >> $GITHUB_ENV
        working-directory: terraform
      - uses: docker/login-action@v2
        with:
          registry: ${{ env.ECR_REPO_URL }}
          username: AWS
          password: ${{ secrets.AWS_ACCESS_KEY_ID }}
      - run: docker build -t ${{ env.ECR_REPO_URL }}:latest .
      - run: docker push ${{ env.ECR_REPO_URL }}:latest

  upload-artifacts:
    needs: terraform-destroy-apply
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - run: |
          echo "EC2_IP=$(terraform output -raw ec2_public_ip)" > tf-outputs.env
          echo "DB_ENDPOINT=$(terraform output -raw db_endpoint)" >> tf-outputs.env
          echo "ECR_REPO_URL=$(terraform output -raw ecr_repo_url)" >> tf-outputs.env
        working-directory: terraform
      - uses: actions/upload-artifact@v3
        with:
          name: terraform-outputs
          path: tf-outputs.env
```

### Deployment Workflow (`.github/workflows/deploy.yml`)
```yaml
name: Deploy

on:
  workflow_run:
    workflows: ["Provision and Build"]
    types:
      - completed

jobs:
  download-artifacts:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/download-artifact@v3
        with:
          name: terraform-outputs
      - run: cat tf-outputs.env >> $GITHUB_ENV

  deploy-to-ec2:
    needs: download-artifacts
    runs-on: ubuntu-latest
    steps:
      - name: Deploy via SSH
        uses: appleboy/ssh-action@v0.1.10
        with:
          host: ${{ env.EC2_IP }}
          username: ubuntu
          key: ${{ secrets.SSH_PRIVATE_KEY }}
          script: |
            sudo apt update && sudo apt install -y docker.io
            sudo systemctl start docker
            aws ecr get-login-password --region us-east-1 | sudo docker login --username AWS --password-stdin ${{ env.ECR_REPO_URL }}
            sudo docker pull ${{ env.ECR_REPO_URL }}:latest
            sudo docker stop flask-app || true
            sudo docker rm flask-app || true
            sudo docker run -d --name flask-app -p 80:5000 \
              -e DB_HOST=${{ env.DB_ENDPOINT }} \
              -e DB_USER=${{ secrets.DB_USERNAME }} \
              -e DB_PASSWORD=${{ secrets.DB_PASSWORD }} \
              -e DB_NAME=flaskdb \
              ${{ env.ECR_REPO_URL }}:latest
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
