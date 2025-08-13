# Building a Scalable Data Platform with S3 Tables, Iceberg and Snowflake

## AWS Community Builders Day Presentation
*Duration: ~50 minutes*

---

## Opening Quote

> "Snowflake is expensive, everyone knows that. But what if I told you there's a way to keep the power while cutting the costs?"

---

## Agenda

1. **The Cost Problem** (5 min)
2. **Apache Iceberg Deep Dive** (20 min)
3. **Iceberg REST API & Security** (8 min)
4. **S3 Tables: The Game Changer** (8 min)
5. **Snowflake's Evolution** (7 min)
6. **The Integration Strategy** (5 min)
7. **Q&A** (2 min)

---

## 1. The Cost Problem 💰

### Why Everyone Says "Snowflake is Expensive"

- **Compute costs** scale with usage
- **Storage costs** for proprietary format
- **Data egress** charges for moving data out
- **Vendor lock-in** limits flexibility

### The Traditional Dilemma

```
High Performance + Easy Management = High Cost
```

**What if we could break this equation?**

---

## 2. Apache Iceberg Deep Dive 🧊

### What is Apache Iceberg?

Apache Iceberg is an **open table format** for huge analytic datasets that brings:
- ACID transactions to data lakes
- Schema evolution
- Time travel capabilities
- Efficient metadata management

### The Magic Behind Iceberg

#### Traditional Parquet on S3
```
s3://bucket/data/
├── file1.parquet
├── file2.parquet
├── file3.parquet
└── ...
```

**Problems:**
- No ACID guarantees
- Manual partition management
- Expensive full table scans
- No schema evolution

---

### Iceberg's Three-Layer Architecture

#### 1. Data Layer
```
s3://bucket/warehouse/table/data/
├── 00001-1-data.parquet
├── 00002-2-data.parquet
└── 00003-3-data.parquet
```

#### 2. Metadata Layer
```
s3://bucket/warehouse/table/metadata/
├── v1.metadata.json
├── v2.metadata.json
└── snap-123456789.avro
```

#### 3. Catalog Layer
- **AWS Glue Catalog**
- **Apache Hive Metastore**
- **Custom REST Catalog**

---

### Iceberg Metadata Structure Deep Dive

#### The Metadata Hierarchy
```
Table Metadata (v1.metadata.json)
├── Schema (columns, types)
├── Partition Spec (how data is partitioned)
├── Sort Order (optimization hints)
├── Current Snapshot ID
└── Snapshot Log (history)

Snapshot (snap-123456789.avro)
├── Snapshot ID & timestamp
├── Summary (added/deleted files count)
├── Manifest List (pointer to manifests)
└── Schema ID (schema version used)

Manifest Files (manifest-123.avro)
├── Data File Paths
├── Partition Values
├── Record Counts
├── File Size & Metrics
└── Column Statistics (min/max/null counts)
```

#### Example Metadata JSON
```json
{
  "format-version": 2,
  "table-uuid": "9c12d441-03fe-4693-9a96-a0705ddf69c1",
  "location": "s3://bucket/warehouse/table",
  "last-sequence-number": 34,
  "last-updated-ms": 1602638573590,
  "last-column-id": 3,
  "current-schema-id": 1,
  "schemas": [
    {
      "schema-id": 1,
      "fields": [
        {"id": 1, "name": "user_id", "required": true, "type": "long"},
        {"id": 2, "name": "event_type", "required": false, "type": "string"},
        {"id": 3, "name": "timestamp", "required": true, "type": "timestamptz"}
      ]
    }
  ],
  "current-snapshot-id": 3055729675574597004,
  "snapshots": [
    {
      "snapshot-id": 3055729675574597004,
      "timestamp-ms": 1602638573590,
      "summary": {
        "operation": "append",
        "added-data-files": "4",
        "added-records": "4444",
        "added-files-size": "31616"
      },
      "manifest-list": "s3://bucket/warehouse/table/metadata/snap-3055729675574597004-1-c87bfec7-d36c-4075-ad04-2c97c05e24a2.avro"
    }
  ]
}
```

---

### Metadata Structure: Pros and Cons

