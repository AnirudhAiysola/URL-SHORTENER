resource "aws_secretsmanager_secret" "db_url" {
  name                    = "url-shortener/database-url"
  description             = "Postgres connection string for the URL shortener"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "db_url" {
  secret_id = aws_secretsmanager_secret.db_url.id
  secret_string = format(
    "postgres://%s:%s@%s/%s",
    aws_db_instance.main.username,
    random_password.db.result,
    aws_db_instance.main.endpoint,
    aws_db_instance.main.db_name
  )
}