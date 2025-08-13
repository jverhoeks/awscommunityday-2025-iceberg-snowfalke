# Iceberg + Snowflake Demo Setup

This demo setup creates a complete environment to demonstrate the integration between S3 Tables (Iceberg), AWS Glue Catalog, and Snowflake for the AWS Community Builders presentation.

## Architecture Overview

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Data Sources  │───▶│   S3 Tables      │───▶│   Snowflake     │
│   (Generated)   │    │   (Iceberg)      │    │   (External)    │
├─────────────────┤    ├──────────────────┤    ├─────────────────┤
│ • Small files   │    │ • Auto-maintain  │    │ • Query engine  │
│ • Large files   │    │ • ACID           │    │ • Analytics     │
│ • User profiles │    │ • Schema evolve  │    │ • Reporting     │
└─────────────────┘    └──────────────────┘    └─────────────────┘
                              │
                              ▼
                       ┌──────────────────┐
                       │  AWS Glue        │
                       │  Catalog         │
                       └──────────────────┘
```

## Prerequisites

### AWS Requirements
- AWS CLI configured with appropriate permissions
- Terraform >= 1.0
- Python 3.8+
- Access to create S3 buckets, IAM roles, Glue catalogs, and S3 Tables

### Snowflake Requirements
- Snowflake account with SYSADMIN privileges
- Ability to create warehouses, databases, and external integrations

### Required AWS Permissions
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:*",
        "s3tables:*",
        "glue:*",
        "iam:*"
      ],
      "Resource": "*"
    }
  ]
}
```

## Setup Instructions

### Step 1: Infrastructure Deployment

1. **Clone and navigate to terraform directory:**
   ```bash
   cd demo-setup/terraform
   ```

2. **Configure variables:**
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your values
   ```

3. **Deploy infrastructure:**
   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

4. **Note the outputs:**
   ```bash
   terraform output
   ```

### Step 2: Generate Sample Data

1. **Install Python dependencies:**
   ```bash
   cd ../data-generation
   pip install -r requirements.txt
   ```

2. **Generate sample data:**
   ```bash
   # Get bucket name from terraform output
   BUCKET_NAME=$(cd ../terraform && terraform output -raw s3_bucket_name)
   
   # Generate both small and large file scenarios
   python generate_sample_data.py --bucket $BUCKET_NAME --scenario both
   ```

   This creates:
   - **Small files scenario**: 7 days of streaming data (144 files/day, ~10-50 records each)
   - **Large files scenario**: 30 days of batch data (4 files/day, ~10K-50K records each)
   - **User profiles CSV**: 10K user profiles for Snowflake standard table

### Step 3: Configure Snowflake

1. **Load user profiles data:**
   ```sql
   -- In Snowflake, upload user_profiles.csv and run:
   USE WAREHOUSE ICEBERG_DEMO_WH;
   USE DATABASE ICEBERG_DEMO;
   USE SCHEMA ANALYTICS;
   
   COPY INTO user_profiles
   FROM @%user_profiles
   FILE_FORMAT = (TYPE = CSV SKIP_HEADER = 1);
   ```

2. **Create external table:**
   ```sql
   -- Create external table pointing to Iceberg data
   CREATE OR REPLACE EXTERNAL TABLE ext_user_events
   USING TEMPLATE (
     SELECT ARRAY_AGG(OBJECT_CONSTRUCT(*))
     FROM TABLE(INFER_SCHEMA(
       LOCATION=>'@ICEBERG_STAGE/user_events/',
       FILE_FORMAT=>(TYPE=PARQUET)
     ))
   );
   ```

### Step 4: Run Performance Tests

1. **Install test dependencies:**
   ```bash
   cd ../performance-tests
   pip install -r ../data-generation/requirements.txt
   ```

2. **Run automated performance tests:**
   ```bash
   python run_performance_tests.py \
     --account your-account.region \
     --username your-username \
     --password your-password \
     --test-suite all
   ```

3. **Or run manual SQL tests:**
   ```bash
   # Copy and paste queries from performance_comparison.sql into Snowflake
   ```

## Demo Scenarios

### Scenario 1: Small File Problem Demonstration

**Purpose**: Show how streaming data creates performance issues

**Setup**: 
- 7 days of small files (1,008 files total)
- Each file contains 10-50 records
- Demonstrates metadata overhead

**Queries to run**:
```sql
-- Show the impact of many small files
SELECT COUNT(*) FROM ext_user_events WHERE timestamp >= CURRENT_DATE - 1;
-- Note: Slow performance due to many file reads
```

### Scenario 2: Optimal File Size Comparison

**Purpose**: Compare performance with properly sized files

**Setup**:
- 30 days of large files (120 files total)
- Each file contains 10K-50K records
- Demonstrates optimal performance

**Queries to run**:
```sql
-- Same query on optimally sized files
SELECT COUNT(*) FROM ext_user_events WHERE timestamp < CURRENT_DATE - 7;
-- Note: Much faster performance
```

### Scenario 3: Hybrid Architecture Benefits

**Purpose**: Show how to combine standard and external tables

**Setup**:
- Hot data (recent) in standard Snowflake tables
- Cold data (historical) in external Iceberg tables
- Unified view combining both

**Queries to run**:
```sql
-- Create hot data table
CREATE TABLE hot_user_events AS
SELECT * FROM ext_user_events WHERE timestamp >= CURRENT_DATE - 7;