#### Pros ✅
1. **Atomic Operations**
   - Single metadata file update = atomic transaction
   - No partial writes visible to readers

2. **Efficient Query Planning**
   - Statistics in manifests enable predicate pushdown
   - Partition pruning without scanning data

3. **Time Travel**
   - Complete snapshot history preserved
   - Point-in-time queries without data duplication

4. **Schema Evolution**
   - Schema changes tracked in metadata
   - Backward/forward compatibility

#### Cons ❌
1. **Metadata Growth**
   - Each write creates new manifest files
   - Snapshot history accumulates over time
   - Can become bottleneck for frequent writes

2. **Small File Problem**
   - Many small writes = many small files
   - Manifest overhead increases
   - Query performance degrades

3. **Eventual Consistency**
   - S3's eventual consistency affects metadata reads
   - Potential for stale metadata views

4. **Complexity**
   - More moving parts than simple file formats
   - Requires understanding of metadata lifecycle

---

### ACID Transactions in Action

#### Before Iceberg (Parquet)
```sql
-- Writer 1
INSERT INTO table VALUES (1, 'data1');

-- Writer 2 (concurrent)
INSERT INTO table VALUES (2, 'data2');

-- Result: Potential data corruption or loss
```

#### With Iceberg
```sql
-- Writer 1
INSERT INTO iceberg_table VALUES (1, 'data1');
-- Creates snapshot_1

-- Writer 2 (concurrent)  
INSERT INTO iceberg_table VALUES (2, 'data2');
-- Creates snapshot_2

-- Result: Both writes succeed atomically
```

---

### Schema Evolution Made Easy

```sql
-- Day 1: Initial schema
CREATE TABLE user_events (
    user_id BIGINT,
    event_type STRING,
    timestamp TIMESTAMP
);

-- Day 30: Need to add new column
ALTER TABLE user_events 
ADD COLUMN device_type STRING;

-- Day 60: Need to rename column
ALTER TABLE user_events 
RENAME COLUMN event_type TO action_type;
```

**No data rewriting required!** 🎉

---

### Time Travel Capabilities

```sql
-- Query data as it was yesterday
SELECT * FROM user_events 
FOR SYSTEM_TIME AS OF '2024-01-15 10:00:00';

-- Query specific snapshot
SELECT * FROM user_events 
FOR SYSTEM_VERSION AS OF 12345;

-- See all snapshots
SELECT * FROM user_events.snapshots;
```

---

### Maintenance Requirements: The Why and How ⚠️

#### Why Maintenance is Critical

**The Small File Problem Illustrated:**
```
Day 1: 1 insert → 1 file (100MB)
Day 2: 100 inserts → 100 files (1MB each)
Day 3: 1000 inserts → 1000 files (100KB each)

Result: 1101 files for 200MB of data!
```

**What Happens Without Compaction:**
1. **Query Performance Degrades**
   - More files = more I/O operations
   - Manifest files grow exponentially
   - Planning time increases dramatically

2. **Storage Costs Increase**
   - Small files have overhead
   - Metadata storage grows
   - S3 request costs multiply

3. **Memory Pressure**
   - Query engines load more file metadata
   - Spark/Trino struggle with file listing
   - OOM errors become common

#### Real-World Example: The Disaster Scenario

```
Table: user_events (streaming inserts every minute)
Timeline without maintenance:

Week 1: 10,080 files (1 per minute)
├── Query time: 2 seconds
├── Planning time: 500ms
└── Storage: 1GB data + 50MB metadata

Month 1: 43,200 files  
├── Query time: 30 seconds
├── Planning time: 10 seconds  
└── Storage: 4GB data + 500MB metadata

Month 6: 259,200 files
├── Query time: 5+ minutes
├── Planning time: 2+ minutes
└── Storage: 24GB data + 5GB metadata
└── Result: Table becomes unusable! 💥
```

#### The Three Pillars of Iceberg Maintenance

#### 1. **Compaction (File Consolidation)**
```sql
-- Before compaction
data/
├── file-001.parquet (1MB)
├── file-002.parquet (1MB)  
├── file-003.parquet (1MB)
└── ... (997 more 1MB files)

-- After compaction  
data/
├── file-compacted-001.parquet (250MB)
├── file-compacted-002.parquet (250MB)
├── file-compacted-003.parquet (250MB)
└── file-compacted-004.parquet (250MB)

-- Command
CALL system.rewrite_data_files(
  table => 'db.table',
  options => map('target-file-size-bytes', '268435456')
);
```

