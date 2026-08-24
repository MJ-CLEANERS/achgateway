# ACH Gateway Deployment Guide

Complete instructions to deploy ACH Gateway and collect paper-authorized debits from M&J Cleaning.

## Prerequisites

- Docker & Docker Compose installed
- Git (to clone the repository)
- 4+ GB RAM available
- Ports 8484, 9494, 2121, 19092 available

## Quick Start (5 minutes)

### Step 1: Navigate to Getting Started Directory

```bash
cd examples/getting-started/
pwd  # Confirm you're in the right location
```

### Step 2: Create Required Data Directories

```bash
# Create FTP server directory structure
mkdir -p ../../testdata/ftp-server/{inbound,outbound,reconciliation,returned}
chmod -R 777 ../../testdata/ftp-server/

# Verify structure
ls -la ../../testdata/ftp-server/
```

### Step 3: Start All Services

```bash
# Start services (pulls images if needed)
docker compose up -d

# Wait for services to be healthy (30-40 seconds)
sleep 40

# Verify all services are running
docker compose ps

# Expected output:
# NAME                COMMAND                  SERVICE      STATUS
# ftp                 "-host=0.0.0.0 ..."     ftp          Up
# kafka1              "redpanda start ..."     kafka1       Up (healthy)
# achgateway          "/achgateway -conf..."  achgateway   Up
```

### Step 4: Verify Service Health

```bash
# Check ACH Gateway is responding
curl -s http://localhost:9494/ping
# Expected: PONG

# Check metrics endpoint
curl -s http://localhost:9494/metrics | head -20

# Check FTP is responding
nc -zv localhost 2121
# Expected: Connection successful
```

## Processing M&J Cleaning Payment

### Step 1: Prepare Payment File from JSON

The `moov_ach_request_final.json` contains M&J Cleaning paper-authorized debit information. Convert it to Nacha format:

```bash
# Option A: Use provided conversion script
bash ./scripts/json-to-nacha.sh

# Option B: Manual conversion with achcli
docker run -it --rm -v $(pwd):/data moov/ach:latest \
  achcli /data/moov_ach_request_final.json > MJ_Cleaning.ach
```

### Step 2: Submit ACH File to Gateway

```bash
# Submit the file for processing
curl -XPOST "http://localhost:8484/shards/foo/files/mj-cleaning-001" \
  --data @./MJ_Cleaning.ach \
  -H "Content-Type: text/plain" \
  -v

# Expected Response:
# HTTP/1.1 200 OK
# File accepted for processing
```

### Step 3: Verify File Was Queued

```bash
# List pending files in "testing" shard
curl -s http://localhost:9494/shards/testing/files | jq .

# Expected response shows file in queue:
# {
#   "files": [
#     "mergable/foo/mj-cleaning-001.ach"
#   ],
#   "SourceHostname": "achgateway-container-id"
# }
```

### Step 4: Monitor Processing Logs

```bash
# Watch real-time logs
docker logs -f $(docker compose ps -q achgateway)

# Look for messages:
# - "begin handle received ACHFile"
# - "finished handling ACHFile"
# - "starting cutoff window processing"
# - "merged 1 files into 1 files"
```

### Step 5: Trigger Upload Cutoff (Manual)

Production cutoff times are 10:30 AM and 2:00 PM PT. For testing, trigger manually:

```bash
# Trigger cutoff processing now
curl -XPUT "http://localhost:9494/trigger-cutoff" \
  --data '{"shardNames":["testing"]}' \
  -H "Content-Type: application/json" \
  -v

# Expected logs:
# msg="starting manual cutoff window processing"
# msg="found 1 matching ACH files"
# msg="merged 1 files into 1 files"
# msg="FileUploaded event emitted"
```

### Step 6: Verify File Uploaded to FTP

```bash
# Check outbound directory
ls -lah ../../testdata/ftp-server/outbound/

# Expected: File matching pattern BANK_ACH_UPLOAD_*.ach
# Display file contents
cat ../../testdata/ftp-server/outbound/*.ach

# Validate with achcli
docker run -it --rm -v $(pwd):/data moov/ach:latest \
  achcli /data/../../testdata/ftp-server/outbound/*.ach
```

## API Reference

### Submit Payment File

```bash
POST /shards/{shardKey}/files/{fileID}
Host: localhost:8484
Content-Type: text/plain

<ACH file content>
```

**Parameters:**
- `shardKey`: "foo" (maps to "testing" shard)
- `fileID`: Unique identifier for this file

**Response:**
- `200 OK` - File accepted
- `400 Bad Request` - Invalid ACH format
- `500 Internal Server Error` - Processing error

### Cancel Pending File

```bash
DELETE /shards/foo/files/mj-cleaning-001
Host: localhost:8484
```

### List Pending Files

```bash
GET /shards/testing/files
Host: localhost:9494
```

### Get Pending File Details

```bash
GET /shards/testing/files/mergable/foo/mj-cleaning-001.ach
Host: localhost:9494
```

### Trigger Cutoff Processing

```bash
PUT /trigger-cutoff
Host: localhost:9494
Content-Type: application/json

{
  "shardNames": ["testing"]
}
```

### Trigger Inbound Processing

