variable "region" {
  default = "us-east-1"
}

variable "db_username" {
  description = "Database username"
  type        = string
}

variable "db_password" {
  description = "Database password"
  type        = string
  sensitive   = true
}

variable "aws_account_id" {
  description = "AWS account ID"
  type        = string
  default     = "518216637461"
  # Set this via terraform.tfvars or environment variable (e.g., TF_VAR_aws_account_id)
}

output "db_address" {
  value = aws_db_instance.postgres.address
}
