resource "random_password" "db" {
  length  = 32
  special = false
}

resource "aws_db_subnet_group" "main" {
  name       = "url-shortener-db-subnet-group"
  subnet_ids = aws_subnet.private[*].id

  tags = {
    Name = "url-shortener-db-subnet-group"
  }
}

resource "aws_db_instance" "main" {
  identifier     = "url-shortener-db"
  engine         = "postgres"
  engine_version = "16"
  instance_class = "db.t4g.micro"

  allocated_storage     = 20
  max_allocated_storage = 50
  storage_encrypted     = true

  db_name  = "shortener"
  username = "shortener"
  password = random_password.db.result

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = false

  backup_retention_period = 1
  skip_final_snapshot     = true
  deletion_protection     = false

  tags = {
    Name = "url-shortener-db"
  }
}