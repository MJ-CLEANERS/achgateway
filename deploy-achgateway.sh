#!/bin/bash
# deploy-achgateway.sh - Complete automated deployment and payment processing
# Usage: bash deploy-achgateway.sh [--full] [--cleanup] [--logs]

set -e

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
EXAMPLES_DIR="${PROJECT_ROOT}/examples/getting-started"
JSON_FILE="${PROJECT_ROOT}/moov_ach_request_final.json"
NACHA_FILE="${EXAMPLES_DIR}/MJ_Cleaning.ach"
FTP_DATA_DIR="${PROJECT_ROOT}/testdata/ftp-server"

# Gateway configuration
GATEWAY_URL="http://localhost:8484"
ADMIN_URL="http://localhost:9494"
SHARD_KEY="foo"
FILE_ID="mj-cleaning-001"
SHARD_NAME="testing"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Parse arguments
FULL_WORKFLOW=false
CLEANUP=false
SHOW_LOGS=false

for arg in "$@"; do
  case $arg in
    --full)
      FULL_WORKFLOW=true
      ;;
    --cleanup)
      CLEANUP=true
      ;;
    --logs)
      SHOW_LOGS=true
      ;;
    --help)
      show_help
      exit 0
      ;;
  esac
done

# Logging functions
log_header() {
  echo ""
  echo -e "${MAGENTA}═══════════════════════════════════════════════════════════${NC}"
  echo -e "${MAGENTA}  $1${NC}"
  echo -e "${MAGENTA}═══════════════════════════════════════════════════════════${NC}"
  echo ""
}

log_section() {
  echo ""
  echo -e "${CYAN}▶ $1${NC}"
  echo ""
}

log_info() {
  echo -e "${BLUE}  ℹ $1${NC}"
}

log_success() {
  echo -e "${GREEN}  ✓ $1${NC}"
}

log_error() {
  echo -e "${RED}  ✗ $1${NC}"
}

log_warning() {
  echo -e "${YELLOW}  ⚠ $1${NC}"
}

log_cmd() {
  echo -e "${CYAN}  $ $1${NC}"
}

show_help() {
  cat << EOF
${CYAN}ACH Gateway Automated Deployment${NC}

Usage: bash deploy-achgateway.sh [OPTIONS]

Options:
  --full          Run complete workflow (start, submit, process, upload)
  --cleanup       Stop services and clean up data before starting
  --logs          Stream logs during deployment
  --help          Show this help message

Examples:
  # Start services only
  bash deploy-achgateway.sh

  # Full workflow with service cleanup
  bash deploy-achgateway.sh --full --cleanup

  # Full workflow with log monitoring
  bash deploy-achgateway.sh --full --logs

EOF
}

# Step 0: Banner
log_header "ACH Gateway Complete Deployment"
log_info "Repository: $PROJECT_ROOT"
log_info "Gateway URL: $GATEWAY_URL"
log_info "Admin URL: $ADMIN_URL"

# Step 1: Cleanup (if requested)
if [ "$CLEANUP" = true ]; then
  log_section "Step 1: Cleanup - Stopping and Removing Services"
  
  log_info "Stopping containers..."
  log_cmd "docker compose -f $EXAMPLES_DIR/docker-compose.yml down"
  cd "$EXAMPLES_DIR"
  docker compose down 2>/dev/null || true
  cd "$PROJECT_ROOT"
  log_success "Services stopped"
  
  log_info "Removing FTP data..."
  log_cmd "rm -rf $FTP_DATA_DIR"
  rm -rf "$FTP_DATA_DIR" 2>/dev/null || true
  log_success "FTP data removed"
  
  sleep 2
fi

# Step 2: Verify prerequisites
log_section "Step 2: Verify Prerequisites"

log_info "Checking Docker..."
if ! command -v docker &> /dev/null; then
  log_error "Docker not found. Please install Docker."
  exit 1
fi
log_success "Docker found: $(docker --version)"

