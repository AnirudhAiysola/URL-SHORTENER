data "aws_iam_policy_document" "ecs_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_execution" {
  name               = "url-shortener-ecs-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json
}

resource "aws_iam_role_policy_attachment" "ecs_execution_managed" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "read_db_secret" {
  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.db_url.arn]
  }
}

resource "aws_iam_role_policy" "ecs_execution_secrets" {
  name   = "read-db-secret"
  role   = aws_iam_role.ecs_execution.id
  policy = data.aws_iam_policy_document.read_db_secret.json
}

resource "aws_iam_role" "ecs_task" {
  name               = "url-shortener-ecs-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json
}