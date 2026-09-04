resource "aws_security_group" "alb_sg" {

  name = "alb_sg"

  description = "Allow HTTP traffic to ALB"

  vpc_id = module.vpc.vpc_id

  ingress {

    description = "HTTP"

    from_port = 80
    to_port   = 80
    protocol  = "tcp"

    cidr_blocks = [
      "0.0.0.0/0"
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


resource "aws_lb" "app_alb" {

  name = "greeting-alb"

  internal = false

  load_balancer_type = "application"

  security_groups = [
    aws_security_group.alb_sg.id
  ]

  subnets = module.vpc.public_subnets

  tags = {
    Name = "GreetingApp-ALB"
  }
}


resource "aws_lb_target_group" "app_tg" {

  name = "app-tg"

  port = 5001

  protocol = "HTTP"

  vpc_id = module.vpc.vpc_id

  target_type = "instance"

  health_check {

    path = "/check"

    port = "5001"

    protocol = "HTTP"

    interval = 30

    timeout = 5

    healthy_threshold = 2

    unhealthy_threshold = 2

    matcher = "200"
  }

  tags = {
    Name = "GreetingApp-TG"
  }
}


resource "aws_lb_listener" "app_listener" {

  load_balancer_arn = aws_lb.app_alb.arn

  port = 80

  protocol = "HTTP"

  default_action {

    type = "forward"

    target_group_arn = aws_lb_target_group.app_tg.arn
  }
}


resource "aws_lb_target_group_attachment" "ec2_attach" {

  target_group_arn = aws_lb_target_group.app_tg.arn

  target_id = aws_instance.flask_ec2.id

  port = 5001
}