#### 2. **Snapshot Expiration (History Cleanup)**
```sql
-- Snapshot accumulation over time
metadata/
├── snap-001.avro (Day 1)
├── snap-002.avro (Day 2)
├── snap-003.avro (Day 3)
└── ... (365 snapshots for 1 year)

-- Expire old snapshots (keep 30 days)
CALL system.expire_snapshots(
  table => 'db.table',
  older_than => TIMESTAMP '2024-01-01 00:00:00',
  retain_last => 30
);
```

#### 3. **Orphan File Cleanup (Garbage Collection)**
```sql
-- Files that exist but aren't referenced
data/
├── active-file-001.parquet ✅ (referenced)
├── active-file-002.parquet ✅ (referenced)
├── old-file-003.parquet ❌ (orphaned after compaction)
└── failed-write-004.parquet ❌ (orphaned after failed write)

-- Clean up orphaned files
CALL system.remove_orphan_files(
  table => 'db.table',
  older_than => TIMESTAMP '2024-01-01 00:00:00'
);
```

#### Maintenance Scheduling Strategy

```yaml
Maintenance Schedule:
  Compaction:
    - Frequency: Daily for high-write tables
    - Trigger: When avg file size < 100MB
    - Target: 256MB files
    
  Snapshot Expiration:
    - Frequency: Weekly
    - Retention: 30 days for production
    - Retention: 7 days for staging
    
  Orphan Cleanup:
    - Frequency: Weekly
    - Safety window: 3 days
    - Dry-run first: Always
```

#### The Manual Burden Reality
- **Monitoring**: File count, sizes, query performance
- **Scheduling**: Cron jobs, Airflow DAGs, Lambda functions
- **Coordination**: Avoiding conflicts with writes
- **Alerting**: When maintenance fails or is needed
- **Cost tracking**: Maintenance compute costs

---

## 3. Iceberg REST API: Security Game Changer 🔐

### The Traditional Data Access Problem

#### Direct S3 Access Model
```
┌─────────────┐    Direct S3 Access   ┌─────────────┐
│   Client    │ ────────────────────▶ │     S3      │
│ (Spark/etc) │                       │   Bucket    │
└─────────────┘                       └─────────────┘

Problems:
❌ Broad S3 permissions required
❌ No fine-grained access control  
❌ Credentials scattered everywhere
❌ No audit trail for data access
❌ Hard to revoke access
```

#### What Clients Need for Direct Access
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject", 
        "s3:DeleteObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::data-lake-bucket/*",
        "arn:aws:s3:::data-lake-bucket"
      ]
    }
  ]
}
```
**Every client needs full bucket access!** 😱

---

### Iceberg REST API: The Solution

#### Controlled Access Architecture
```
┌─────────────┐    REST API     ┌─────────────┐    Vended Creds    ┌─────────────┐
│   Client    │ ──────────────▶ │  Iceberg    │ ─────────────────▶ │     S3      │
│ (Spark/etc) │                 │ REST Catalog│                    │   Bucket    │
└─────────────┘                 └─────────────┘                    └─────────────┘
                                       │
                                       ▼
                                ┌─────────────┐
                                │   Auth &    │
                                │ Permissions │
                                └─────────────┘
```

#### How REST API Works

1. **Client Authentication**
```http
POST /v1/oauth/tokens
Content-Type: application/json

{
  "grant_type": "client_credentials",
  "client_id": "spark-app-1",
  "client_secret": "secret123"
}

Response:
{
  "access_token": "eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9...",
  "token_type": "Bearer",
  "expires_in": 3600
}
```

2. **Table Discovery**
```http
GET /v1/namespaces/analytics/tables
Authorization: Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9...

Response:
{
  "identifiers": [
    {"namespace": ["analytics"], "name": "user_events"},
    {"namespace": ["analytics"], "name": "product_catalog"}
  ]
}
```

3. **Credential Vending**
```http
GET /v1/namespaces/analytics/tables/user_events
Authorization: Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9...

