Flask Application Deployment on AWS with GitHub Actions, Terraform, and Docker
This repository contains a CI/CD pipeline for deploying a Flask application on AWS EC2 using GitHub Actions, Terraform, and Docker. The pipeline automates infrastructure provisioning, Docker image management, and application deployment, ensuring a scalable and repeatable deployment process.
Overview
The CI/CD pipeline is split into two GitHub Actions workflows:

Infrastructure and Image Build Workflow:

Triggered on push to the main branch.
Provisions AWS infrastructure (EC2 instance, ECR repository, etc.) using Terraform.
Builds and pushes a Docker image of the Flask application to Amazon ECR.
Stores Terraform outputs (e.g., EC2 IP, database endpoint, ECR repository URL) as artifacts.


Deployment Workflow:

Triggered on completion of the first workflow.
Downloads Terraform outputs.
Connects to the EC2 instance via SSH.
Installs Docker, pulls the Flask image from ECR, and runs the container with environment variables for database connectivity.



Prerequisites

AWS Account: An active AWS account with permissions to create EC2 instances, ECR repositories, and IAM roles.
GitHub Repository: A repository with the Flask application code and the following structure:├── app/
│   ├── main.py
│   ├── requirements.txt
│   └── Dockerfile
├── terraform/
│   ├── main.tf
│   ├── variables.tf
│   └── outputs.tf
├── .github/
│   └── workflows/
│       ├── infra-build.yml
│       └── deploy.yml


Terraform: Infrastructure as Code (IaC) files to define AWS resources.
Docker: A Dockerfile to containerize the Flask application.

Workflow Details
1. Infrastructure and Image Build Workflow (infra-build.yml)
Trigger: Runs on push to the main branch.
Jobs:

Setup and Provision Infrastructure:
Checks out the repository.
Configures AWS credentials using GitHub secrets.
Initializes Terraform and applies the configuration to provision:
An EC2 instance with a security group allowing HTTP and SSH access.
An Amazon ECR repository for storing Docker images.
(Optional) A database instance (e.g., RDS) for the Flask app.


Optionally destroys existing infrastructure before applying new changes.
Outputs key variables (e.g., EC2 public IP, database endpoint, ECR repository URL) to a file.


Build and Push Docker Image:
Builds the Flask application Docker image using the Dockerfile.
Logs into Amazon ECR using AWS credentials.
Pushes the image to the ECR repository.


Upload Artifacts:
Stores Terraform outputs as a GitHub Actions artifact for use in the deployment workflow.



Example Workflow:
name: Infrastructure and Image Build
on:
  push:
    branches:
      - main
jobs:
  build-and-push:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v3
      - name: Configure AWS Credentials
        uses: aws-actions/configure-aws-credentials@v2
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: us-east-1
      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v2
      - name: Terraform Init
        working-directory: ./terraform
        run: terraform init
      - name: Terraform Apply
        working-directory: ./terraform
        run: terraform apply -auto-approve
      - name: Build and Push Docker Image
        run: |
          aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin <account-id>.dkr.ecr.us-east-1.amazonaws.com
          docker build -t flask-app .
          docker tag flask-app:latest <account-id>.dkr.ecr.us-east-1.amazonaws.com/flask-app:latest
          docker push <account-id>.dkr.ecr.us-east-1.amazonaws.com/flask-app:latest
      - name: Upload Terraform Outputs
        uses: actions/upload-artifact@v3
        with:
          name: terraform-outputs
          path: ./terraform/outputs.json

2. Deployment Workflow (deploy.yml)
Trigger: Runs on completion of the infra-build.yml workflow.
Jobs:

Deploy Application:
Downloads the Terraform outputs artifact.
Uses the EC2 public IP to SSH into the instance.
Installs Docker on the EC2 instance if not already present.
Logs into Amazon ECR and pulls the latest Flask image.
Runs the Flask container, passing environment variables for database connectivity.



Example Workflow:
name: Deploy Flask Application
on:
  workflow_run:
    workflows: ["Infrastructure and Image Build"]
    types:
      - completed
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v3
      - name: Download Terraform Outputs
        uses: actions/download-artifact@v3
        with:
          name: terraform-outputs
          path: ./terraform
      - name: SSH into EC2 and Deploy
        env:
          EC2_IP: ${{ secrets.EC2_IP }}
          SSH_KEY: ${{ secrets.EC2_SSH_KEY }}
        run: |
          echo "$SSH_KEY" > key.pem
          chmod 600 key.pem
          ssh -o StrictHostKeyChecking=no -i key.pem ubuntu@$EC2_IP << 'EOF'
            sudo apt-get update
            sudo apt-get install -y docker.io
            sudo systemctl start docker
            aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin <account-id>.dkr.ecr.us-east-1.amazonaws.com
            docker pull <account-id>.dkr.ecr.us-east-1.amazonaws.com/flask-app:latest
            docker run -d -p 80:5000 \
              -e DB_HOST=$(jq -r '.db_endpoint.value' terraform/outputs.json) \
              -e DB_USER=${{ secrets.DB_USER }} \
              -e DB_PASSWORD=${{ secrets.DB_PASSWORD }} \
              <account-id>.dkr.ecr.us-east-1.amazonaws.com/flask-app:latest
          EOF

Required GitHub Secrets
The following secrets must be configured in the GitHub repository settings:



