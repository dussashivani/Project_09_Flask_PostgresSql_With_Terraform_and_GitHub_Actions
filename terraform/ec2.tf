resource "aws_security_group" "ec2_sg" {
  name        = "ec2_sg"
  description = "Allow HTTP from ALB and SSH"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port       = 5000
    to_port         = 5000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
} 

resource "aws_ecr_repository" "greeting_app" {
  name = "greeting-app"
  force_delete = true
}

resource "aws_instance" "flask_ec2" {
  ami           = "ami-081b0a6eac00b4f53" # Ubuntu
  instance_type = "t2.micro"
  subnet_id     = module.vpc.public_subnets[0]
  key_name      = "project9-key-final"
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  iam_instance_profile = aws_iam_instance_profile.ec2_profile.name
  associate_public_ip_address = true

  user_data = <<-EOF
              #!/bin/bash
              set -xe
              apt-get update -y
              apt-get install -y docker.io
              systemctl start docker
              systemctl enable docker

              curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
              apt-get install unzip -y
              unzip awscliv2.zip
              sudo ./aws/install
			  
			  # Create init.sql file
              cat <<EOT > /tmp/init.sql
              CREATE TABLE IF NOT EXISTS greetings (
                id SERIAL PRIMARY KEY,
                username VARCHAR(100),
                message TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
               );
              EOT

              # Run SQL against DB
              PGPASSWORD="${var.db_password}" psql -h ${aws_db_instance.postgres.address} -U ${var.db_username} -d ${aws_db_instance.postgres.db_name} -f /tmp/init.sql || echo "Init failed"
            EOF

  tags = {
    Name = "GreetingApp-EC2"
  }
}

resource "aws_iam_role" "ec2_ecr_access" {
  name = "ec2-ecr-access-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = {
        Service = "ec2.amazonaws.com"
      },
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_policy" "ecr_policy" {
  name = "ECRAccessPolicy"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Action = [
        "ecr:*",
        "cloudtrail:LookupEvents",
		"iam:CreateServiceLinkedRole"
      ],
      Resource = "*"
	  "Condition": {
                "StringEquals": {
                    "iam:AWSServiceName": [
                        "replication.ecr.amazonaws.com"
                    ]
                }
            }
    }]
  })
}


resource "aws_iam_role_policy_attachment" "ec2_attach" {
  role       = aws_iam_role.ec2_ecr_access.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryFullAccess"
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "ec2-instance-profile"
  role = aws_iam_role.ec2_ecr_access.name
}