Response:
{
  "metadata-location": "s3://bucket/warehouse/analytics/user_events/metadata/v1.json",
  "config": {
    "s3.access-key-id": "ASIA...",
    "s3.secret-access-key": "temp-secret",
    "s3.session-token": "temp-token",
    "s3.expiration": "2024-01-15T12:00:00Z"
  }
}
```

---

### Fine-Grained Security Benefits

#### Table-Level Permissions
```yaml
User: data-scientist-alice
Permissions:
  - analytics.user_events: READ
  - analytics.product_catalog: READ
  - staging.*: READ, WRITE

User: etl-service  
Permissions:
  - raw.*: READ, WRITE
  - analytics.*: WRITE
  - staging.*: READ, WRITE, DELETE

User: external-partner
Permissions:
  - public.aggregated_metrics: READ
```

#### Column-Level Security
```sql
-- REST API can enforce column filtering
SELECT user_id, event_type, timestamp 
FROM analytics.user_events;

-- For user 'external-partner', automatically becomes:
SELECT 
  hash(user_id) as user_id,  -- PII masked
  event_type, 
  timestamp 
FROM analytics.user_events;
```

#### Row-Level Security
```sql
-- Policy: Users can only see their own region's data
CREATE POLICY region_policy ON analytics.user_events
FOR SELECT TO 'regional-analyst'
USING (region = current_user_region());
```

---

### Credential Vending Deep Dive

#### Traditional Approach: Long-lived Credentials
```yaml
Problems:
  - Credentials in config files
  - Hard to rotate
  - Broad permissions
  - No expiration
  - Difficult audit trail
```

#### REST API Approach: Temporary Credentials
```yaml
Benefits:
  - Short-lived (1-12 hours)
  - Scoped to specific tables/operations
  - Automatic rotation
  - Full audit trail
  - Easy revocation
```

#### Example Vended Credentials
```json
{
  "s3.access-key-id": "ASIAXAMPLE123456789",
  "s3.secret-access-key": "temp-secret-key-12345",
  "s3.session-token": "very-long-session-token...",
  "s3.expiration": "2024-01-15T12:00:00Z",
  "s3.region": "us-west-2",
  "allowed-locations": [
    "s3://data-lake/analytics/user_events/*"
  ],
  "allowed-operations": ["READ"]
}
```

---

### Security Architecture Benefits

#### 1. **Zero Trust Data Access**
- No permanent credentials in client applications
- Every access request authenticated and authorized
- Principle of least privilege enforced

#### 2. **Centralized Policy Management**
```yaml
# Single place to manage all data access policies
REST Catalog Configuration:
  authentication:
    type: "oauth2"
    provider: "aws-cognito"
  
  authorization:
    type: "rbac"
    policies:
      - role: "data-scientist"
        tables: ["analytics.*"]
        operations: ["READ"]
      - role: "etl-service"
        tables: ["*"]
        operations: ["READ", "WRITE"]
```

#### 3. **Comprehensive Audit Trail**
```json
{
  "timestamp": "2024-01-15T10:30:00Z",
  "user": "alice@company.com",
  "action": "table.read",
  "resource": "analytics.user_events",
  "client": "spark-app-1",
  "ip": "10.0.1.100",
  "credentials_issued": {
    "expiration": "2024-01-15T11:30:00Z",
    "permissions": ["s3:GetObject"],
    "scope": "s3://data-lake/analytics/user_events/*"
  }
}
```

#### 4. **Easy Integration with Enterprise Auth**
- LDAP/Active Directory integration
- SAML/OAuth2 support
- Multi-factor authentication
- Role-based access control (RBAC)

---

### REST API vs Direct Access Comparison

| Aspect | Direct S3 Access | Iceberg REST API |
|--------|------------------|------------------|
| **Credentials** | Long-lived, broad | Short-lived, scoped |
| **Permissions** | Bucket-level | Table/column-level |
| **Audit** | CloudTrail only | Full data lineage |
| **Revocation** | Manual, slow | Immediate |
| **Compliance** | Complex | Built-in |
| **Setup** | Simple | More complex |
| **Security** | ❌ Poor | ✅ Excellent |

---

## 4. S3 Tables: The Game Changer 🚀

### What are S3 Tables?

AWS S3 Tables is a **managed service** that:
- Automatically handles Iceberg table maintenance
- Provides optimized storage and query performance
- Eliminates operational overhead
- Integrates seamlessly with AWS analytics services

### Key Features

#### Automatic Maintenance
```yaml
Maintenance Tasks (Automated):
  - Compaction: ✅ Automatic
  - Snapshot cleanup: ✅ Automatic  
  - Orphan file removal: ✅ Automatic
  - Partition optimization: ✅ Automatic
