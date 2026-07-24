resource "aws_ecs_cluster" "main" {
  name = "url-shortener-cluster"

  setting {
    name  = "containerInsights"
    value = "disabled"
  }
}

resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/url-shortener"
  retention_in_days = 7
}

resource "aws_ecs_task_definition" "app" {
  family                   = "url-shortener"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name      = "app"
      image = "${aws_ecr_repository.app.repository_url}:v2"
      essential = true

      portMappings = [
        {
          containerPort = 3000
          protocol      = "tcp"
        }
      ]

      environment = [
        { name = "PORT", value = "3000" },
        { name = "BASE_URL", value = "http://${aws_lb.main.dns_name}" },
        { name = "NODE_ENV", value = "production" },
        { name = "REDIS_URL", value = "redis://${aws_elasticache_cluster.main.cache_nodes[0].address}:6379" }
      ]

      secrets = [
        {
          name      = "DATABASE_URL"
          valueFrom = aws_secretsmanager_secret.db_url.arn
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.app.name
          "awslogs-region"        = "us-east-1"
          "awslogs-stream-prefix" = "app"
        }
      }
    }
  ])
}