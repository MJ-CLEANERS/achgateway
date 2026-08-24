# ACH Gateway Deployment & Payment Processing Guide

**Complete automation for deploying Moov ACH Gateway and processing M&J Cleaning paper-authorized debits.**

---

## 🚀 Quick Start (2 minutes)

```bash
# One command to deploy everything and process payment
bash quick-start.sh
```

That's it! The script will:
- ✅ Start all services (ACH Gateway, Kafka, FTP)
- ✅ Convert JSON payment data to Nacha format
- ✅ Submit file to gateway
- ✅ Trigger cutoff processing
- ✅ Upload to FTP server
- ✅ Display results

---

## 📋 What's Included

### Deployment Scripts

| Script | Purpose | Usage |
|--------|---------|-------|
| `quick-start.sh` | One-command deployment | `bash quick-start.sh` |
| `deploy-achgateway.sh` | Full control deployment | `bash deploy-achgateway.sh [--full] [--cleanup] [--logs]` |
| `scripts/json-to-nacha.sh` | JSON conversion & submission | `bash scripts/json-to-nacha.sh [--submit] [--cutoff]` |
| `status-check.sh` | Monitor & troubleshoot | `bash status-check.sh [--watch] [--logs] [--debug]` |
| `DEPLOYMENT.md` | Detailed guide | Read for in-depth instructions |

### Data Files

- `moov_ach_request_final.json` - M&J Cleaning payment data (2 authorized debitors + 1 credit)
- `examples/getting-started/config.yml` - Gateway configuration
- `examples/getting-started/docker-compose.yml` - Service definitions

---

## 🎯 Usage Scenarios

### Scenario 1: Deploy & Process (Recommended for First-Time)

```bash
bash quick-start.sh
```

**What happens:**
1. Checks Docker is installed
2. Starts all services with fresh data
3. Converts JSON to Nacha ACH format
4. Submits payment file to gateway
5. Triggers cutoff processing
6. Confirms upload to FTP server
7. Displays payment details

**Result:** ACH file ready at `testdata/ftp-server/outbound/`

---

### Scenario 2: Manual Multi-Step Deployment

```bash
# Step 1: Start services
bash deploy-achgateway.sh

# Step 2: Convert JSON to Nacha
bash scripts/json-to-nacha.sh

# Step 3: Submit to gateway
bash scripts/json-to-nacha.sh --submit

# Step 4: Trigger cutoff
bash scripts/json-to-nacha.sh --submit --cutoff
```

---

### Scenario 3: Full Deployment with All Options

```bash
# Clean slate, full workflow, show logs
bash deploy-achgateway.sh --full --cleanup --logs
```

---

### Scenario 4: Monitor Ongoing Operations

```bash
# Real-time status (refreshes every 5 seconds)
bash status-check.sh --watch

# With debug info
bash status-check.sh --watch --debug

# Stream container logs
bash status-check.sh --logs
```

---

## 🔍 Checking Results

### View Uploaded Payment File

```bash
# Show the Nacha ACH file that was uploaded
cat testdata/ftp-server/outbound/*.ach
```

### Check Pending Files

```bash
# List files waiting to be processed
curl -s http://localhost:9494/shards/testing/files | jq .
```

### View Gateway Metrics

```bash
# Display processing metrics
curl -s http://localhost:9494/metrics | grep ach_gateway
```

### Monitor Real-Time Logs

```bash
# Stream gateway logs
docker logs -f $(docker ps -q -f 'name=achgateway')

# OR use the status script
bash status-check.sh --logs
```

---

## 📊 Payment Data Details

The `moov_ach_request_final.json` contains:

**Company:** M&J CLEANING AND SANITIZING
- EIN: 922786717
- Routing Number: 041215663
- Account Number: 2071167505956

**Authorized Debitors:**
1. **College of Eastern Idaho**
   - Routing: 12400005
   - Account: 9809524995
   - Debit Amount: $6.84

