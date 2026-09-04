output "db_endpoint" {

  description = "PostgreSQL RDS endpoint"

  value = aws_db_instance.postgres.address
}


output "ec2_public_ip" {

  description = "EC2 public IP address"

  value = aws_instance.flask_ec2.public_ip
}


output "ecr_repo_url" {

  description = "ECR repository URL"

  value = aws_ecr_repository.greeting_app.repository_url
}


output "alb_dns" {

  description = "Application Load Balancer DNS"

  value = aws_lb.app_alb.dns_name
}


output "db_name" {

  description = "Database name"

  value = aws_db_instance.postgres.db_name
}
