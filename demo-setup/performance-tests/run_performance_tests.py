#!/usr/bin/env python3
"""
Automated performance testing script for Snowflake Iceberg demo
Runs performance tests and collects metrics
"""

import snowflake.connector
import pandas as pd
import time
import json
import argparse
from datetime import datetime
from typing import Dict, List, Tuple
import os

class SnowflakePerformanceTester:
    def __init__(self, account: str, username: str, password: str, 
                 warehouse: str = "ICEBERG_DEMO_WH", 
                 database: str = "ICEBERG_DEMO", 
                 schema: str = "ANALYTICS"):
        self.conn = snowflake.connector.connect(
            account=account,
            user=username,
            password=password,
            warehouse=warehouse,
            database=database,
            schema=schema
        )
        self.cursor = self.conn.cursor()
        self.results = []
        
    def execute_timed_query(self, query: str, test_name: str) -> Dict:
        """Execute a query and measure performance metrics"""
        print(f"Running test: {test_name}")
        
        start_time = time.time()
        start_timestamp = datetime.now()
        
        try:
            self.cursor.execute(query)
            results = self.cursor.fetchall()
            
            end_time = time.time()
            end_timestamp = datetime.now()
            
            # Get query ID for detailed metrics
            query_id = self.cursor.sfqid
            
            # Collect additional metrics
            metrics = self._get_query_metrics(query_id)
            
            result = {
                'test_name': test_name,
                'query': query,
                'start_time': start_timestamp.isoformat(),
                'end_time': end_timestamp.isoformat(),
                'execution_time_seconds': round(end_time - start_time, 3),
                'row_count': len(results),
                'query_id': query_id,
                'status': 'SUCCESS',
                **metrics
            }
            
            print(f"  ✅ Completed in {result['execution_time_seconds']}s")
            return result
            
        except Exception as e:
            end_time = time.time()
            result = {
                'test_name': test_name,
                'query': query,
                'start_time': start_timestamp.isoformat(),
                'end_time': datetime.now().isoformat(),
                'execution_time_seconds': round(end_time - start_time, 3),
                'row_count': 0,
                'query_id': None,
                'status': 'ERROR',
                'error': str(e)
            }
            print(f"  ❌ Failed: {str(e)}")
            return result
    
    def _get_query_metrics(self, query_id: str) -> Dict:
        """Get detailed metrics for a query"""
        try:
            metrics_query = f"""
            SELECT 
                total_elapsed_time,
                bytes_scanned,
                bytes_written,
                bytes_deleted,
                credits_used_cloud_services,
                warehouse_size,
                compilation_time,
                execution_time,
                queued_provisioning_time,
                queued_repair_time,
                queued_overload_time
            FROM snowflake.account_usage.query_history 
            WHERE query_id = '{query_id}'
            """
            
            self.cursor.execute(metrics_query)
            result = self.cursor.fetchone()
            
            if result:
                return {
                    'total_elapsed_time_ms': result[0],
                    'bytes_scanned': result[1],
                    'bytes_written': result[2],
                    'bytes_deleted': result[3],
                    'credits_used': result[4],
                    'warehouse_size': result[5],
                    'compilation_time_ms': result[6],
                    'execution_time_ms': result[7],
                    'queued_provisioning_ms': result[8],
                    'queued_repair_ms': result[9],
                    'queued_overload_ms': result[10]
                }
        except:
            pass
        
        return {}
    
    def run_basic_performance_tests(self):
        """Run basic performance comparison tests"""
        
        tests = [
            {
                'name': 'External Iceberg - Count All Events',
                'query': 'SELECT COUNT(*) as total_events FROM ext_user_events'
            },
            {
                'name': 'Standard Table - Count All Users',
                'query': 'SELECT COUNT(*) as total_users FROM user_profiles'
            },
            {
                'name': 'External Iceberg - Last 7 Days Filter',
                'query': '''
                SELECT 
                    COUNT(*) as events_last_7_days,
                    COUNT(DISTINCT user_id) as unique_users,
                    COUNT(DISTINCT event_type) as unique_events
                FROM ext_user_events 
                WHERE timestamp >= CURRENT_DATE - 7
                '''
            },
            {
                'name': 'Standard Table - Last 7 Days Filter',
                'query': '''
                SELECT 
                    COUNT(*) as users_last_7_days,
                    COUNT(DISTINCT region) as unique_regions
                FROM user_profiles 
                WHERE created_at >= CURRENT_DATE - 7
                '''
            },
            {
                'name': 'Join External + Standard Tables',
                'query': '''
                SELECT 
                    p.region,
                    COUNT(DISTINCT p.user_id) as total_users,
                    COUNT(e.event_type) as total_events,
                    COUNT(DISTINCT e.event_type) as unique_events
                FROM user_profiles p
                LEFT JOIN ext_user_events e ON p.user_id = e.user_id
                WHERE e.timestamp >= CURRENT_DATE - 7
                GROUP BY p.region
                ORDER BY total_events DESC
                '''
            }
        ]
        
        for test in tests:
            result = self.execute_timed_query(test['query'], test['name'])
            self.results.append(result)
    
    def run_advanced_performance_tests(self):
        """Run advanced performance tests"""
        
        tests = [
            {
                'name': 'Aggregation by Event Type',
                'query': '''
                SELECT 
                    event_type,
                    COUNT(*) as event_count,
                    COUNT(DISTINCT user_id) as unique_users,
                    MIN(timestamp) as first_event,
                    MAX(timestamp) as last_event
                FROM ext_user_events
                GROUP BY event_type
                ORDER BY event_count DESC
                '''
            },
            {
                'name': 'Window Functions - User Event Sequence',
                'query': '''
                SELECT 
                    user_id,
                    event_type,
                    timestamp,
                    ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY timestamp DESC) as event_rank,
                    LAG(event_type) OVER (PARTITION BY user_id ORDER BY timestamp) as prev_event
                FROM ext_user_events
                WHERE timestamp >= CURRENT_DATE - 3
                QUALIFY event_rank <= 10
                LIMIT 1000
                '''
            },
            {
                'name': 'Complex Analytics - Purchase Funnel',
                'query': '''
                WITH user_events AS (
                    SELECT 
                        user_id,
                        event_type,
                        timestamp,
                        ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY timestamp) as event_sequence
                    FROM ext_user_events
                    WHERE timestamp >= CURRENT_DATE - 14
                ),
                funnel_analysis AS (
                    SELECT 
                        user_id,
                        MAX(CASE WHEN event_type = 'page_view' THEN 1 ELSE 0 END) as has_page_view,
                        MAX(CASE WHEN event_type = 'add_to_cart' THEN 1 ELSE 0 END) as has_add_to_cart,
                        MAX(CASE WHEN event_type = 'checkout' THEN 1 ELSE 0 END) as has_checkout,
                        MAX(CASE WHEN event_type = 'purchase' THEN 1 ELSE 0 END) as has_purchase
                    FROM user_events
                    GROUP BY user_id
                )
                SELECT 
                    SUM(has_page_view) as page_views,
                    SUM(has_add_to_cart) as add_to_carts,
                    SUM(has_checkout) as checkouts,
                    SUM(has_purchase) as purchases,
                    ROUND(SUM(has_add_to_cart) / SUM(has_page_view) * 100, 2) as page_to_cart_rate,
                    ROUND(SUM(has_purchase) / SUM(has_checkout) * 100, 2) as checkout_to_purchase_rate
                FROM funnel_analysis
                '''
            }
        ]
        
        for test in tests:
            result = self.execute_timed_query(test['query'], test['name'])
            self.results.append(result)
    
    def run_maintenance_analysis(self):
        """Analyze maintenance requirements"""
        
        # Simulate file count analysis
        file_analysis_query = '''
        WITH daily_stats AS (
            SELECT 
                DATE(timestamp) as partition_date,
                COUNT(*) as record_count,
                COUNT(DISTINCT user_id) as unique_users,
                -- Simulate file count estimation
                CEIL(COUNT(*) / 1000.0) as estimated_small_files,
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
            CASE 
                WHEN estimated_small_files > 0 
                THEN ROUND((estimated_small_files - optimal_files) / estimated_small_files * 100, 2)
                ELSE 0 
            END as compaction_savings_pct
        FROM daily_stats
        WHERE estimated_small_files > optimal_files
        ORDER BY partition_date DESC
        LIMIT 10
        '''
        
        result = self.execute_timed_query(file_analysis_query, 'Maintenance Analysis - File Compaction')
        self.results.append(result)
    
    def generate_report(self, output_file: str = None):
        """Generate performance test report"""
        if not output_file:
            output_file = f"performance_report_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
        
        report = {
            'test_run_timestamp': datetime.now().isoformat(),
            'total_tests': len(self.results),
            'successful_tests': len([r for r in self.results if r['status'] == 'SUCCESS']),
            'failed_tests': len([r for r in self.results if r['status'] == 'ERROR']),
            'results': self.results
        }
        
        # Save detailed results
        with open(output_file, 'w') as f:
            json.dump(report, f, indent=2)
        
        # Generate summary
        print("\n" + "="*80)
        print("PERFORMANCE TEST SUMMARY")
        print("="*80)
        
        successful_results = [r for r in self.results if r['status'] == 'SUCCESS']
        
        if successful_results:
            print(f"\nTest Results ({len(successful_results)} successful tests):")
            print("-" * 80)
            
            for result in successful_results:
                print(f"{result['test_name']:<50} {result['execution_time_seconds']:>8.3f}s")
                if 'bytes_scanned' in result and result['bytes_scanned']:
                    mb_scanned = result['bytes_scanned'] / (1024 * 1024)
                    print(f"{'':>50} {mb_scanned:>8.1f} MB scanned")
        
        failed_results = [r for r in self.results if r['status'] == 'ERROR']
        if failed_results:
            print(f"\nFailed Tests ({len(failed_results)}):")
            print("-" * 80)
            for result in failed_results:
                print(f"{result['test_name']:<50} ERROR: {result.get('error', 'Unknown')}")
        
        print(f"\nDetailed results saved to: {output_file}")
        
        return report
    
    def close(self):
        """Close database connection"""
        self.cursor.close()
        self.conn.close()

