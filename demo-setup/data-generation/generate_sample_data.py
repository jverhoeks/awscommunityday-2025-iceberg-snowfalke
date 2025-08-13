#!/usr/bin/env python3
"""
Generate sample data for Iceberg demo
Creates both streaming-like small files and batch-like large files
"""

import boto3
import pandas as pd
import pyarrow as pa
import pyarrow.parquet as pq
from datetime import datetime, timedelta
import random
import uuid
import json
import os
from typing import List, Dict

class IcebergDataGenerator:
    def __init__(self, bucket_name: str, table_path: str = "demo_analytics/user_events"):
        self.s3_client = boto3.client('s3')
        self.bucket_name = bucket_name
        self.table_path = table_path
        self.regions = ['us-west-2', 'us-east-1', 'eu-west-1', 'ap-southeast-1']
        self.event_types = [
            'page_view', 'click', 'purchase', 'signup', 'login', 
            'logout', 'search', 'add_to_cart', 'checkout', 'download'
        ]
        
    def generate_user_events(self, num_records: int, start_date: datetime) -> pd.DataFrame:
        """Generate sample user events data"""
        data = []
        
        for i in range(num_records):
            # Generate timestamp within the day
            timestamp = start_date + timedelta(
                hours=random.randint(0, 23),
                minutes=random.randint(0, 59),
                seconds=random.randint(0, 59)
            )
            
            # Generate properties based on event type
            event_type = random.choice(self.event_types)
            properties = self._generate_properties(event_type)
            
            record = {
                'user_id': random.randint(1, 100000),
                'event_type': event_type,
                'timestamp': timestamp,
                'properties': properties,
                'region': random.choice(self.regions)
            }
            data.append(record)
        
        return pd.DataFrame(data)
    
    def _generate_properties(self, event_type: str) -> Dict[str, str]:
        """Generate realistic properties based on event type"""
        base_props = {
            'session_id': str(uuid.uuid4())[:8],
            'user_agent': random.choice(['Chrome', 'Firefox', 'Safari', 'Edge']),
            'platform': random.choice(['web', 'mobile', 'tablet'])
        }
        
        if event_type == 'purchase':
            base_props.update({
                'product_id': f"prod_{random.randint(1, 1000)}",
                'amount': str(round(random.uniform(10, 500), 2)),
                'currency': 'USD'
            })
        elif event_type == 'page_view':
            base_props.update({
                'page_url': f"/page/{random.randint(1, 100)}",
                'referrer': random.choice(['google', 'facebook', 'direct', 'email'])
            })
        elif event_type == 'search':
            base_props.update({
                'query': random.choice(['shoes', 'laptop', 'book', 'phone', 'tablet']),
                'results_count': str(random.randint(0, 1000))
            })
        
        return base_props
    
    def create_small_files_scenario(self, days: int = 7, files_per_day: int = 144):
        """
        Simulate streaming scenario: many small files (every 10 minutes)
        This will demonstrate the small file problem
        """
        print(f"Creating small files scenario: {days} days, {files_per_day} files per day")
        
        start_date = datetime.now() - timedelta(days=days)
        
        for day in range(days):
            current_date = start_date + timedelta(days=day)
            
            for file_num in range(files_per_day):
                # Generate small batch (10-50 records per file)
                num_records = random.randint(10, 50)
                df = self.generate_user_events(num_records, current_date)
                
                # Create file timestamp (every 10 minutes)
                file_time = current_date + timedelta(minutes=file_num * 10)
                
                # Write to S3 as Parquet
                self._write_parquet_to_s3(
                    df, 
                    f"data/year={current_date.year}/month={current_date.month:02d}/day={current_date.day:02d}/hour={file_time.hour:02d}/minute={file_time.minute:02d}/data.parquet"
                )
                
                if file_num % 24 == 0:  # Progress every 4 hours
                    print(f"  Day {day + 1}: Created {file_num + 1}/{files_per_day} files")
    
    def create_large_files_scenario(self, days: int = 30, files_per_day: int = 4):
        """
        Simulate batch scenario: fewer large files (every 6 hours)
        This demonstrates optimal file sizes
        """
        print(f"Creating large files scenario: {days} days, {files_per_day} files per day")
        
        start_date = datetime.now() - timedelta(days=days + 7)  # Start before small files
        
        for day in range(days):
            current_date = start_date + timedelta(days=day)
            
            for file_num in range(files_per_day):
                # Generate large batch (10,000-50,000 records per file)
                num_records = random.randint(10000, 50000)
                df = self.generate_user_events(num_records, current_date)
                
                # Create file timestamp (every 6 hours)
                file_time = current_date + timedelta(hours=file_num * 6)
                
                # Write to S3 as Parquet
                self._write_parquet_to_s3(
                    df,
                    f"data/year={current_date.year}/month={current_date.month:02d}/day={current_date.day:02d}/batch_{file_num:02d}.parquet"
                )
                
            print(f"  Day {day + 1}: Created {files_per_day} large files")
    
    def _write_parquet_to_s3(self, df: pd.DataFrame, key_suffix: str):
        """Write DataFrame to S3 as Parquet"""
        # Convert properties dict to JSON string for Parquet compatibility
        df['properties'] = df['properties'].apply(json.dumps)
        
        # Convert to PyArrow table
        table = pa.Table.from_pandas(df)
        
        # Write to buffer
        import io
        buffer = io.BytesIO()
        pq.write_table(table, buffer)
        buffer.seek(0)
        
        # Upload to S3
        key = f"{self.table_path}/{key_suffix}"
        self.s3_client.put_object(
            Bucket=self.bucket_name,
            Key=key,
            Body=buffer.getvalue(),
            ContentType='application/octet-stream'
        )
    
    def create_user_profiles_data(self) -> pd.DataFrame:
        """Generate user profiles for standard Snowflake table"""
        data = []
        
        for user_id in range(1, 10001):  # 10K users
            data.append({
                'user_id': user_id,
                'name': f"User {user_id}",
                'email': f"user{user_id}@example.com",
                'region': random.choice(self.regions),
                'created_at': datetime.now() - timedelta(days=random.randint(1, 365))
            })
        
        return pd.DataFrame(data)
    
    def save_user_profiles_csv(self, filename: str = "user_profiles.csv"):
        """Save user profiles as CSV for Snowflake loading"""
        df = self.create_user_profiles_data()
        df.to_csv(filename, index=False)
        print(f"User profiles saved to {filename}")
        return filename

def main():
    import argparse
    
    parser = argparse.ArgumentParser(description='Generate sample data for Iceberg demo')
    parser.add_argument('--bucket', required=True, help='S3 bucket name')
    parser.add_argument('--scenario', choices=['small', 'large', 'both'], default='both',
                       help='Which scenario to generate')
    parser.add_argument('--small-days', type=int, default=7, 
                       help='Days of small files to generate')
    parser.add_argument('--large-days', type=int, default=30,
                       help='Days of large files to generate')
    
    args = parser.parse_args()
    
    generator = IcebergDataGenerator(args.bucket)
    
    if args.scenario in ['small', 'both']:
        generator.create_small_files_scenario(days=args.small_days)
    
    if args.scenario in ['large', 'both']:
        generator.create_large_files_scenario(days=args.large_days)
    
    # Always generate user profiles
    csv_file = generator.save_user_profiles_csv()
    
    print("\nData generation complete!")
    print(f"Upload {csv_file} to Snowflake for user profiles table")

if __name__ == "__main__":
    main()