```

#### Performance Optimizations
- **Automatic Z-ordering** for better compression
- **Intelligent partitioning** based on query patterns
- **Columnar storage** optimizations
- **Metadata caching** for faster queries

---

### S3 Tables Options & Pricing

#### Table Types
1. **General Purpose Tables**
   - Standard Iceberg format
   - Full compatibility
   - $0.10 per GB/month

2. **Optimized Tables**
   - Enhanced performance features
   - Automatic optimizations
   - $0.15 per GB/month

#### Additional Costs
- **Request charges**: $0.0004 per 1,000 requests
- **Data transfer**: Standard S3 rates
- **Compute**: Pay only for query processing

#### Cost Comparison
```
Traditional Snowflake: $2-5 per credit hour + storage
S3 Tables: $0.10-0.15 per GB/month + minimal compute
```

**Potential savings: 60-80% for storage-heavy workloads**

---

## 5. Snowflake's Evolution ❄️

### Traditional Snowflake Architecture

#### Micro-Partitions
```
Snowflake Internal Storage:
├── Micro-partition 1 (16MB compressed)
├── Micro-partition 2 (16MB compressed)  
├── Micro-partition 3 (16MB compressed)
└── ...
```

**Benefits:**
- Automatic clustering
- Efficient pruning
- Optimized compression

**Drawbacks:**
- Proprietary format
- Vendor lock-in
- High storage costs

---

### The New Snowflake: External Tables

#### Connecting to S3
```sql
-- Create external table pointing to S3
CREATE OR REPLACE EXTERNAL TABLE ext_user_events
WITH LOCATION = @s3_stage
FILE_FORMAT = (TYPE = PARQUET)
AUTO_REFRESH = TRUE;
```

#### Iceberg Catalog Integration
```sql
-- Connect to external Iceberg catalog
CREATE CATALOG iceberg_catalog
CATALOG_SOURCE = 'GLUE'
TABLE_FORMAT = 'ICEBERG';

-- Query Iceberg tables directly
SELECT * FROM iceberg_catalog.db.user_events;
```

---

### Snowflake + Iceberg Integration Deep Dive

#### External Tables with Standard Tables
```sql
-- External Iceberg table
CREATE EXTERNAL TABLE ext_user_events
USING TEMPLATE (
  SELECT ARRAY_AGG(OBJECT_CONSTRUCT(*))
  FROM TABLE(INFER_SCHEMA(
    LOCATION=>'@iceberg_stage/user_events/',
    FILE_FORMAT=>'iceberg_format'
  ))
);

-- Standard Snowflake table  
CREATE TABLE std_user_profiles (
  user_id NUMBER,
  name STRING,
  email STRING,
  created_at TIMESTAMP
);

-- Join external and standard tables
SELECT 
  e.user_id,
  e.event_type,
  p.name,
  p.email
FROM ext_user_events e
JOIN std_user_profiles p ON e.user_id = p.user_id
WHERE e.timestamp >= CURRENT_DATE - 7;
```

#### Views and Materialized Views
```sql
-- Create view combining external and standard tables
CREATE VIEW user_activity_summary AS
SELECT 
  p.user_id,
  p.name,
  COUNT(e.event_type) as total_events,
  COUNT(DISTINCT e.event_type) as unique_event_types,
  MAX(e.timestamp) as last_activity
FROM std_user_profiles p
LEFT JOIN ext_user_events e ON p.user_id = e.user_id
GROUP BY p.user_id, p.name;

