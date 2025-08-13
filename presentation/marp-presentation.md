---
marp: true
theme: default
class: lead
paginate: true
backgroundColor: #fff
backgroundImage: url('https://marp.app/assets/hero-background.svg')
style: |
  .columns {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 1rem;
  }
  .aws-orange { color: #FF9900; }
  .aws-blue { color: #232F3E; }
  .snowflake-blue { color: #29B5E8; }
  .highlight { background-color: #FFF3CD; padding: 0.2em 0.4em; border-radius: 3px; }
  .cost-savings { background-color: #D4EDDA; border: 1px solid #C3E6CB; border-radius: 5px; padding: 1em; margin: 1em 0; }
---

# Building a Scalable Data Platform
## with S3 Tables, Iceberg and Snowflake

**AWS Community Builders Day**
*Duration: 40 minutes + 10 minute demo*

---

<!-- _class: quote -->

> "Snowflake is expensive, everyone knows that. But what if I told you there's a way to keep the power while cutting the costs **AND** make your AWS data integration seamless?"

---

# Agenda

1. **The Integration Challenge** <span class="aws-orange">(5 min)</span>
2. **Apache Iceberg: The Foundation** <span class="aws-orange">(10 min)</span>
3. **S3 Tables: AWS Managed Iceberg** <span class="aws-orange">(8 min)</span>
4. **Snowflake Integration Strategy** <span class="aws-orange">(10 min)</span>
5. **Cost & Performance Analysis** <span class="aws-orange">(5 min)</span>
6. **The Open Ecosystem** <span class="aws-orange">(2 min)</span>
7. **Live Demo** <span class="aws-orange">(10 min)</span>

---

# 💰 1. The Integration Challenge

---

## The AWS + Snowflake Dilemma

<div class="columns">
<div>

### <span class="aws-orange">Your AWS Data Stack:</span>
- Kinesis streams → S3
- EMR/Glue jobs → S3  
- Lambda functions → S3
- RDS exports → S3

</div>
<div>

### <span class="snowflake-blue">Your Snowflake Reality:</span>
- Expensive data loading (COPY commands)
- Storage costs 3-5x higher than S3
- Data egress charges for multi-tool access
- Vendor lock-in limits AWS service integration

</div>
</div>

---

## The Traditional Trade-off

```
AWS Integration + Cost Efficiency  vs  Snowflake Performance + Ease
```

**What if you could have both?**

---

## Business Impact

<div class="cost-savings">

### For a typical 10TB data warehouse:
- Snowflake storage: **$400/month**
- S3 storage: **$230/month**  
- <span class="aws-orange">**Potential savings: $170/month = $2,040/year**</span>

</div>

### Plus operational benefits:
- Seamless AWS service integration
- Multi-engine data access
- Reduced vendor lock-in risk

---

# 🧊 2. Apache Iceberg: The Foundation

---

## Why Iceberg Matters for AWS + Snowflake

<div class="columns">
<div>

### The Problem with Raw Parquet on S3:
```
s3://bucket/data/
├── file1.parquet
├── file2.parquet  
├── file3.parquet
└── ...
```

- No ACID guarantees
- Manual partition management  
- Expensive full table scans
- No schema evolution

</div>
<div>

### Iceberg solves this with a metadata layer:
- **ACID transactions** on S3 data
- **Schema evolution** without data rewrites
- **Time travel** for point-in-time queries
- **Efficient query planning** with statistics

</div>
</div>

---

## Iceberg Architecture: Built for AWS

```
┌─────────────────┐
│  AWS Services   │
│ (Spark, Athena, │ ──┐
│  Glue, etc.)    │   │
└─────────────────┘   │
                      ▼
┌─────────────────┐   ┌─────────────────┐   ┌─────────────────┐
│   Catalog       │◄──┤   Metadata      │◄──┤     Data        │
│ (Glue/REST)     │   │ (JSON + Avro)   │   │   (Parquet)     │
└─────────────────┘   └─────────────────┘   └─────────────────┘
                              │                       │
                              ▼                       ▼
                      s3://bucket/metadata/    s3://bucket/data/
```

---

## The Maintenance Challenge

### What happens with streaming data:
```
Kinesis → Glue Job (every 5 min) → S3
Result: 288 files/day × 365 days = 105,120 files/year!
```

### Performance impact:
- Week 1: Query time 2 seconds
- Month 1: Query time 30 seconds  
- Month 6: Query time 5+ minutes

<span class="highlight">**Manual maintenance required:** File compaction, snapshot cleanup, orphan file removal</span>

---

# 🚀 3. S3 Tables: AWS Managed Iceberg

---

## The AWS Solution to Iceberg Maintenance

**S3 Tables = Iceberg + AWS Management**

<div class="cost-savings">

### What S3 Tables Handles Automatically:
- ✅ File compaction (small → large files)
- ✅ Snapshot cleanup (metadata management)  
- ✅ Orphan file removal (garbage collection)
- ✅ Query optimization (Z-ordering, statistics)
- ✅ Schema evolution (backward compatibility)

</div>

---

## Native AWS Service Integration

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Kinesis       │───▶│   S3 Tables      │◄───┤   Athena        │
│   Streams       │    │   (Managed       │    │   Queries       │
└─────────────────┘    │    Iceberg)      │    └─────────────────┘
                       └──────────────────┘
                              │    ▲
                              ▼    │
                       ┌──────────────────┐
                       │  Glue Catalog    │
                       │  (Metadata)      │
                       └──────────────────┘
```

---

## Cost-Effective Pricing

<div class="columns">
<div>

### S3 Tables Pricing:
- General Purpose: $0.10 per GB/month
- Optimized: $0.15 per GB/month
- Requests: $0.0004 per 1,000 operations

</div>
<div>

### Compare to Snowflake:
- Storage: $40 per TB/month <span class="highlight">(4x more expensive)</span>
- Plus compute costs for maintenance

</div>
</div>

---

# ❄️ 4. Snowflake Integration Strategy

---

## Setting Up the Integration

### Step 1: Create External Catalog in Snowflake
```sql
-- Connect Snowflake to AWS Glue Catalog
CREATE CATALOG iceberg_catalog
CATALOG_SOURCE = 'GLUE'
CATALOG_NAMESPACE = 'analytics'
TABLE_FORMAT = 'ICEBERG'
GLUE_AWS_ROLE_ARN = 'arn:aws:iam::123456789:role/SnowflakeRole';
```

---

## Hybrid Architecture (Recommended)

```sql
-- Hot data (recent): Snowflake internal tables
CREATE TABLE hot_user_events AS
SELECT * FROM iceberg_catalog.analytics.user_events 
WHERE timestamp >= CURRENT_DATE - 30;

-- Cold data (historical): S3 Tables external access
-- Unified view for complete data access
CREATE VIEW complete_user_events AS
SELECT * FROM hot_user_events
UNION ALL
SELECT * FROM iceberg_catalog.analytics.user_events 
WHERE timestamp < CURRENT_DATE - 30;
```

---

# 📊 5. Cost & Performance Analysis

---

## Real-World Cost Comparison

### Scenario: 100TB Data Warehouse

<div class="columns">
<div>

### Traditional Snowflake:
- Storage: $4,000/month
- Compute: $800/month  
- **Total: $4,800/month**

</div>
<div>

### S3 Tables + Snowflake Hybrid:
- S3 Tables (80TB): $800/month
- Snowflake (20TB): $800/month
- Reduced compute: $400/month
- **Total: $2,000/month**

</div>
</div>

<div class="cost-savings">

### <span class="aws-orange">Savings: $2,800/month = $33,600/year</span>

</div>

---

## The Sweet Spot: Hybrid Architecture

### Recommended Data Tiering Strategy

- **Tier 1: Hot data (last 30 days)** - Snowflake internal
- **Tier 2: Warm data (30-365 days)** - S3 Tables external  
- **Tier 3: Cold data (>1 year)** - S3 Tables external

### Results:
- 90% of queries hit hot data (fast performance)
- 10% of queries hit cold data (acceptable performance)  
- Storage costs reduced by 60%
- **Overall savings: 45% with minimal performance impact**

---

# 🌐 6. The Open Ecosystem

---

## Iceberg REST API: Universal Data Access

**The game-changer:** Iceberg REST API is an **open protocol** that works with any engine

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   DuckDB        │    │   Databricks     │    │   Snowflake     │
│   (Local)       │    │   (Spark)        │    │   (Cloud)       │
└─────────────────┘    └──────────────────┘    └─────────────────┘
         │                       │                       │
         └───────────────────────┼───────────────────────┘
                                 ▼
                    ┌──────────────────────┐
                    │  Iceberg REST API    │
                    │  (Universal Access)  │
                    └──────────────────────┘
```

---

## The Strategic Advantage

### 1. **No Vendor Lock-in**
- Open format works with any engine
- Easy migration between platforms
- Future-proof architecture

### 2. **Best Tool for Each Job**
- **Ingestion:** AWS Kinesis → S3 Tables
- **Processing:** Databricks Spark (large-scale)
- **Analytics:** Snowflake (complex SQL)
- **Exploration:** DuckDB (local analysis)

---

# 🎬 7. Live Demo

---

## Demo Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│  Sample Data    │───▶│   S3 Tables      │───▶│   Snowflake     │
│  Generator      │    │   (Iceberg)      │    │   Queries       │
└─────────────────┘    └──────────────────┘    └─────────────────┘
                              │
                              ▼
                       ┌──────────────────┐
                       │  Performance     │
                       │  Comparison      │
                       └──────────────────┘
```

---

## What We'll Demonstrate

1. **Small File Problem** (2 min)
   - Show 1,000+ small files from streaming data

2. **S3 Tables Auto-Compaction** (3 min)
   - Automatic file consolidation

3. **Snowflake Integration** (3 min)
   - External catalog setup

4. **Cost Analysis** (2 min)
   - Real cost comparison

---

# 🎯 Key Takeaways

---

## For Engineers & Managers

<div class="columns">
<div>

### Engineers:
1. **S3 Tables eliminates Iceberg maintenance overhead**
2. **Hybrid architecture optimizes cost vs performance**
3. **Open standards prevent vendor lock-in**
4. **AWS-native integration simplifies pipelines**

</div>
<div>

### Managers:
1. **Significant cost savings at scale** - 45% reduction
2. **Reduced operational overhead** - $32K/year savings
3. **Future-proof architecture**
4. **Faster time-to-market**

</div>
</div>

---

## The Bottom Line

```
Traditional Approach: High cost + Vendor lock-in
Our Approach: Lower cost + Flexibility + Performance
```

---

# Thank you! 🙏

*Building cost-effective, flexible data platforms with AWS and Snowflake*

## Questions? 🤔

**Email:** [your-email]
**LinkedIn:** [your-linkedin]  
**GitHub:** [your-github]