```bash
PUT /trigger-inbound
Host: localhost:9494
Content-Type: application/json

{
  "shardNames": ["testing"]
}
```

## Configuration Details

### Shard Mapping

The configuration maps `shardKey` to actual shards:

```yaml
Mappings:
  - shardKey: "foo"          # Your submission identifier
    shardName: "testing"     # Actual shard in config
```

### Cutoff Windows

Files submitted before the cutoff time are processed at:
- **10:30 AM PT** - First daily cutoff
- **2:00 PM PT** - Second daily cutoff

Time zone: `America/Los_Angeles`

### FTP Upload Configuration

**Upload Agent: local-ftp**
```yaml
ftp:
  hostname: "ftp:2121"
  username: "admin"
  password: "123456"
paths:
  inbound: "/inbound/"        # Download files from ODFI
  outbound: "/outbound/"      # Upload files to ODFI
  reconciliation: "/reconciliation/"  # Reconciliation files
  return: "/returned/"        # Returned files
```

## Troubleshooting

### Issue: File Submission Returns 400

**Solution: Validate ACH file format**

```bash
# Check if file is valid
docker run -it --rm -v $(pwd):/data moov/ach:latest \
  achcli /data/MJ_Cleaning.ach

# Common issues:
# - Line endings (should be CRLF for ACH files)
# - Invalid record counts
# - Malformed entries
```

**Fix line endings on Unix/Mac:**
```bash
dos2unix MJ_Cleaning.ach
# OR
sed -i 's/$/\r/' MJ_Cleaning.ach
```

### Issue: File Not Appearing in Pending Files

**Solution: Check service logs**

```bash
# View gateway logs
docker logs $(docker compose ps -q achgateway)

# View FTP logs
docker logs $(docker compose ps -q ftp)

# View Kafka logs
docker logs $(docker compose ps -q kafka1)
```

### Issue: Cutoff Not Processing Files

**Possible Causes:**
1. Service not running: `docker compose ps`
2. Current time outside cutoff window
3. Shard not configured properly

**Solution:**
```bash
# Force manual cutoff trigger
curl -XPUT "http://localhost:9494/trigger-cutoff" \
  --data '{"shardNames":["testing"]}' \
  -H "Content-Type: application/json"

# Verify shard configuration
curl -s http://localhost:9494/shards | jq .
```

### Issue: FTP Connection Fails

**Solution: Test FTP directly**

```bash
# Test FTP connection
ftp -l 2121 admin 123456

# In ftp prompt:
# ftp> ls
# ftp> cd outbound
# ftp> quit

# Or use curl
curl -u admin:123456 ftp://localhost:2121/
```

## Monitoring & Metrics

### Prometheus Metrics (Port 9494)

```bash
# Get all metrics
curl -s http://localhost:9494/metrics | grep ach_

# Key metrics:
curl -s http://localhost:9494/metrics | grep -E "ach_gateway_incoming|ach_gateway_file"
```

### View Configuration

```bash
# Get active configuration (values masked)
curl -s http://localhost:9494/config | jq .
```

### Shard Mappings

```bash
# List all shard mappings
curl -s http://localhost:8484/shard_mappings | jq .
```

## Complete Workflow Example

```bash
#!/bin/bash
set -e

cd examples/getting-started/

# 1. Ensure services are running
echo "Starting services..."
docker compose up -d
sleep 40

# 2. Verify health
echo "Checking health..."
curl -s http://localhost:9494/ping

# 3. Convert JSON to Nacha (if needed)
echo "Converting JSON to ACH format..."
if [ ! -f "MJ_Cleaning.ach" ]; then
    docker run -it --rm -v $(pwd):/data moov/ach:latest \
      achcli /data/moov_ach_request_final.json > MJ_Cleaning.ach
fi

# 4. Submit file
echo "Submitting payment file..."
curl -XPOST "http://localhost:8484/shards/foo/files/mj-cleaning-001" \
  --data @./MJ_Cleaning.ach \
  -H "Content-Type: text/plain"

# 5. Check pending
echo "Checking pending files..."
sleep 2
curl -s http://localhost:9494/shards/testing/files | jq .

# 6. Trigger cutoff
echo "Triggering cutoff processing..."
curl -XPUT "http://localhost:9494/trigger-cutoff" \
  --data '{"shardNames":["testing"]}' \
  -H "Content-Type: application/json"

# 7. Monitor logs
echo "Monitoring upload progress..."
docker logs -f $(docker compose ps -q achgateway) &
LOGS_PID=$!
sleep 10
kill $LOGS_PID 2>/dev/null || true

# 8. Verify upload
echo "Verifying file uploaded..."
ls -lah ../../testdata/ftp-server/outbound/
echo "✓ Deployment complete!"
```

## Stopping Services

```bash
# Stop all services
docker compose down

# Remove all data (clean slate)
docker compose down -v
rm -rf ../../testdata/ftp-server/outbound/*
```

## Additional Resources

- **ACH Gateway Docs**: https://moov-io.github.io/achgateway/
- **ACH Library**: https://github.com/moov-io/ach
- **Nacha Format**: https://www.nacha.org/
- **GitHub Issues**: https://github.com/moov-io/achgateway/issues

---

**Last Updated**: 2025-07-27
**Version**: ACH Gateway v0.33.3+