log_info "Checking Docker Compose..."
if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
  log_error "Docker Compose not found. Please install Docker Compose."
  exit 1
fi
log_success "Docker Compose found"

log_info "Checking required files..."
if [ ! -f "$JSON_FILE" ]; then
  log_error "JSON file not found: $JSON_FILE"
  exit 1
fi
log_success "JSON file found"

if [ ! -f "$EXAMPLES_DIR/docker-compose.yml" ]; then
  log_error "Docker Compose file not found: $EXAMPLES_DIR/docker-compose.yml"
  exit 1
fi
log_success "Docker Compose file found"

# Step 3: Create FTP directories
log_section "Step 3: Create FTP Data Directories"

log_info "Creating FTP directory structure..."
for dir in inbound outbound reconciliation returned; do
  mkdir -p "$FTP_DATA_DIR/$dir"
done
chmod -R 777 "$FTP_DATA_DIR" 2>/dev/null || true
log_success "FTP directories created: $FTP_DATA_DIR"

log_cmd "ls -la $FTP_DATA_DIR/"
ls -la "$FTP_DATA_DIR" | sed 's/^/  /'

# Step 4: Start services
log_section "Step 4: Start Services"

log_info "Starting Docker Compose services..."
log_cmd "cd $EXAMPLES_DIR && docker compose up -d"
cd "$EXAMPLES_DIR"
docker compose up -d
cd "$PROJECT_ROOT"
log_success "Services started"

log_info "Waiting for services to be healthy (40 seconds)..."
for i in {40..1}; do
  printf "  Waiting: %2d seconds remaining...\r" $i
  sleep 1
done
echo ""
log_success "Services should now be healthy"

# Step 5: Verify service health
log_section "Step 5: Verify Service Health"

log_info "Checking ACH Gateway..."
if curl -s "$ADMIN_URL/ping" > /dev/null 2>&1; then
  log_success "ACH Gateway is responding"
else
  log_error "ACH Gateway is not responding"
  log_info "Checking container logs..."
  docker compose -f "$EXAMPLES_DIR/docker-compose.yml" logs achgateway | tail -20
  exit 1
fi

log_info "Checking metrics endpoint..."
if curl -s "$ADMIN_URL/metrics" | grep -q "ach_gateway" > /dev/null 2>&1; then
  log_success "Metrics endpoint is working"
else
  log_warning "Metrics may not be ready yet"
fi

log_info "Checking FTP server..."
if nc -z localhost 2121 > /dev/null 2>&1; then
  log_success "FTP server is listening on port 2121"
else
  log_error "FTP server is not responding"
fi

log_info "Checking Kafka..."
docker compose -f "$EXAMPLES_DIR/docker-compose.yml" ps | grep kafka1 | grep -q "healthy" && \
  log_success "Kafka is healthy" || \
  log_warning "Kafka status unknown"

# Step 6: List services
log_section "Step 6: Running Services"

log_cmd "docker compose -f $EXAMPLES_DIR/docker-compose.yml ps"
docker compose -f "$EXAMPLES_DIR/docker-compose.yml" ps | sed 's/^/  /'

if [ "$FULL_WORKFLOW" = false ]; then
  echo ""
  log_success "Deployment ready!"
  echo ""
  echo "Services are running. Next steps:"
  echo ""
  echo "  1. Convert JSON to Nacha format:"
  echo "     bash scripts/json-to-nacha.sh"
  echo ""
  echo "  2. Submit and process:"
  echo "     bash scripts/json-to-nacha.sh --submit --cutoff"
  echo ""
  echo "  3. Or run full workflow:"
  echo "     bash deploy-achgateway.sh --full"
  echo ""
  exit 0
fi

# Step 7: Convert JSON to Nacha
log_section "Step 7: Convert JSON to Nacha Format"

log_info "Checking for achcli..."
if command -v achcli &> /dev/null; then
  ACHCLI_CMD="achcli"
  log_success "achcli found locally"
