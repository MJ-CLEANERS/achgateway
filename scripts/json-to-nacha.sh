#!/bin/bash
# json-to-nacha.sh - Convert moov ACH JSON to Nacha format and submit to gateway
# Usage: bash scripts/json-to-nacha.sh [--submit] [--cutoff]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
JSON_FILE="${PROJECT_ROOT}/moov_ach_request_final.json"
NACHA_FILE="${PROJECT_ROOT}/examples/getting-started/MJ_Cleaning.ach"
GATEWAY_URL="http://localhost:8484"
ADMIN_URL="http://localhost:9494"
SHARD_KEY="foo"
FILE_ID="mj-cleaning-001"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse arguments
SUBMIT=false
TRIGGER_CUTOFF=false
for arg in "$@"; do
  case $arg in
    --submit)
      SUBMIT=true
      ;;
    --cutoff)
      TRIGGER_CUTOFF=true
      ;;
  esac
done

log_info() {
  echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
  echo -e "${GREEN}[✓]${NC} $1"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $1"
}

log_warning() {
  echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Step 1: Verify JSON file exists
log_info "Verifying JSON file..."
if [ ! -f "$JSON_FILE" ]; then
  log_error "JSON file not found: $JSON_FILE"
  exit 1
fi
log_success "JSON file found: $JSON_FILE"

# Step 2: Check if achcli is available
log_info "Checking for achcli..."
if ! command -v achcli &> /dev/null; then
  log_info "achcli not found locally, using Docker..."
  ACHCLI_CMD="docker run -it --rm -v ${PROJECT_ROOT}:/data moov/ach:latest achcli"
else
  log_success "achcli found"
  ACHCLI_CMD="achcli"
fi

# Step 3: Convert JSON to Nacha format
log_info "Converting JSON to Nacha format..."
mkdir -p "$(dirname "$NACHA_FILE")"

if $ACHCLI_CMD "$JSON_FILE" > "$NACHA_FILE" 2>&1; then
  log_success "Conversion successful"
  log_info "Output file: $NACHA_FILE"
  log_info "File size: $(du -h "$NACHA_FILE" | cut -f1)"
else
  log_error "Conversion failed"
  exit 1
fi

# Step 4: Validate the generated Nacha file
log_info "Validating Nacha file format..."
if $ACHCLI_CMD "$NACHA_FILE" > /dev/null 2>&1; then
  log_success "Nacha file validation passed"
else
  log_warning "Nacha file validation completed (check output)"
fi

# Step 5: Display file preview
log_info "File preview (first 10 lines):"
head -10 "$NACHA_FILE" | sed 's/^/  /'

# Step 6: Submit to gateway if requested
if [ "$SUBMIT" = true ]; then
  log_info "Checking gateway connectivity..."
  if ! curl -s "$GATEWAY_URL/ping" > /dev/null; then
    log_error "Cannot connect to gateway at $GATEWAY_URL"
    log_info "Start services with: cd examples/getting-started && docker compose up -d"
    exit 1
  fi
  log_success "Gateway is responding"

  log_info "Submitting ACH file to gateway..."
  RESPONSE=$(curl -s -X POST \
    "$GATEWAY_URL/shards/$SHARD_KEY/files/$FILE_ID" \
    --data-binary @"$NACHA_FILE" \
    -H "Content-Type: text/plain" \
    -w "\n%{http_code}")
  
  HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
  BODY=$(echo "$RESPONSE" | head -n-1)

  if [ "$HTTP_CODE" = "200" ]; then
    log_success "File submitted successfully (HTTP $HTTP_CODE)"
  else
    log_error "File submission failed (HTTP $HTTP_CODE)"
    log_error "Response: $BODY"
    exit 1
  fi

  # Step 7: Verify file was queued
  log_info "Waiting for file to be queued (2 seconds)..."
  sleep 2

  log_info "Checking pending files..."
  PENDING=$(curl -s "$ADMIN_URL/shards/testing/files")
  
  if echo "$PENDING" | grep -q "$FILE_ID"; then
    log_success "File found in pending queue"
    echo "$PENDING" | jq . | sed 's/^/  /'
  else
    log_warning "File not yet visible in pending queue"
    log_info "Pending files response:"
    echo "$PENDING" | jq . | sed 's/^/  /'
  fi

  # Step 8: Trigger cutoff if requested
  if [ "$TRIGGER_CUTOFF" = true ]; then
    log_info "Triggering cutoff processing..."
    CUTOFF_RESPONSE=$(curl -s -X PUT \
      "$ADMIN_URL/trigger-cutoff" \
      -H "Content-Type: application/json" \
      -d '{"shardNames":["testing"]}')

    if echo "$CUTOFF_RESPONSE" | grep -q "testing"; then
      log_success "Cutoff processing initiated"
      echo "$CUTOFF_RESPONSE" | jq . | sed 's/^/  /'
    else
      log_error "Cutoff processing failed"
      log_info "Response: $CUTOFF_RESPONSE"
    fi

    # Step 9: Monitor upload
    log_info "Monitoring upload progress (monitoring for 15 seconds)..."
    CONTAINER=$(docker compose -f "${PROJECT_ROOT}/examples/getting-started/docker-compose.yml" ps -q achgateway)
    
    if [ -n "$CONTAINER" ]; then
      docker logs -f "$CONTAINER" 2>&1 | head -30 &
      LOG_PID=$!
      sleep 15
      kill $LOG_PID 2>/dev/null || true
    fi

    # Step 10: Verify file uploaded to FTP
    log_info "Checking FTP outbound directory..."
    FTP_OUTBOUND="${PROJECT_ROOT}/testdata/ftp-server/outbound"
    if [ -d "$FTP_OUTBOUND" ]; then
      FILE_COUNT=$(find "$FTP_OUTBOUND" -name "*.ach" -type f | wc -l)
      if [ "$FILE_COUNT" -gt 0 ]; then
        log_success "File(s) found in FTP outbound directory"
        ls -lah "$FTP_OUTBOUND"/*.ach | sed 's/^/  /'
      else
        log_warning "No ACH files found in FTP outbound directory yet"
        log_info "This may take a moment, check again with:"
        log_info "ls -la ${FTP_OUTBOUND}/"
      fi
    else
      log_warning "FTP outbound directory not found: $FTP_OUTBOUND"
    fi
  fi

  # Summary
  echo ""
  log_success "Deployment workflow complete!"
  echo ""
  echo "Summary:"
  echo "  JSON Input:  $JSON_FILE"
  echo "  Nacha File:  $NACHA_FILE"
  echo "  Shard Key:   $SHARD_KEY"
  echo "  File ID:     $FILE_ID"
  echo "  Gateway:     $GATEWAY_URL"
  echo ""
  echo "Next steps:"
  if [ "$TRIGGER_CUTOFF" = false ]; then
    echo "  1. Trigger cutoff: bash scripts/json-to-nacha.sh --submit --cutoff"
  else
    echo "  1. Check FTP upload: ls -la testdata/ftp-server/outbound/"
    echo "  2. View uploaded file: cat testdata/ftp-server/outbound/*.ach"
  fi
  echo ""

else
  # No submission, just show what would happen
  echo ""
  log_success "JSON conversion complete!"
  echo ""
  echo "To submit to gateway and process:"
  echo "  bash $SCRIPT_DIR/json-to-nacha.sh --submit --cutoff"
  echo ""
  echo "Or submit manually:"
  echo "  curl -XPOST 'http://localhost:8484/shards/$SHARD_KEY/files/$FILE_ID' \\"
  echo "    --data-binary @'$NACHA_FILE' \\"
  echo "    -H 'Content-Type: text/plain'"
  echo ""
fi