2. **Maria Maldonado**
   - Routing: 12100024
   - Account: 5565371720
   - Debit Amount: $2.51

**Credits Received:** $9.35 (sum of debits)

**Status:** Paper Authorization Signed

---

## 🛠️ Service Configuration

### ACH Gateway (Port 8484 - Business Logic)
- Receives ACH file submissions
- Manages shard mappings
- Routes files for processing

### Admin Panel (Port 9494)
- Pending file listing
- Cutoff triggering
- Metrics and monitoring
- Configuration viewing

### FTP Server (Port 2121)
- Credentials: admin / 123456
- **Inbound:** `/inbound/` - Download files from bank
- **Outbound:** `/outbound/` - Upload files to bank
- **Returns:** `/returned/` - Returned files
- **Reconciliation:** `/reconciliation/` - Reconciliation files

### Kafka (Internal)
- Event streaming
- File processing pipeline
- Event notifications

---

## ⚙️ Advanced Configuration

### Change Cutoff Times

Edit `examples/getting-started/config.yml`:

```yaml
ACHGateway:
  Sharding:
    Shards:
      - name: "testing"
        cutoffs:
          timezone: "America/Los_Angeles"
          windows:
            - "10:30"      # First cutoff
            - "14:00"      # Second cutoff
```

### Modify FTP Connection

```yaml
Upload:
  agents:
    - id: "local-ftp"
      ftp:
        hostname: "ftp.yourbank.com"
        username: "your-username"
        password: "your-password"
```

### Enable File Encryption

```yaml
Inbound:
  HTTP:
    Transform:
      Encryption:
        AES:
          Key: "your-256-bit-key"
```

---

## 🚨 Troubleshooting

### Issue: "Docker not found"
```bash
# Install Docker Desktop from https://www.docker.com/products/docker-desktop
# Or on Linux: sudo apt-get install docker.io docker-compose
```

### Issue: "Port 8484 already in use"
```bash
# Find and stop the service using the port
sudo lsof -i :8484
sudo kill -9 <PID>

# Or change the port in examples/getting-started/config.yml
```

### Issue: "File not appearing in pending queue"
```bash
# Check gateway logs
bash status-check.sh --logs

# Verify file format
docker run -it --rm -v $(pwd):/data moov/ach:latest achcli /data/MJ_Cleaning.ach

# Try submitting again
bash scripts/json-to-nacha.sh --submit
```

### Issue: "Cutoff not processing files"
```bash
# Check if gateway is running
bash status-check.sh

# Manually trigger cutoff
curl -XPUT "http://localhost:9494/trigger-cutoff" \
  -H "Content-Type: application/json" \
  -d '{"shardNames":["testing"]}'

# Monitor logs during processing
bash status-check.sh --logs
```

### Issue: "FTP upload failed"
```bash
# Verify FTP is running
bash status-check.sh | grep FTP

# Test FTP connection
ftp localhost 2121
# Login: admin / 123456

# Check FTP data directory
ls -la testdata/ftp-server/
```

---

## 📝 API Reference

### Submit Payment File

```bash
curl -XPOST "http://localhost:8484/shards/foo/files/mj-cleaning-001" \
  --data-binary @MJ_Cleaning.ach \
  -H "Content-Type: text/plain"
```

**Response:**
- `200 OK` - File accepted
- `400 Bad Request` - Invalid format
- `500 Internal Server Error` - Processing error

### List Pending Files

```bash
curl -s http://localhost:9494/shards/testing/files | jq .
```

### Get File Details

```bash
curl -s http://localhost:9494/shards/testing/files/mergable/foo/mj-cleaning-001.ach | jq .
```

### Trigger Cutoff Processing

```bash
curl -XPUT "http://localhost:9494/trigger-cutoff" \
  -H "Content-Type: application/json" \
  -d '{"shardNames":["testing"]}'
```

### Get Gateway Configuration

```bash
curl -s http://localhost:9494/config | jq .
```

### Get Metrics

```bash
curl -s http://localhost:9494/metrics | grep ach_gateway
```