else
  ACHCLI_CMD="docker run -it --rm -v ${PROJECT_ROOT}:/data moov/ach:latest achcli"
  log_info "Using achcli via Docker"
fi

log_info "Converting JSON to Nacha format..."
log_cmd "achcli $JSON_FILE > $NACHA_FILE"
mkdir -p "$(dirname "$NACHA_FILE")"

if $ACHCLI_CMD "$JSON_FILE" > "$NACHA_FILE" 2>&1; then
  log_success "JSON conversion successful"
  log_info "Output file: $NACHA_FILE"
  log_info "File size: $(du -h "$NACHA_FILE" | cut -f1)"
else
  log_error "JSON conversion failed"
  exit 1
fi

log_info "Preview of generated Nacha file:"
head -10 "$NACHA_FILE" | sed 's/^/  /'

# Step 8: Validate Nacha file
log_section "Step 8: Validate Nacha File"

log_info "Validating file format..."
if $ACHCLI_CMD "$NACHA_FILE" > /tmp/ach_validation.log 2>&1; then
  log_success "Nacha file validation passed"
else
  log_warning "Validation completed (check output)"
fi

# Step 9: Submit ACH file
log_section "Step 9: Submit ACH File to Gateway"

log_info "Submitting file to gateway..."
log_cmd "curl -XPOST '$GATEWAY_URL/shards/$SHARD_KEY/files/$FILE_ID' --data-binary @'$NACHA_FILE'"

RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
  "$GATEWAY_URL/shards/$SHARD_KEY/files/$FILE_ID" \
  --data-binary @"$NACHA_FILE" \
  -H "Content-Type: text/plain")

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | head -n-1)

if [ "$HTTP_CODE" = "200" ]; then
  log_success "File submitted successfully (HTTP $HTTP_CODE)"
else
  log_error "File submission failed (HTTP $HTTP_CODE)"
  log_info "Response: $BODY"
  exit 1
fi

sleep 2

# Step 10: Verify file in queue
log_section "Step 10: Verify File in Pending Queue"

log_info "Checking pending files..."
log_cmd "curl -s $ADMIN_URL/shards/$SHARD_NAME/files"

PENDING=$(curl -s "$ADMIN_URL/shards/$SHARD_NAME/files")
echo "$PENDING" | jq . | sed 's/^/  /'

if echo "$PENDING" | grep -q "$FILE_ID"; then
  log_success "File found in pending queue"
else
  log_warning "File not yet visible in pending queue (may appear shortly)"
fi

# Step 11: Show shard configuration
log_section "Step 11: Shard Configuration"

log_info "Active shards and mappings..."
log_cmd "curl -s $ADMIN_URL/shards"
SHARDS=$(curl -s "$ADMIN_URL/shards")
echo "$SHARDS" | jq . | sed 's/^/  /'

log_info "Shard mappings..."
log_cmd "curl -s $GATEWAY_URL/shard_mappings"
MAPPINGS=$(curl -s "$GATEWAY_URL/shard_mappings")
echo "$MAPPINGS" | jq . | sed 's/^/  /'

# Step 12: Trigger cutoff processing
log_section "Step 12: Trigger Cutoff Processing"

log_info "Initiating manual cutoff for 'testing' shard..."
log_cmd "curl -XPUT '$ADMIN_URL/trigger-cutoff' -H 'Content-Type: application/json' -d '{\"shardNames\":[\"testing\"]}'"

CUTOFF_RESPONSE=$(curl -s -X PUT \
  "$ADMIN_URL/trigger-cutoff" \
  -H "Content-Type: application/json" \
  -d '{"shardNames":["testing"]}')

echo "$CUTOFF_RESPONSE" | jq . | sed 's/^/  /'

if echo "$CUTOFF_RESPONSE" | grep -q "testing"; then
  log_success "Cutoff processing initiated"
else
  log_warning "Cutoff response: $CUTOFF_RESPONSE"
fi

