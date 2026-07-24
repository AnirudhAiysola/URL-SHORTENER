resource "aws_security_group" "alb" {
  name        = "url-shortener-alb-sg"
  description = "Allows public HTTP traffic to the load balancer"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from anywhere"
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

  tags = {
    Name = "url-shortener-alb-sg"
  }
}

resource "aws_security_group" "app" {
  name        = "url-shortener-app-sg"
  description = "Allows traffic from the load balancer only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "App port from ALB"
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "url-shortener-app-sg"
  }
}

resource "aws_security_group" "db" {
  name        = "url-shortener-db-sg"
  description = "Allows Postgres traffic from the app only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Postgres from app"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  tags = {
    Name = "url-shortener-db-sg"
  }
}