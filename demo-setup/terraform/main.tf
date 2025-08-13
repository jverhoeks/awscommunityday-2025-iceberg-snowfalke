# Demo Setup: S3 Tables + Iceberg + Snowflake
# This creates the AWS infrastructure for the demo

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    snowflake = {
      source  = "Snowflake-Labs/snowflake"
      version = "~> 0.94"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

provider "snowflake" {
  account  = var.snowflake_account
  username = var.snowflake_username
  password = var.snowflake_password
  role     = "SYSADMIN"
}

# Variables
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "iceberg-demo"
}

variable "snowflake_account" {
  description = "Snowflake account identifier"
  type        = string
}

variable "snowflake_username" {
  description = "Snowflake username"
  type        = string
}

variable "snowflake_password" {
  description = "Snowflake password"
  type        = string
  sensitive   = true
}

# S3 Bucket for Iceberg tables
resource "aws_s3_bucket" "iceberg_data" {
  bucket = "${var.project_name}-iceberg-data-${random_id.bucket_suffix.hex}"
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket_versioning" "iceberg_data" {
  bucket = aws_s3_bucket.iceberg_data.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "iceberg_data" {
  bucket = aws_s3_bucket.iceberg_data.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 Tables namespace
resource "aws_s3tables_namespace" "demo" {
  name       = "demo_analytics"
  bucket_arn = aws_s3_bucket.iceberg_data.arn
}

# Sample Iceberg table
resource "aws_s3tables_table" "user_events" {
  name         = "user_events"
  namespace    = aws_s3tables_namespace.demo.name
  bucket_arn   = aws_s3_bucket.iceberg_data.arn
  format       = "ICEBERG"
  
  schema = jsonencode({
    type = "struct"
    fields = [
      {
        id       = 1
        name     = "user_id"
        required = true
        type     = "long"
      },
      {
        id       = 2
        name     = "event_type"
        required = true
        type     = "string"
      },
      {
        id       = 3
        name     = "timestamp"
        required = true
        type     = "timestamp"
      },
      {
        id       = 4
        name     = "properties"
        required = false
        type     = {
          type      = "map"
          keyType   = "string"
          valueType = "string"
        }
      },
      {
        id       = 5
        name     = "region"
        required = true
        type     = "string"
      }
    ]
  })
}

# IAM role for Snowflake to access S3
resource "aws_iam_role" "snowflake_role" {
  name = "${var.project_name}-snowflake-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Condition = {
          StringEquals = {
            "sts:ExternalId" = var.snowflake_external_id
          }
        }
      }
    ]
  })
}

variable "snowflake_external_id" {
  description = "Snowflake external ID for assume role"
  type        = string
}

data "aws_caller_identity" "current" {}

# IAM policy for S3 access
resource "aws_iam_role_policy" "snowflake_s3_policy" {
  name = "${var.project_name}-snowflake-s3-policy"
  role = aws_iam_role.snowflake_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [
          aws_s3_bucket.iceberg_data.arn,
          "${aws_s3_bucket.iceberg_data.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "glue:GetDatabase",
          "glue:GetDatabases",
          "glue:GetTable",
          "glue:GetTables",
          "glue:GetPartition",
          "glue:GetPartitions"
        ]
        Resource = "*"
      }
    ]
  })
}

# Glue Catalog Database
resource "aws_glue_catalog_database" "demo" {
  name = "${var.project_name}_catalog"
  
  description = "Demo database for Iceberg tables"
}

# Glue Catalog Table for Iceberg
resource "aws_glue_catalog_table" "user_events" {
  name          = "user_events"
  database_name = aws_glue_catalog_database.demo.name

  table_type = "EXTERNAL_TABLE"

  parameters = {
    "table_type"           = "ICEBERG"
    "metadata_location"    = "s3://${aws_s3_bucket.iceberg_data.bucket}/demo_analytics/user_events/metadata/"
    "iceberg.table.type"   = "ICEBERG"
  }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.iceberg_data.bucket}/demo_analytics/user_events/data/"
    input_format  = "org.apache.iceberg.mr.hive.HiveIcebergInputFormat"
    output_format = "org.apache.iceberg.mr.hive.HiveIcebergOutputFormat"

    ser_de_info {
      serialization_library = "org.apache.iceberg.mr.hive.HiveIcebergSerDe"
    }

    columns {
      name = "user_id"
      type = "bigint"
    }

    columns {
      name = "event_type"
      type = "string"
    }

    columns {
      name = "timestamp"
      type = "timestamp"
    }

    columns {
      name = "properties"
      type = "map<string,string>"
    }

    columns {
      name = "region"
      type = "string"
    }
  }
}

# Outputs
output "s3_bucket_name" {
  description = "Name of the S3 bucket for Iceberg data"
  value       = aws_s3_bucket.iceberg_data.bucket
}

output "glue_database_name" {
  description = "Name of the Glue catalog database"
  value       = aws_glue_catalog_database.demo.name
}

output "snowflake_role_arn" {
  description = "ARN of the IAM role for Snowflake"
  value       = aws_iam_role.snowflake_role.arn
}

output "s3_table_arn" {
  description = "ARN of the S3 table"
  value       = aws_s3tables_table.user_events.arn
}