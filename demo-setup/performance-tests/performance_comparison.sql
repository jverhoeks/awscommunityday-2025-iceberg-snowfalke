-- Performance Comparison: Standard vs External Iceberg Tables
-- Run these queries in Snowflake to compare performance

-- Set up the session
USE WAREHOUSE ICEBERG_DEMO_WH;
USE DATABASE ICEBERG_DEMO;
USE SCHEMA ANALYTICS;

-- ============================================================================
-- SETUP: Create External Iceberg Table
-- ============================================================================

-- Create external table pointing to Iceberg data
CREATE OR REPLACE EXTERNAL TABLE ext_user_events
USING TEMPLATE (
  SELECT ARRAY_AGG(OBJECT_CONSTRUCT(*))
  FROM TABLE(INFER_SCHEMA(
    LOCATION=>'@ICEBERG_STAGE/user_events/',
    FILE_FORMAT=>(TYPE=PARQUET)
  ))
);

-- Create views and materialized views for testing
CREATE OR REPLACE VIEW user_activity_summary AS
SELECT 
  p.user_id,
  p.name,
  p.region,
  COUNT(e.event_type) as total_events,
  COUNT(DISTINCT e.event_type) as unique_event_types,
  MAX(e.timestamp) as last_activity
FROM user_profiles p
LEFT JOIN ext_user_events e ON p.user_id = e.user_id
GROUP BY p.user_id, p.name, p.region;

-- Create materialized view for performance comparison
CREATE OR REPLACE MATERIALIZED VIEW mv_daily_user_stats AS
SELECT 
  DATE(e.timestamp) as event_date,
  e.user_id,
  e.region,
  COUNT(*) as event_count,
  COUNT(DISTINCT e.event_type) as unique_events,
  SUM(CASE WHEN e.event_type = 'purchase' THEN 1 ELSE 0 END) as purchases
FROM ext_user_events e
GROUP BY DATE(e.timestamp), e.user_id, e.region;

-- ============================================================================
-- PERFORMANCE TEST 1: Simple Aggregation
-- ============================================================================

-- Test 1a: Count all events (External Iceberg)
SELECT 'External Iceberg - Count All' as test_name, CURRENT_TIMESTAMP() as start_time;
SELECT COUNT(*) as total_events FROM ext_user_events;
SELECT CURRENT_TIMESTAMP() as end_time;

-- Test 1b: Count all events (Standard table - simulate with user_profiles)
SELECT 'Standard Table - Count All' as test_name, CURRENT_TIMESTAMP() as start_time;
SELECT COUNT(*) as total_users FROM user_profiles;
SELECT CURRENT_TIMESTAMP() as end_time;

-- ============================================================================
-- PERFORMANCE TEST 2: Filtered Aggregation
-- ============================================================================

-- Test 2a: Events in last 7 days (External Iceberg)
SELECT 'External Iceberg - Last 7 Days' as test_name, CURRENT_TIMESTAMP() as start_time;
SELECT 
  COUNT(*) as events_last_7_days,
  COUNT(DISTINCT user_id) as unique_users,
  COUNT(DISTINCT event_type) as unique_events
FROM ext_user_events 
WHERE timestamp >= CURRENT_DATE - 7;
SELECT CURRENT_TIMESTAMP() as end_time;

-- Test 2b: Users created in last 7 days (Standard table)
SELECT 'Standard Table - Last 7 Days' as test_name, CURRENT_TIMESTAMP() as start_time;
SELECT 
  COUNT(*) as users_last_7_days,
  COUNT(DISTINCT region) as unique_regions
FROM user_profiles 
WHERE created_at >= CURRENT_DATE - 7;
SELECT CURRENT_TIMESTAMP() as end_time;

-- ============================================================================
-- PERFORMANCE TEST 3: Complex Joins
-- ============================================================================

-- Test 3a: Join external and standard tables
SELECT 'Join External + Standard' as test_name, CURRENT_TIMESTAMP() as start_time;
SELECT 
  p.region,
  COUNT(DISTINCT p.user_id) as total_users,
  COUNT(e.event_type) as total_events,
  COUNT(DISTINCT e.event_type) as unique_events,
  AVG(CASE WHEN e.event_type = 'purchase' THEN 1 ELSE 0 END) as purchase_rate
FROM user_profiles p
LEFT JOIN ext_user_events e ON p.user_id = e.user_id
WHERE e.timestamp >= CURRENT_DATE - 30
GROUP BY p.region
ORDER BY total_events DESC;
SELECT CURRENT_TIMESTAMP() as end_time;

-- ============================================================================
-- PERFORMANCE TEST 4: Materialized View Performance
-- ============================================================================

-- Test 4a: Query materialized view
SELECT 'Materialized View Query' as test_name, CURRENT_TIMESTAMP() as start_time;
SELECT 
  event_date,
  region,
  SUM(event_count) as total_events,
  SUM(purchases) as total_purchases,
  COUNT(DISTINCT user_id) as unique_users