---

## 🔄 Payment Processing Workflow

```
1. JSON Input (moov_ach_request_final.json)
   ↓
2. Convert to Nacha Format (achcli)
   ↓
3. Submit to Gateway HTTP API (port 8484)
   ↓
4. File Queued in Pending Files
   ↓
5. Cutoff Window Triggered (10:30 AM or 2:00 PM)
   ↓
6. File Merged with Others (if any)
   ↓
7. Nacha Format Validation
   ↓
8. FileUploaded Event Published to Kafka
   ↓
9. Upload Agent Connects to FTP
   ↓
10. File Uploaded to FTP Outbound Directory
   ↓
11. File Ready for Bank Processing
```

---

## 📊 Monitoring Dashboard

Create a monitoring dashboard with multiple terminals:

```bash
# Terminal 1: Status monitoring (refreshes every 5 seconds)
bash status-check.sh --watch

# Terminal 2: Stream logs
bash status-check.sh --logs

# Terminal 3: Watch FTP directory
watch -n 2 'ls -lah testdata/ftp-server/outbound/'
```

---

## 🧹 Cleanup & Restart

### Stop All Services

```bash
cd examples/getting-started
docker compose down
```

### Stop Services and Remove Data

```bash
cd examples/getting-started
docker compose down -v
rm -rf ../../testdata/ftp-server/outbound/*
```

### Full Clean Restart

```bash
bash deploy-achgateway.sh --full --cleanup
```

---

## 📚 Additional Resources

| Resource | Link |
|----------|------|
| ACH Gateway Docs | https://moov-io.github.io/achgateway/ |
| ACH Library | https://github.com/moov-io/ach |
| Nacha Format Spec | https://www.nacha.org/ |
| Docker Documentation | https://docs.docker.com/ |
| GitHub Issues | https://github.com/moov-io/achgateway/issues |

---

## 🤝 Support

### Verify Environment

```bash
# Check all prerequisites and services
bash status-check.sh --debug
```

### Collect Diagnostic Info

```bash
# Gather deployment info for troubleshooting
{
  echo "=== System Info ==="
  uname -a
  echo "=== Docker ==="
  docker --version
  echo "=== Services ==="
  cd examples/getting-started && docker compose ps
  echo "=== Gateway Health ==="
  curl -s http://localhost:9494/ping
  echo "=== FTP Status ==="
  nc -zv localhost 2121
  echo "=== Logs (last 50 lines) ==="
  docker compose logs --tail 50 achgateway
} > diagnostic-info.txt
cat diagnostic-info.txt
```

---

## ✅ Deployment Checklist

- [ ] Docker installed and running
- [ ] Repository cloned locally
- [ ] `moov_ach_request_final.json` present
- [ ] Network ports available (8484, 9494, 2121, 19092)
- [ ] Sufficient disk space (2GB minimum)
- [ ] Sufficient RAM (4GB minimum)
- [ ] Run `bash quick-start.sh`
- [ ] Payment file uploaded to FTP
- [ ] Verify results in `testdata/ftp-server/outbound/`

---

## 🎓 Learning Path

1. **Beginner:** Run `bash quick-start.sh` and observe the output
2. **Intermediate:** Read `DEPLOYMENT.md` and understand each step
3. **Advanced:** Modify `examples/getting-started/config.yml` and rebuild
4. **Expert:** Customize ACH file processing and add transformations

---

**Last Updated:** 2025-07-27  
**ACH Gateway Version:** v0.33.3+  
**Status:** Production Ready

---

## 🎯 Next Steps

1. Run the deployment:
   ```bash
   bash quick-start.sh
   ```

2. Verify the payment file:
   ```bash
   cat testdata/ftp-server/outbound/*.ach
   ```

3. Check the status anytime:
   ```bash
   bash status-check.sh
   ```

4. For production deployment, see `DEPLOYMENT.md`

---

**Built for M&J Cleaning & Sanitizing**  
*Automated ACH payment processing made simple.*
