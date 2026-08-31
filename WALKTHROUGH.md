# ACH Gateway - Step-by-Step Walkthrough

**Complete visual guide to deploy and run ACH Gateway for M&J Cleaning payments.**

---

## ⏱️ Time Required
- **Quick Start:** 5 minutes
- **Full Walkthrough:** 15 minutes
- **With Monitoring:** 20 minutes

---

## 📍 Step 1: Verify Prerequisites (1 minute)

### Check Docker Installation

```bash
docker --version
```

**Expected Output:**
```
Docker version 24.0.0 (or similar)
```

**If not installed:**
- Download: https://www.docker.com/products/docker-desktop
- Install and restart your terminal

### Check Docker Compose

```bash
docker compose version
```

**Expected Output:**
```
Docker Compose version v2.20.0 (or similar)
```

### Verify Repository Structure

```bash
ls -la
```

**Expected Files:**
```
✓ moov_ach_request_final.json      - Payment data
✓ deploy-achgateway.sh             - Main deployment script
✓ quick-start.sh                   - One-command launcher
✓ examples/                        - Docker compose files
✓ scripts/                         - Helper scripts
```

---

## 🚀 Step 2: Launch Deployment (2 minutes)

### Option A: Quick Start (RECOMMENDED)

```bash
bash quick-start.sh
```

This runs the complete workflow automatically.

**What you'll see:**
```
╔════════════════════════════════════════════════════════════╗
║        ACH Gateway - Quick Start Deployment               ║
║        M&J Cleaning Paper-Authorized Debit Processing     ║
╚════════════════════════════════════════════════════════════╝

Checking prerequisites...
✓ Docker installed
✓ Docker Compose available
Starting ACH Gateway deployment...
```

**Then waits for services to start (⏱️ ~40 seconds)**

### Option B: Step-by-Step Deployment

```bash
# Step 1: Start services only
bash deploy-achgateway.sh

# Step 2: In another terminal, convert JSON to Nacha
bash scripts/json-to-nacha.sh

# Step 3: Submit to gateway
bash scripts/json-to-nacha.sh --submit

# Step 4: Process payment
bash scripts/json-to-nacha.sh --submit --cutoff
```

---

## 🔄 Step 3: Understand What's Happening (2 minutes)

### Service Startup Output

When you run the script, you'll see:

```
Step 3: Create FTP Data Directories
  Creating FTP directory structure...
  ✓ FTP directories created

Step 4: Start Services
  Starting Docker Compose services...
  ✓ Services started
  Waiting for services to be healthy (40 seconds)...

Step 5: Verify Service Health
  ✓ ACH Gateway is responding
  ✓ FTP server is listening on port 2121
  ✓ Kafka is healthy
```

### What Services Are Running?

| Service | Port | Purpose |
|---------|------|---------|
| **achgateway** | 8484 (API), 9494 (Admin) | Accepts & processes ACH files |
| **ftp** | 2121 | Stores uploaded files |
| **kafka1** | 19092 | Event streaming |

### Check Services Manually

```bash
docker ps
```

You should see three containers running:
```
NAMES           STATUS
achgateway      Up 2 minutes
ftp             Up 2 minutes
kafka1          Up 2 minutes (healthy)
```

---

## 💾 Step 4: Payment File Conversion (1 minute)

### Input File: `moov_ach_request_final.json`

Contains M&J Cleaning payment details:

```json
{
  "id": "file-01",
  "fileHeader": {
    "immediateOriginName": "M&J CLEANING AND SANITIZING",
    "immediateDestinationName": "Federal Reserve Bank",
    "fileCreationDate": "260727"
  },
  "batches": [{
    "batchHeader": {
      "serviceClassCode": 225,
      "companyName": "M&J CLEANING AND SANITIZING",
      "effectiveEntryDate": "2026-07-27T00:00:00Z"
    },
    "entryDetails": [
      {
        "individualName": "COLLEGE OF EASTERN IDAHO",
        "amount": 684
      },
      {
        "individualName": "MARIA MALDONADO",
        "amount": 251
      }
    ]
  }]
}
```

### Conversion Process

The script converts JSON → Nacha format automatically:

```bash
docker run -it --rm -v $(pwd):/data moov/ach:latest achcli moov_ach_request_final.json > MJ_Cleaning.ach
```

### Output File: `MJ_Cleaning.ach`

Nacha ACH format (plaintext):

```
101 23138010401210428821906240000A094101Federal Reserve Bank   M&J CLEANING AND SANITIZING
5225M&J CLEANING AND SANITIZING  1922786717 PPD CLEANING  260727   1041215660000001
622312400005412345678         0000000684               COLLEGE OF EASTERN IDAHO    0041215660000001
622112100024825565371720      0000000251               MARIA MALDONADO              0041215660000002
622204121566312071167505956   0000000935               MJ CLEANING AND SANITIZING   0041215660000003
820000010000003024500029000000000935000000000935192278671704121566000001
9000001000001000000010024500029000000000935000000000935
```

