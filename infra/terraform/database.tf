variable "private_subnet_ids" {
  type = list(string)
  validation {
    condition     = length(var.private_subnet_ids) >= 2
    error_message = "Use private subnets in at least two availability zones."
  }
}

variable "vpc_id" { type = string }
variable "application_security_group_id" { type = string }
variable "postgres_engine_version" {
  type = string
  validation {
    condition     = can(regex("^16\\.", var.postgres_engine_version))
    error_message = "Select a currently supported PostgreSQL 16 minor release."
  }
}

resource "aws_db_subnet_group" "plug" {
  name       = "plug-staging-private"
  subnet_ids = var.private_subnet_ids
}

resource "aws_security_group" "database" {
  name        = "plug-staging-database"
  description = "Database access from the application only"
  vpc_id      = var.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "application" {
  security_group_id            = aws_security_group.database.id
  referenced_security_group_id = var.application_security_group_id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}

resource "aws_db_parameter_group" "plug" {
  name   = "plug-staging-postgres16"
  family = "postgres16"
  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }
}

resource "aws_db_instance" "plug" {
  identifier                      = "plug-staging"
  engine                          = "postgres"
  engine_version                  = var.postgres_engine_version
  instance_class                  = "db.t4g.micro"
  allocated_storage               = 20
  max_allocated_storage           = 50
  storage_type                    = "gp3"
  storage_encrypted               = true
  db_name                         = "plug"
  username                        = "plug_migrator"
  manage_master_user_password     = true
  publicly_accessible             = false
  db_subnet_group_name            = aws_db_subnet_group.plug.name
  vpc_security_group_ids          = [aws_security_group.database.id]
  parameter_group_name            = aws_db_parameter_group.plug.name
  backup_retention_period         = 14
  deletion_protection             = true
  skip_final_snapshot             = false
  final_snapshot_identifier       = "plug-staging-final"
  copy_tags_to_snapshot           = true
  auto_minor_version_upgrade      = true
  enabled_cloudwatch_logs_exports = ["postgresql"]
  tags                            = { Project = "PLUG", Environment = "staging" }
}

output "database_endpoint" { value = aws_db_instance.plug.address }
output "migration_secret_arn" {
  value     = aws_db_instance.plug.master_user_secret[0].secret_arn
  sensitive = true
}