-- Materialized view for performance
CREATE MATERIALIZED VIEW mv_daily_user_stats AS
SELECT 
  DATE(e.timestamp) as event_date,
  e.user_id,
  COUNT(*) as event_count,
  COUNT(DISTINCT e.event_type) as unique_events
FROM ext_user_events e
GROUP BY DATE(e.timestamp), e.user_id;
```

#### Dynamic Tables (Real-time Updates)
```sql
-- Dynamic table that auto-refreshes
CREATE DYNAMIC TABLE dt_user_engagement
TARGET_LAG = '1 hour'
WAREHOUSE = compute_wh
AS
SELECT 
  user_id,
  DATE(timestamp) as activity_date,
  COUNT(*) as events_count,
  ARRAY_AGG(DISTINCT event_type) as event_types,
  MAX(timestamp) as last_seen
FROM ext_user_events
WHERE timestamp >= CURRENT_DATE - 30
GROUP BY user_id, DATE(timestamp);
```

#### Permissions and Security
```sql
-- Grant permissions on external tables
GRANT SELECT ON ext_user_events TO ROLE data_analyst;
GRANT SELECT ON ext_user_events TO ROLE data_scientist;

-- Row-level security on external tables
CREATE ROW ACCESS POLICY user_region_policy AS (region) RETURNS BOOLEAN ->
  CURRENT_ROLE() = 'ADMIN' OR 
  region = CURRENT_USER_REGION();

-- Apply policy to external table
ALTER TABLE ext_user_events 
ADD ROW ACCESS POLICY user_region_policy ON (region);

-- Column masking on external tables
CREATE MASKING POLICY email_mask AS (val STRING) RETURNS STRING ->
  CASE 
    WHEN CURRENT_ROLE() IN ('ADMIN', 'PII_READER') THEN val
    ELSE REGEXP_REPLACE(val, '.+@', '*****@')
  END;

ALTER TABLE ext_user_events 
MODIFY COLUMN email SET MASKING POLICY email_mask;
```

---

### Performance: Standard vs Iceberg Tables

#### Query Performance Comparison

| Aspect | Standard Tables | External Iceberg |
|--------|----------------|------------------|
| **Metadata Access** | ✅ Instant | ⚠️ S3 API calls |
| **Clustering** | ✅ Automatic | ⚠️ Manual/limited |
| **Pruning** | ✅ Micro-partitions | ✅ Iceberg manifests |
| **Caching** | ✅ Result cache | ❌ Limited caching |
| **Compression** | ✅ Optimized | ⚠️ Standard Parquet |
| **Statistics** | ✅ Automatic | ⚠️ Manifest-based |

#### Real Performance Numbers
```sql
-- Standard table query (1TB data)
SELECT COUNT(*) FROM std_user_events 
WHERE timestamp >= '2024-01-01';
-- Execution time: 2.3 seconds
-- Credits consumed: 0.1

-- External Iceberg table query (1TB data)  
SELECT COUNT(*) FROM ext_user_events
WHERE timestamp >= '2024-01-01';
-- Execution time: 4.7 seconds  
-- Credits consumed: 0.15
-- Additional: S3 API costs
```

#### When to Use Each

**Use Standard Tables When:**
- High query frequency (>100 queries/day)
- Complex analytics requiring clustering
- Need sub-second response times
- Heavy use of Snowflake-specific features

**Use External Iceberg When:**
- Large datasets with infrequent access
- Multi-engine data sharing required
- Cost optimization is priority
- Data sovereignty requirements

#### Hybrid Architecture Benefits
```sql
-- Hot data in standard tables (last 30 days)
CREATE TABLE hot_user_events AS
SELECT * FROM ext_user_events 
WHERE timestamp >= CURRENT_DATE - 30;

-- Union view for complete data access
CREATE VIEW complete_user_events AS
SELECT * FROM hot_user_events
UNION ALL
SELECT * FROM ext_user_events 
WHERE timestamp < CURRENT_DATE - 30;
```

---

### External Iceberg Catalog Benefits

#### 1. Multi-Engine Access
```
Same Data, Multiple Engines:
S3 Tables (Iceberg) ←→ AWS Glue Catalog
    ↓