---

## 📤 Step 5: Submit to Gateway (1 minute)

### What Happens

```bash
curl -XPOST "http://localhost:8484/shards/foo/files/mj-cleaning-001" \
  --data-binary @MJ_Cleaning.ach \
  -H "Content-Type: text/plain"
```

**Response:**
```
HTTP/1.1 200 OK
```

### File Gets Queued

File enters the pending queue:
```
Shard: "testing"
File Path: mergable/foo/mj-cleaning-001.ach
Status: Waiting for cutoff window
```

### Verify File Was Accepted

```bash
curl -s http://localhost:9494/shards/testing/files | jq .
```

**Response:**
```json
{
  "files": [
    "mergable/foo/mj-cleaning-001.ach"
  ],
  "SourceHostname": "achgateway-container-id"
}
```

---

## ⏰ Step 6: Cutoff Processing (2 minutes)

### What is a Cutoff Window?

Cutoff windows determine when pending files are uploaded to the bank:

- **First Window:** 10:30 AM PT
- **Second Window:** 2:00 PM PT

### Trigger Manual Cutoff (for Testing)

```bash
curl -XPUT "http://localhost:9494/trigger-cutoff" \
  -H "Content-Type: application/json" \
  -d '{"shardNames":["testing"]}'
```

### What the Script Does

1. **Merges** all pending files from the same shard
2. **Validates** Nacha format
3. **Publishes** FileUploaded event to Kafka
4. **Connects** to FTP server
5. **Uploads** file to outbound directory
6. **Confirms** upload success

### Monitor the Process

```bash
docker logs -f $(docker ps -q -f 'name=achgateway')
```

**You'll see:**
```
msg="begin handle received ACHFile"
msg="finished handling ACHFile"
msg="starting cutoff window processing"
msg="found 1 matching ACH files"
msg="merged 1 files into 1 files"
msg="FileUploaded event emitted"
msg="ftp connection successful"
msg="file uploaded successfully"
```

---

## ✅ Step 7: Verify Upload (1 minute)

### Check FTP Outbound Directory

```bash
ls -lah testdata/ftp-server/outbound/
```

**Expected Output:**
```
-rw-r--r--  1 user  group  1.2K Jul 27 10:30 BANK_ACH_UPLOAD_20260727_001.ach
```

### View the Uploaded File

```bash
cat testdata/ftp-server/outbound/*.ach
```

**Shows the Nacha formatted payment file ready for bank processing.**

### Validate File Format

```bash
docker run -it --rm -v $(pwd):/data moov/ach:latest \
  achcli testdata/ftp-server/outbound/*.ach
```

**Success Output:**
```
File ID: file-01
Batch Count: 1
Entry Count: 3
Total Debit: $9.35
Total Credit: $9.35
Status: ✓ Valid
```

---

## 📊 Step 8: Check Payment Details (1 minute)

### View Payment Metadata

```bash
curl -s http://localhost:9494/shards/testing/files/mergable/foo/mj-cleaning-001.ach | jq .
```

### Payment Summary

```json
{
  "file_id": "mj-cleaning-001",
  "shard_key": "foo",
  "shard_name": "testing",
  "hostname": "achgateway",
  "accepted_at": "2026-07-27T10:30:00Z",
  "processed_at": "2026-07-27T10:30:15Z",
  "file_path": "mergable/foo/mj-cleaning-001.ach",
  "status": "uploaded_to_ftp",
  "payment_details": {
    "company": "M&J CLEANING AND SANITIZING",
    "effective_date": "2026-07-27",
    "total_amount": "$9.35",
    "entries": [
      {
        "name": "COLLEGE OF EASTERN IDAHO",
        "amount": "$6.84",
        "routing": "12400005",
        "account": "9809524995"
      },
      {
        "name": "MARIA MALDONADO",
        "amount": "$2.51",
        "routing": "12100024",
        "account": "5565371720"
      }
    ]
  }
}
```

---

## 📈 Step 9: Monitor with Dashboard (Optional)

### Setup Real-Time Monitoring

**Terminal 1: Status Dashboard**
```bash
bash status-check.sh --watch
```

Refreshes every 5 seconds, shows:
- Service health
- Pending files
- FTP uploads
- Metrics
- Quick commands

**Terminal 2: Log Streaming**
```bash
docker logs -f $(docker ps -q -f 'name=achgateway')
```

**Terminal 3: FTP Directory Watch**
```bash
watch -n 2 'ls -lah testdata/ftp-server/outbound/'
```

---

## 🎯 Step 10: Troubleshooting Issues

