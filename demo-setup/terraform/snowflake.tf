# Snowflake Configuration for Iceberg Demo

# Create warehouse for demo
resource "snowflake_warehouse" "demo_warehouse" {
  name           = "ICEBERG_DEMO_WH"
  warehouse_size = "X-SMALL"
  auto_suspend   = 60
  auto_resume    = true
  
  comment = "Warehouse for Iceberg demo"
}

# Create database
resource "snowflake_database" "demo_db" {
  name    = "ICEBERG_DEMO"
  comment = "Database for Iceberg demo"
}

# Create schema
resource "snowflake_schema" "demo_schema" {
  database = snowflake_database.demo_db.name
  name     = "ANALYTICS"
  comment  = "Schema for analytics tables"
}

# Create storage integration for S3 access
resource "snowflake_storage_integration" "s3_integration" {
  name    = "ICEBERG_S3_INTEGRATION"
  comment = "Storage integration for Iceberg S3 access"
  type    = "EXTERNAL_STAGE"

  enabled = true

  storage_allowed_locations = [
    "s3://${aws_s3_bucket.iceberg_data.bucket}/*"
  ]

  storage_provider = "S3"

  storage_aws_role_arn = aws_iam_role.snowflake_role.arn
}

# Create external stage
resource "snowflake_stage" "iceberg_stage" {
  name     = "ICEBERG_STAGE"
  database = snowflake_database.demo_db.name
  schema   = snowflake_schema.demo_schema.name

  url = "s3://${aws_s3_bucket.iceberg_data.bucket}/demo_analytics/"

  storage_integration = snowflake_storage_integration.s3_integration.name

  file_format = "TYPE = PARQUET"
  
  comment = "External stage for Iceberg tables"
}

# Create catalog integration for Glue
resource "snowflake_catalog_integration" "glue_catalog" {
  name    = "GLUE_CATALOG_INTEGRATION"
  comment = "Catalog integration for AWS Glue"

  catalog_source = "GLUE"
  
  table_format = "ICEBERG"

  glue_aws_role_arn = aws_iam_role.snowflake_role.arn
  
  glue_catalog_id = data.aws_caller_identity.current.account_id
  
  glue_region = var.aws_region

  enabled = true
}

# Create roles for demo
resource "snowflake_role" "data_analyst" {
  name    = "DATA_ANALYST"
  comment = "Role for data analysts"
}

resource "snowflake_role" "data_scientist" {
  name    = "DATA_SCIENTIST"
  comment = "Role for data scientists"
}

# Grant permissions to roles
resource "snowflake_grant_privileges_to_role" "analyst_warehouse" {
  privileges = ["USAGE"]
  role_name  = snowflake_role.data_analyst.name
  on_account_object {
    object_type = "WAREHOUSE"
    object_name = snowflake_warehouse.demo_warehouse.name
  }
}

resource "snowflake_grant_privileges_to_role" "analyst_database" {
  privileges = ["USAGE"]
  role_name  = snowflake_role.data_analyst.name
  on_account_object {
    object_type = "DATABASE"
    object_name = snowflake_database.demo_db.name
  }
}

resource "snowflake_grant_privileges_to_role" "analyst_schema" {
  privileges = ["USAGE"]
  role_name  = snowflake_role.data_analyst.name
  on_schema {
    schema_name = "\"${snowflake_database.demo_db.name}\".\"${snowflake_schema.demo_schema.name}\""
  }
}

# Create standard Snowflake table for comparison
resource "snowflake_table" "user_profiles" {
  database = snowflake_database.demo_db.name
  schema   = snowflake_schema.demo_schema.name
  name     = "USER_PROFILES"

  column {
    name = "USER_ID"
    type = "NUMBER(38,0)"
  }

  column {
    name = "NAME"
    type = "VARCHAR(255)"
  }

  column {
    name = "EMAIL"
    type = "VARCHAR(255)"
  }

  column {
    name = "REGION"
    type = "VARCHAR(50)"
  }

  column {
    name = "CREATED_AT"
    type = "TIMESTAMP_NTZ"
  }

  comment = "Standard Snowflake table for user profiles"
}

# Output Snowflake connection details
output "snowflake_warehouse" {
  description = "Snowflake warehouse name"
  value       = snowflake_warehouse.demo_warehouse.name
}

output "snowflake_database" {
  description = "Snowflake database name"
  value       = snowflake_database.demo_db.name
}

output "snowflake_schema" {
  description = "Snowflake schema name"
  value       = snowflake_schema.demo_schema.name
}

output "storage_integration_name" {
  description = "Storage integration name"
  value       = snowflake_storage_integration.s3_integration.name
}

output "catalog_integration_name" {
  description = "Catalog integration name"
  value       = snowflake_catalog_integration.glue_catalog.name
}