-- Create unified view
CREATE VIEW complete_user_events AS
SELECT * FROM hot_user_events
UNION ALL
SELECT * FROM ext_user_events WHERE timestamp < CURRENT_DATE - 7;

-- Query unified view
SELECT event_type, COUNT(*) FROM complete_user_events GROUP BY event_type;
```

### Scenario 4: Cost Analysis

**Purpose**: Demonstrate cost differences between approaches

**Queries to run**:
```sql
-- Analyze warehouse usage
SELECT 
  query_type,
  COUNT(*) as query_count,
  SUM(total_elapsed_time) / 1000 as total_seconds,
  SUM(credits_used_cloud_services) as credits_used
FROM snowflake.account_usage.query_history
WHERE start_time >= CURRENT_DATE - 1
  AND warehouse_name = 'ICEBERG_DEMO_WH'
GROUP BY query_type;

-- Compare storage costs
SELECT 
  table_name,
  bytes / (1024*1024*1024) as storage_gb,
  row_count
FROM snowflake.account_usage.table_storage_metrics
WHERE table_schema = 'ANALYTICS';
```

## Expected Performance Results

### Typical Performance Comparison

| Test | Standard Table | External Iceberg | Difference |
|------|---------------|------------------|------------|
| Count All | 0.5s | 1.2s | +140% |
| Filtered Query | 0.8s | 2.1s | +163% |
| Complex Join | 2.3s | 4.7s | +104% |
| Aggregation | 1.1s | 2.8s | +155% |

### Cost Comparison (1TB dataset)

| Approach | Monthly Storage | Compute Hours | Total Cost |
|----------|----------------|---------------|------------|
| Pure Snowflake | $40 | 100h @ $2/h | $240 |
| S3 Tables + Snowflake | $100 | 50h @ $2/h | $200 |
| **Savings** | | | **17%** |

*Note: Savings increase significantly with larger datasets*

## Maintenance Demonstration

### Show Compaction Benefits

1. **Before compaction** (small files):
   ```bash
   # Count files in S3
   aws s3 ls s3://your-bucket/demo_analytics/user_events/data/ --recursive | wc -l
   ```

2. **Simulate compaction** (using S3 Tables auto-compaction):
   ```sql
   -- S3 Tables automatically compacts files
   -- Query performance improves over time
   ```

3. **After compaction** (fewer, larger files):
   ```bash
   # Fewer files, better performance
   aws s3 ls s3://your-bucket/demo_analytics/user_events/data/ --recursive | wc -l
   ```

## Cleanup

```bash
# Destroy all resources
cd terraform
terraform destroy

# Clean up local files
cd ../data-generation
rm -f user_profiles.csv

cd ../performance-tests
rm -f performance_report_*.json
```

## Troubleshooting

### Common Issues

1. **Terraform fails with S3 Tables**:
   - Ensure S3 Tables is available in your region
   - Check AWS CLI version (requires latest)

2. **Snowflake external table creation fails**:
   - Verify storage integration is properly configured
   - Check IAM role trust relationship
   - Ensure external ID matches

3. **Performance tests fail**:
   - Verify Snowflake connection parameters
   - Check that external table exists and has data
   - Ensure warehouse is running

4. **Data generation fails**:
   - Check AWS credentials and S3 permissions
   - Verify bucket exists and is accessible
   - Check Python dependencies

### Debug Commands

```bash
# Check S3 Tables
aws s3tables list-namespaces --bucket-arn arn:aws:s3:::your-bucket

# Check Glue catalog
aws glue get-tables --database-name your-database

# Test Snowflake connection
python -c "import snowflake.connector; print('Snowflake connector works')"
```

## Presentation Integration

This demo setup supports all the key points in the presentation:

1. **Cost Problem**: Compare Snowflake vs S3 Tables costs
2. **Iceberg Benefits**: Show ACID, schema evolution, time travel
3. **Maintenance Issues**: Demonstrate small file problem
4. **S3 Tables Solution**: Show automated maintenance
5. **Integration Strategy**: Demonstrate hybrid architecture
6. **Performance Comparison**: Real metrics between approaches

Use the generated performance reports and cost analysis in your presentation to provide concrete evidence of the benefits discussed.