### Issue: "Gateway not responding"

```bash
# Check if container is running
docker ps | grep achgateway

# View recent errors
docker logs $(docker ps -q -f 'name=achgateway') | tail -20

# Restart services
cd examples/getting-started
docker compose restart
```

### Issue: "File not appearing in outbound"

```bash
# Check if file was processed
curl -s http://localhost:9494/shards/testing/files | jq .

# View processing logs
docker logs $(docker ps -q -f 'name=achgateway') | grep "mj-cleaning"

# Re-trigger cutoff
curl -XPUT "http://localhost:9494/trigger-cutoff" \
  -H "Content-Type: application/json" \
  -d '{"shardNames":["testing"]}'
```

### Issue: "Services won't start"

```bash
# Check Docker daemon
docker ps

# Remove old containers
docker compose -f examples/getting-started/docker-compose.yml down -v

# Start fresh
bash deploy-achgateway.sh --cleanup
```

---

## 🧹 Step 11: Cleanup (When Done)

### Stop All Services

```bash
cd examples/getting-started
docker compose down
```

### Remove All Data

```bash
cd examples/getting-started
docker compose down -v
rm -rf ../../testdata/ftp-server/outbound/*
```

### Full Reset

```bash
bash deploy-achgateway.sh --full --cleanup
```

---

## 📋 Complete Command Reference

### Quick Commands

```bash
# One-command deployment
bash quick-start.sh

# Full deployment with options
bash deploy-achgateway.sh --full --cleanup --logs

# Convert JSON to Nacha
bash scripts/json-to-nacha.sh

# Submit and process
bash scripts/json-to-nacha.sh --submit --cutoff

# Monitor status (auto-refresh)
bash status-check.sh --watch

# Stream logs
bash status-check.sh --logs

# Debug mode
bash status-check.sh --debug
```

### Gateway API Calls

```bash
# Submit file
curl -XPOST "http://localhost:8484/shards/foo/files/mj-cleaning-001" \
  --data-binary @MJ_Cleaning.ach \
  -H "Content-Type: text/plain"

# List pending files
curl -s http://localhost:9494/shards/testing/files | jq .

# Get file details
curl -s http://localhost:9494/shards/testing/files/mergable/foo/mj-cleaning-001.ach | jq .

# Trigger cutoff
curl -XPUT "http://localhost:9494/trigger-cutoff" \
  -H "Content-Type: application/json" \
  -d '{"shardNames":["testing"]}'

# Get metrics
curl -s http://localhost:9494/metrics | grep ach_gateway

# Check health
curl -s http://localhost:9494/ping
```

### Docker Commands

```bash
# View running services
docker ps

# View container logs
docker logs -f $(docker ps -q -f 'name=achgateway')

# Execute command in container
docker exec -it $(docker ps -q -f 'name=achgateway') sh

# Stop services
cd examples/getting-started && docker compose down

# Restart services
cd examples/getting-started && docker compose restart
```

---

## 🎓 Learning Objectives Achieved

After completing this walkthrough, you will:

✅ Understand ACH payment file processing  
✅ Deploy Moov ACH Gateway using Docker  
✅ Convert JSON payment data to Nacha format  
✅ Submit files to the gateway  
✅ Trigger cutoff processing  
✅ Verify uploads to FTP server  
✅ Monitor and troubleshoot the system  

---

## 🚀 Next: Production Deployment

For production use, see `DEPLOYMENT.md` for:

- Security configuration
- Database setup (MySQL/Spanner)
- Multi-shard configuration
- Real FTP/SFTP credentials
- Monitoring and alerting
- Backup and recovery

---

## 📞 Support Resources

| Topic | Resource |
|-------|----------|
| **ACH Gateway** | https://moov-io.github.io/achgateway/ |
| **ACH Format** | https://www.nacha.org/content/what-ach |
| **Docker Help** | https://docs.docker.com/get-started/ |
| **Issues** | https://github.com/moov-io/achgateway/issues |

---

## ✨ Success Checklist

- [ ] Docker installed and running
- [ ] Repository cloned locally
- [ ] Run `bash quick-start.sh`
- [ ] Services started successfully
- [ ] JSON converted to Nacha
- [ ] File submitted to gateway
- [ ] Cutoff triggered
- [ ] File uploaded to FTP
- [ ] Verified in `testdata/ftp-server/outbound/`
- [ ] Read this entire guide
- [ ] Ready for production! 🎉

---

**Congratulations!** 🎊

You have successfully deployed ACH Gateway and processed M&J Cleaning's paper-authorized debits. The payment file is ready for your bank to process.

**Questions?** Check the troubleshooting section or see `README-DEPLOYMENT.md` for more details.

---

*Last Updated: 2025-07-27*  
*ACH Gateway v0.33.3+*