def main():
    parser = argparse.ArgumentParser(description='Run Snowflake Iceberg performance tests')
    parser.add_argument('--account', required=True, help='Snowflake account')
    parser.add_argument('--username', required=True, help='Snowflake username')
    parser.add_argument('--password', required=True, help='Snowflake password')
    parser.add_argument('--warehouse', default='ICEBERG_DEMO_WH', help='Snowflake warehouse')
    parser.add_argument('--database', default='ICEBERG_DEMO', help='Snowflake database')
    parser.add_argument('--schema', default='ANALYTICS', help='Snowflake schema')
    parser.add_argument('--test-suite', choices=['basic', 'advanced', 'all'], default='all',
                       help='Which test suite to run')
    parser.add_argument('--output', help='Output file for results')
    
    args = parser.parse_args()
    
    # Initialize tester
    tester = SnowflakePerformanceTester(
        account=args.account,
        username=args.username,
        password=args.password,
        warehouse=args.warehouse,
        database=args.database,
        schema=args.schema
    )
    
    try:
        print("Starting Snowflake Iceberg Performance Tests")
        print("=" * 50)
        
        if args.test_suite in ['basic', 'all']:
            print("\nRunning basic performance tests...")
            tester.run_basic_performance_tests()
        
        if args.test_suite in ['advanced', 'all']:
            print("\nRunning advanced performance tests...")
            tester.run_advanced_performance_tests()
        
        if args.test_suite in ['all']:
            print("\nRunning maintenance analysis...")
            tester.run_maintenance_analysis()
        
        # Generate report
        report = tester.generate_report(args.output)
        
    finally:
        tester.close()

if __name__ == "__main__":
    main()