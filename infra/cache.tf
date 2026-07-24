resource "aws_security_group" "redis" {
  name        = "url-shortener-redis-sg"
  description = "Allows Redis traffic from the app only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Redis from app"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  tags = {
    Name = "url-shortener-redis-sg"
  }
}

resource "aws_elasticache_subnet_group" "main" {
  name       = "url-shortener-cache-subnet-group"
  subnet_ids = aws_subnet.private[*].id
}

resource "aws_elasticache_cluster" "main" {
  cluster_id           = "url-shortener-cache"
  engine               = "redis"
  node_type            = "cache.t4g.micro"
  num_cache_nodes      = 1
  parameter_group_name = "default.redis7"
  engine_version       = "7.1"
  port                 = 6379

  subnet_group_name  = aws_elasticache_subnet_group.main.name
  security_group_ids = [aws_security_group.redis.id]

  tags = {
    Name = "url-shortener-cache"
  }
}

output "redis_endpoint" {
  value = aws_elasticache_cluster.main.cache_nodes[0].address
}