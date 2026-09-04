resource "aws_db_subnet_group" "rds_subnet" {

  name = "rds-subnet-group"

  subnet_ids = module.vpc.public_subnets

  tags = {
    Name = "GreetingApp-RDS-Subnet"
  }
}


resource "aws_security_group" "rds_sg" {

  name = "rds_sg"

  description = "Allow PostgreSQL from Flask EC2"

  vpc_id = module.vpc.vpc_id

  ingress {

    description = "PostgreSQL from Flask EC2"

    from_port = 5432
    to_port   = 5432
    protocol  = "tcp"

    security_groups = [
      aws_security_group.ec2_sg.id
    ]
  }

  egress {

    from_port = 0
    to_port   = 0
    protocol  = "-1"

    cidr_blocks = [
      "0.0.0.0/0"
    ]
  }
}


resource "aws_db_instance" "postgres" {

  identifier = "greeting-db"

  engine = "postgres"

  instance_class = "db.t3.micro"

  allocated_storage = 20

  db_name  = "greetings_db"
  username = var.db_username
  password = var.db_password

  db_subnet_group_name = aws_db_subnet_group.rds_subnet.name

  vpc_security_group_ids = [
    aws_security_group.rds_sg.id
  ]

  publicly_accessible = false

  skip_final_snapshot = true

  deletion_protection = false
}