├── Snowflake (SQL)
├── Spark (Processing)  
├── Athena (Ad-hoc queries)
└── Redshift (Analytics)
```

#### 2. Cost Optimization
- **Storage**: Pay S3 rates, not Snowflake rates
- **Compute**: Use Snowflake only when needed
- **Flexibility**: Choose the right tool for each job

#### 3. Data Governance
- **Single source of truth** in the catalog
- **Consistent metadata** across all engines
- **Unified access controls**

---

## 6. The Integration Strategy 🔄

### Architecture Overview

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Data Sources  │───▶│   S3 Tables      │───▶│   Snowflake     │
│                 │    │   (Iceberg)      │    │   (External)    │
├─────────────────┤    ├──────────────────┤    ├─────────────────┤
│ • Streaming     │    │ • Auto-maintain  │    │ • Query engine  │
│ • Batch         │    │ • ACID           │    │ • Analytics     │
│ • APIs          │    │ • Schema evolve  │    │ • Reporting     │
└─────────────────┘    └──────────────────┘    └─────────────────┘
                              │
                              ▼
                       ┌──────────────────┐
                       │  AWS Glue        │
                       │  Catalog         │
                       └──────────────────┘
```

### Implementation Steps

#### Step 1: Set Up S3 Tables
```sql
-- Create S3 table with Iceberg format
CREATE TABLE s3_tables.analytics.user_events (
    user_id BIGINT,
    event_type STRING,
    timestamp TIMESTAMP,
    properties MAP<STRING, STRING>
)
USING ICEBERG
LOCATION 's3://my-bucket/tables/user_events/';
```

#### Step 2: Configure Snowflake External Catalog
```sql
-- Create external catalog connection
CREATE CATALOG my_iceberg_catalog
CATALOG_SOURCE = 'GLUE'
CATALOG_NAMESPACE = 'analytics'
TABLE_FORMAT = 'ICEBERG';
```

#### Step 3: Query Across Platforms
```sql
-- In Snowflake
SELECT 
    event_type,
    COUNT(*) as event_count
FROM my_iceberg_catalog.analytics.user_events
WHERE timestamp >= CURRENT_DATE - 7
GROUP BY event_type;
```

---

### Cost Benefits in Practice

#### Before: Pure Snowflake
```
Monthly Costs:
- Storage (1TB): $40/month
- Compute (100 hours): $200/month  
- Total: $240/month
```

#### After: S3 Tables + Snowflake
```
Monthly Costs:
- S3 Tables storage (1TB): $100/month
- Snowflake compute (50 hours): $100/month
- Total: $200/month
- Savings: 17% + increased flexibility
```

**For larger datasets (10TB+), savings can reach 50-70%**

---

### Integration Benefits Summary

#### 1. **Cost Reduction**
- Lower storage costs with S3 Tables
- Reduced compute usage in Snowflake
- Pay-per-use model flexibility

#### 2. **Operational Simplicity**
- Automated maintenance with S3 Tables
- No manual Iceberg operations
- Unified catalog management

#### 3. **Multi-Engine Flexibility**
- Use Snowflake for complex analytics
- Use Spark for large-scale processing
- Use Athena for ad-hoc queries

#### 4. **Future-Proofing**
- Open format prevents vendor lock-in
- Easy migration between platforms
- Standards-based approach

---

## Key Takeaways 🎯

1. **Snowflake doesn't have to be expensive** when used strategically
2. **Iceberg provides ACID guarantees** that raw Parquet can't
3. **S3 Tables eliminates maintenance overhead** of managing Iceberg
4. **External catalogs unlock multi-engine architectures**
5. **The combination offers the best of all worlds**: performance, cost-efficiency, and flexibility

---

## Questions? 🤔

### Contact Information
- **Email**: [your-email]
- **LinkedIn**: [your-linkedin]
- **GitHub**: [your-github]

### Resources
- [AWS S3 Tables Documentation](https://docs.aws.amazon.com/s3/latest/userguide/s3-tables.html)
- [Apache Iceberg Documentation](https://iceberg.apache.org/)
- [Snowflake External Tables Guide](https://docs.snowflake.com/en/user-guide/tables-external)

---

**Thank you!** 🙏

*Building the future of data platforms, one table at a time.*