FROM mv_daily_user_stats
WHERE event_date >= CURRENT_DATE - 14
GROUP BY event_date, region
ORDER BY event_date DESC, total_events DESC;
SELECT CURRENT_TIMESTAMP() as end_time;

-- ============================================================================
-- PERFORMANCE TEST 5: Time Travel (Iceberg Feature)
-- ============================================================================

-- Test 5a: Query data as it was 1 day ago (if supported)
SELECT 'Time Travel - 1 Day Ago' as test_name, CURRENT_TIMESTAMP() as start_time;
-- Note: Time travel syntax may vary based on Snowflake's Iceberg implementation
SELECT COUNT(*) as events_yesterday
FROM ext_user_events AT(TIMESTAMP => CURRENT_TIMESTAMP() - INTERVAL '1 DAY');
SELECT CURRENT_TIMESTAMP() as end_time;

-- ============================================================================
-- PERFORMANCE TEST 6: Large Scan vs Partition Pruning
-- ============================================================================

-- Test 6a: Full table scan
SELECT 'Full Table Scan' as test_name, CURRENT_TIMESTAMP() as start_time;
SELECT 
  event_type,
  COUNT(*) as event_count
FROM ext_user_events
GROUP BY event_type
ORDER BY event_count DESC;
SELECT CURRENT_TIMESTAMP() as end_time;

-- Test 6b: Partition pruned query (by date)
SELECT 'Partition Pruned Query' as test_name, CURRENT_TIMESTAMP() as start_time;
SELECT 
  event_type,
  COUNT(*) as event_count
FROM ext_user_events
WHERE timestamp >= CURRENT_DATE - 1
GROUP BY event_type
ORDER BY event_count DESC;
SELECT CURRENT_TIMESTAMP() as end_time;

-- ============================================================================
-- PERFORMANCE TEST 7: Window Functions
-- ============================================================================

-- Test 7a: Window functions on external table
SELECT 'Window Functions - External' as test_name, CURRENT_TIMESTAMP() as start_time;
SELECT 
  user_id,
  event_type,
  timestamp,
  ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY timestamp DESC) as event_rank,
  LAG(event_type) OVER (PARTITION BY user_id ORDER BY timestamp) as prev_event
FROM ext_user_events
WHERE timestamp >= CURRENT_DATE - 7
QUALIFY event_rank <= 5;
SELECT CURRENT_TIMESTAMP() as end_time;

-- ============================================================================
-- COST ANALYSIS QUERIES
-- ============================================================================

-- Query to check warehouse usage and costs
SELECT 'Warehouse Usage Analysis' as analysis_type;
SELECT 
  query_type,
  warehouse_name,
  COUNT(*) as query_count,
  SUM(total_elapsed_time) / 1000 as total_seconds,
  SUM(credits_used_cloud_services) as cloud_service_credits,
  AVG(bytes_scanned) as avg_bytes_scanned
FROM snowflake.account_usage.query_history
WHERE start_time >= CURRENT_DATE - 1
  AND warehouse_name = 'ICEBERG_DEMO_WH'
GROUP BY query_type, warehouse_name
ORDER BY total_seconds DESC;

-- Storage usage comparison
SELECT 'Storage Usage Analysis' as analysis_type;
SELECT 
  table_name,
  table_type,
  bytes as storage_bytes,
  bytes / (1024*1024*1024) as storage_gb,
  row_count
FROM snowflake.account_usage.table_storage_metrics
WHERE table_schema = 'ANALYTICS'
  AND table_catalog = 'ICEBERG_DEMO'
ORDER BY storage_bytes DESC;

-- ============================================================================
-- MAINTENANCE SIMULATION (for comparison)
-- ============================================================================

-- Show file count in external table (to demonstrate small file problem)
SELECT 'File Count Analysis' as analysis_type;
-- This would typically be done via S3 API or Glue catalog
-- In Snowflake, we can approximate by looking at metadata

-- Simulate compaction benefit calculation
SELECT 'Compaction Benefit Simulation' as analysis_type;
WITH file_stats AS (
  SELECT 
    DATE(timestamp) as partition_date,
    COUNT(*) as record_count,
    -- Simulate file count (assuming 1000 records per small file)
    CEIL(COUNT(*) / 1000.0) as estimated_small_files,
    -- Optimal file count (assuming 100MB files with ~50K records each)
    CEIL(COUNT(*) / 50000.0) as optimal_files
  FROM ext_user_events
  GROUP BY DATE(timestamp)
)
SELECT 
  partition_date,
  record_count,
  estimated_small_files,
  optimal_files,
  estimated_small_files - optimal_files as files_to_compact,
  ROUND((estimated_small_files - optimal_files) / estimated_small_files * 100, 2) as compaction_savings_pct
FROM file_stats
WHERE estimated_small_files > optimal_files
ORDER BY partition_date DESC
LIMIT 10;