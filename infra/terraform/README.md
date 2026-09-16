# Terraform baseline

This configuration prepares a private, encrypted PostgreSQL 16 database with managed credentials, TLS enforcement, backups, and deletion protection. It has not been applied to a cloud account.

Before running a plan, agree the AWS account/region, two private subnets, application security group, supported engine minor release, encrypted remote state, budget alarm, and rollback owner. Do not apply resources without reviewing the cost and plan with both engineers.

This is the database layer only. An HTTPS application deployment and identity provider must still be configured. Use a separate least-privilege runtime database role; the managed master secret is for migrations, never for normal request handling.
