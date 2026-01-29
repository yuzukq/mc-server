#!/usr/bin/env python3
"""
Minecraft World Data Sync Script for Cloudflare R2
Handles world data synchronization and server locking mechanism
"""

import os
import sys
import json
import time
import socket
from datetime import datetime
from pathlib import Path
import boto3
from botocore.exceptions import ClientError
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

# Configuration
R2_ACCOUNT_ID = os.getenv('R2_ACCOUNT_ID')
R2_ACCESS_KEY_ID = os.getenv('R2_ACCESS_KEY_ID')
R2_SECRET_ACCESS_KEY = os.getenv('R2_SECRET_ACCESS_KEY')
R2_BUCKET_NAME = os.getenv('R2_BUCKET_NAME')
R2_ENDPOINT = os.getenv('R2_ENDPOINT')
LOCAL_DATA_DIR = os.getenv('LOCAL_DATA_DIR', './server001/data')

LOCK_FILE_KEY = 'server.lock'
DATA_ARCHIVE_KEY = 'server-data.tar.gz'


class R2Sync:
    def __init__(self):
        self.validate_config()
        self.s3_client = boto3.client(
            's3',
            endpoint_url=R2_ENDPOINT,
            aws_access_key_id=R2_ACCESS_KEY_ID,
            aws_secret_access_key=R2_SECRET_ACCESS_KEY,
            region_name='auto'
        )
        self.hostname = socket.gethostname()
        
    def validate_config(self):
        """Validate required environment variables"""
        required_vars = [
            'R2_ACCOUNT_ID',
            'R2_ACCESS_KEY_ID', 
            'R2_SECRET_ACCESS_KEY',
            'R2_BUCKET_NAME',
            'R2_ENDPOINT'
        ]
        missing = [var for var in required_vars if not os.getenv(var)]
        if missing:
            print(f"❌ Error: Missing required environment variables: {', '.join(missing)}")
            print("Please check your .env file")
            sys.exit(1)
    
    def check_lock(self):
        """Check if server lock exists"""
        try:
            response = self.s3_client.get_object(
                Bucket=R2_BUCKET_NAME,
                Key=LOCK_FILE_KEY
            )
            lock_data = json.loads(response['Body'].read().decode('utf-8'))
            return lock_data
        except ClientError as e:
            if e.response['Error']['Code'] == 'NoSuchKey':
                return None
            raise
    
    def create_lock(self):
        """Create server lock file"""
        lock_data = {
            'hostname': self.hostname,
            'timestamp': datetime.utcnow().isoformat(),
            'pid': os.getpid()
        }
        
        # Check if lock already exists
        existing_lock = self.check_lock()
        if existing_lock:
            print(f"❌ Error: Server is already running!")
            print(f"   Locked by: {existing_lock.get('hostname', 'unknown')}")
            print(f"   Since: {existing_lock.get('timestamp', 'unknown')}")
            print("\nIf you're sure no server is running, manually delete 'server.lock' from R2 bucket")
            sys.exit(1)
        
        # Create lock
        self.s3_client.put_object(
            Bucket=R2_BUCKET_NAME,
            Key=LOCK_FILE_KEY,
            Body=json.dumps(lock_data, indent=2),
            ContentType='application/json'
        )
        print(f"✅ Lock acquired by {self.hostname}")
    
    def release_lock(self):
        """Release server lock file"""
        try:
            self.s3_client.delete_object(
                Bucket=R2_BUCKET_NAME,
                Key=LOCK_FILE_KEY
            )
            print(f"✅ Lock released")
        except ClientError as e:
            print(f"⚠️  Warning: Could not release lock: {e}")
    
    def download_data(self):
        """Download entire server data from R2"""
        local_data_path = Path(LOCAL_DATA_DIR)
        archive_path = local_data_path.parent / DATA_ARCHIVE_KEY
        
        print(f"📥 Downloading server data from R2...")
        
        try:
            # Check if data archive exists in R2
            self.s3_client.head_object(
                Bucket=R2_BUCKET_NAME,
                Key=DATA_ARCHIVE_KEY
            )
            
            # Download archive
            archive_path.parent.mkdir(parents=True, exist_ok=True)
            self.s3_client.download_file(
                R2_BUCKET_NAME,
                DATA_ARCHIVE_KEY,
                str(archive_path)
            )
            
            # Extract archive
            import tarfile
            import shutil
            
            # Remove existing data directory to avoid conflicts
            if local_data_path.exists():
                shutil.rmtree(local_data_path)
            
            with tarfile.open(archive_path, 'r:gz') as tar:
                tar.extractall(path=local_data_path.parent)
            
            # Clean up archive
            archive_path.unlink()
            
            print(f"✅ Server data downloaded and extracted to {local_data_path}")
            
        except ClientError as e:
            if e.response['Error']['Code'] == '404':
                print(f"ℹ️  No existing server data in R2. Starting with fresh server.")
            else:
                print(f"❌ Error downloading server data: {e}")
                raise
    
    def upload_data(self):
        """Upload entire server data to R2"""
        local_data_path = Path(LOCAL_DATA_DIR)
        archive_path = local_data_path.parent / DATA_ARCHIVE_KEY
        
        if not local_data_path.exists():
            print(f"⚠️  Warning: Data directory not found at {local_data_path}")
            return
        
        print(f"📤 Uploading server data to R2...")
        
        # Create archive
        import tarfile
        with tarfile.open(archive_path, 'w:gz') as tar:
            # Add entire data directory
            tar.add(local_data_path, arcname='data')
        
        # Upload to R2
        self.s3_client.upload_file(
            str(archive_path),
            R2_BUCKET_NAME,
            DATA_ARCHIVE_KEY
        )
        
        # Clean up archive
        archive_path.unlink()
        
        print(f"✅ Server data uploaded to R2")
    
    def sync_init(self):
        """Initialize sync: acquire lock and download data"""
        print("🚀 Initializing server sync...")
        self.create_lock()
        self.download_data()
        print("✅ Sync initialization complete")
    
    def sync_shutdown(self):
        """Shutdown sync: upload data and release lock"""
        print("🔄 Shutting down server sync...")
        self.upload_data()
        self.release_lock()
        print("✅ Sync shutdown complete")


def main():
    if len(sys.argv) < 2:
        print("Usage: python sync.py <command>")
        print("\nCommands:")
        print("  init         - Acquire lock and download data (run before server start)")
        print("  shutdown     - Upload data and release lock (run after server stop)")
        print("  download     - Download server data only")
        print("  upload       - Upload server data only")
        print("  lock         - Acquire server lock only")
        print("  unlock       - Release server lock only")
        print("  check-lock   - Check current lock status")
        sys.exit(1)
    
    command = sys.argv[1]
    sync = R2Sync()
    
    try:
        if command == 'init':
            sync.sync_init()
        elif command == 'shutdown':
            sync.sync_shutdown()
        elif command == 'download':
            sync.download_data()
        elif command == 'upload':
            sync.upload_data()
        elif command == 'lock':
            sync.create_lock()
        elif command == 'unlock':
            sync.release_lock()
        elif command == 'check-lock':
            lock = sync.check_lock()
            if lock:
                print(f"🔒 Server is locked")
                print(f"   Hostname: {lock.get('hostname', 'unknown')}")
                print(f"   Since: {lock.get('timestamp', 'unknown')}")
            else:
                print(f"🔓 Server is not locked")
        else:
            print(f"❌ Unknown command: {command}")
            sys.exit(1)
    except Exception as e:
        print(f"❌ Error: {e}")
        sys.exit(1)


if __name__ == '__main__':
    main()