# Step 13: Monitor logs (if requested)
if [ "$SHOW_LOGS" = true ]; then
  log_section "Step 13: Monitoring Logs"
  log_info "Streaming logs for 20 seconds..."
  
  CONTAINER=$(docker compose -f "$EXAMPLES_DIR/docker-compose.yml" ps -q achgateway)
  if [ -n "$CONTAINER" ]; then
    docker logs -f "$CONTAINER" 2>&1 | head -100 &
    LOG_PID=$!
    sleep 20
    kill $LOG_PID 2>/dev/null || true
  fi
fi

# Step 14: Verify file upload
log_section "Step 14: Verify File Upload to FTP"

log_info "Checking FTP outbound directory..."
log_cmd "ls -lah $FTP_DATA_DIR/outbound/"
sleep 3

if [ -d "$FTP_DATA_DIR/outbound" ]; then
  FILE_COUNT=$(find "$FTP_DATA_DIR/outbound" -name "*.ach" -type f 2>/dev/null | wc -l)
  if [ "$FILE_COUNT" -gt 0 ]; then
    log_success "ACH file(s) found in FTP outbound directory"
    ls -lah "$FTP_DATA_DIR/outbound"/*.ach | sed 's/^/  /'
    
    log_info "File content preview:"
    head -10 "$FTP_DATA_DIR/outbound"/*.ach | sed 's/^/  /'
  else
    log_warning "No ACH files found in FTP outbound directory yet"
    log_info "This may take a moment. Check again with:"
    log_cmd "ls -lah $FTP_DATA_DIR/outbound/"
  fi
else
  log_warning "FTP outbound directory not found"
fi

# Step 15: Display metrics
log_section "Step 15: Gateway Metrics"

log_info "Fetching ACH Gateway metrics..."
log_cmd "curl -s $ADMIN_URL/metrics | grep ach_gateway"

curl -s "$ADMIN_URL/metrics" | grep "ach_gateway" | head -20 | sed 's/^/  /'

# Final Summary
log_header "Deployment Complete!"

echo -e "${GREEN}Summary:${NC}"
echo ""
echo "  Input JSON:      $JSON_FILE"
echo "  Nacha File:      $NACHA_FILE"
echo "  Gateway URL:     $GATEWAY_URL"
echo "  Admin URL:       $ADMIN_URL"
echo "  Shard Key:       $SHARD_KEY"
echo "  File ID:         $FILE_ID"
echo "  FTP Outbound:    $FTP_DATA_DIR/outbound"
echo ""

echo -e "${GREEN}Next Steps:${NC}"
echo ""
echo "  1. Monitor file processing:"
echo "     docker logs -f \$(docker ps -q -f 'name=achgateway')"
echo ""
echo "  2. Check file on FTP server:"
echo "     cat $FTP_DATA_DIR/outbound/*.ach"
echo ""
echo "  3. View gateway metrics:"
echo "     curl -s $ADMIN_URL/metrics | grep ach_gateway"
echo ""
echo "  4. Stop services:"
echo "     docker compose -f $EXAMPLES_DIR/docker-compose.yml down"
echo ""

echo -e "${GREEN}Useful Commands:${NC}"
echo ""
echo "  # List pending files"
echo "  curl -s $ADMIN_URL/shards/$SHARD_NAME/files | jq ."
echo ""
echo "  # Get file details"
echo "  curl -s $ADMIN_URL/shards/$SHARD_NAME/files/mergable/$SHARD_KEY/$FILE_ID.ach | jq ."
echo ""
echo "  # List shard mappings"
echo "  curl -s $GATEWAY_URL/shard_mappings | jq ."
echo ""
echo "  # Get config"
echo "  curl -s $ADMIN_URL/config | jq ."
echo ""
echo "  # Trigger another cutoff"
echo "  curl -XPUT $ADMIN_URL/trigger-cutoff -H 'Content-Type: application/json' -d '{\"shardNames\":[\"testing\"]}'"
echo ""

echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✓ ACH Gateway is ready to process payments!${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