Secret Name
Purpose



AWS_ACCESS_KEY_ID
AWS access key for Terraform and ECR authentication.


AWS_SECRET_ACCESS_KEY
AWS secret key for Terraform and ECR authentication.


EC2_SSH_KEY
PEM key for SSH access to the EC2 instance.


DB_USER
Database username for Flask app connectivity.


DB_PASSWORD
Database password for Flask app connectivity.


To set up secrets:

Navigate to your repository on GitHub.
Go to Settings > Secrets and variables > Actions > New repository secret.
Add each secret with the appropriate value.

Terraform Outputs
The Terraform configuration (terraform/outputs.tf) defines the following outputs, which are saved to outputs.json and used in the deployment workflow:



Output Name
Description



ec2_public_ip
Public IP address of the EC2 instance.


db_endpoint
Endpoint of the database (e.g., RDS).


ecr_repository_url
URL of the ECR repository for the Flask image.


Example outputs.tf:
output "ec2_public_ip" {
  value = aws_instance.app_instance.public_ip
}
output "db_endpoint" {
  value = aws_db_instance.default.endpoint
}
output "ecr_repository_url" {
  value = aws_ecr_repository.flask_app.repository_url
}

These outputs are consumed in the deployment workflow to:

SSH into the EC2 instance (ec2_public_ip).
Configure the Flask container with the database endpoint (db_endpoint).
Pull the Docker image from ECR (ecr_repository_url).

Security Considerations

SSH Key Handling:

The EC2_SSH_KEY is stored as a GitHub secret and written to a temporary file (key.pem) during deployment.
The file is secured with chmod 600 to restrict access.
StrictHostKeyChecking=no is used to avoid SSH host verification issues, but consider enabling it in production with a known hosts file.


Secret Management:

AWS credentials (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY) are stored as GitHub secrets to prevent exposure.
Database credentials (DB_USER, DB_PASSWORD) are passed as environment variables to the Flask container, avoiding hardcoding in the codebase.
Use AWS IAM roles with least privilege for Terraform and ECR access.


Network Security:

The EC2 instance’s security group should allow only necessary ports (e.g., 80 for HTTP, 22 for SSH, and database-specific ports).
Restrict SSH access to specific IP ranges if possible.
Use AWS Secrets Manager for sensitive data in production instead of GitHub secrets.


Docker Image Security:

Scan Docker images for vulnerabilities using tools like Trivy or AWS ECR image scanning.
Use a minimal base image (e.g., python:3.9-slim) to reduce attack surface.



Environment Variable Usage
The Flask container is configured with the following environment variables at runtime:



Variable
Source
Purpose



DB_HOST
Terraform output (db_endpoint)
Database endpoint for Flask app.


DB_USER
GitHub secret (DB_USER)
Database username.


DB_PASSWORD
GitHub secret (DB_PASSWORD)
Database password.


These variables are passed to the docker run command in the deployment workflow to ensure the Flask app connects to the database securely.
Best Practices

Modularity:

Separate infrastructure provisioning (infra-build.yml) from application deployment (deploy.yml) for clarity and reusability.
Use Terraform modules to organize AWS resource definitions (e.g., separate modules for EC2, ECR, and RDS).


Reusability:

Parameterize Terraform variables (e.g., instance type, region) in variables.tf to support different environments (dev, prod).
Use GitHub Actions reusable workflows for common tasks like Terraform setup or Docker builds.


Error Handling:

Add validation steps in Terraform (e.g., terraform plan) before applying changes.
Implement retry logic for SSH connections in the deployment workflow to handle transient network issues.
Use GitHub Actions continue-on-error for non-critical steps to avoid pipeline failures.


Monitoring and Logging:

Enable AWS CloudWatch logs for the EC2 instance and Flask application.
Add health checks in the Flask app to verify database connectivity and application status.


Versioning:

Tag Docker images with commit SHAs or version numbers for traceability.
Use Terraform state locking (e.g., with an S3 backend) to prevent concurrent modifications.



Getting Started

Configure AWS:

Create an IAM user with permissions for EC2, ECR, and RDS.
Store the access key and secret key as GitHub secrets (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY).


Set Up SSH Key:

Generate an EC2 key pair in AWS and download the .pem file.
Store the private key as a GitHub secret (EC2_SSH_KEY).


Set Up Database Credentials:

Store database credentials as GitHub secrets (DB_USER, DB_PASSWORD).


Push to Main:

Commit and push changes to the main branch to trigger the infra-build.yml workflow.
The deploy.yml workflow will automatically run upon successful completion.


Verify Deployment:

Access the Flask application at http://<EC2_PUBLIC_IP>.



Troubleshooting

Terraform Apply Fails: Check the AWS credentials and ensure the IAM user has the required permissions.
SSH Connection Fails: Verify the EC2_SSH_KEY and ensure the EC2 security group allows SSH (port 22).
Docker Pull Fails: Confirm the ECR repository URL and AWS credentials used for login.
Flask App Errors: Check container logs (docker logs <container_id>) for database connectivity issues.

Contributing
To contribute to this project:

Fork the repository.
Create a feature branch (git checkout -b feature/xyz).
Commit your changes (git commit -m 'Add feature xyz').
Push to the branch (git push origin feature/xyz).
Open a pull request.

License
This project is licensed under the MIT License. See the LICENSE file for details.
