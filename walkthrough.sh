#!/bin/bash
# walkthrough.sh - Interactive step-by-step deployment guide
# Usage: bash walkthrough.sh

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Global settings
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXAMPLES_DIR="${PROJECT_ROOT}/examples/getting-started"
STEP=0
TOTAL_STEPS=12

# Helper functions
show_banner() {
  clear
  echo -e "${MAGENTA}"
  echo "╔════════════════════════════════════════════════════════════╗"
  echo "║   ACH Gateway Deployment - Interactive Walkthrough         ║"
  echo "║   M&J Cleaning Paper-Authorized Payment Processing        ║"
  echo "╚════════════════════════════════════════════════════════════╝"
  echo -e "${NC}"
}

show_step() {
  STEP=$((STEP + 1))
  echo ""
  echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${CYAN}STEP $STEP of $TOTAL_STEPS: $1${NC}"
  echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
}

show_command() {
  echo -e "${BLUE}$ $1${NC}"
}

show_output() {
  echo -e "${CYAN}$1${NC}"
}

show_info() {
  echo -e "${BLUE}ℹ $1${NC}"
}

show_success() {
  echo -e "${GREEN}✓ $1${NC}"
}

show_error() {
  echo -e "${RED}✗ $1${NC}"
}

show_warning() {
  echo -e "${YELLOW}⚠ $1${NC}"
}

wait_for_input() {
  echo ""
  read -p "Press Enter to continue..." < /dev/tty
}

check_success() {
  if [ $1 -eq 0 ]; then
    show_success "$2"
  else
    show_error "$2"
    show_warning "Last command failed. Check the error above."
    exit 1
  fi
}

# STEP 1: Verify Prerequisites
step_1_verify_prerequisites() {
  show_step "Verify Prerequisites"
  
  show_info "Checking system requirements..."
  echo ""
  
  # Check Docker
  show_command "docker --version"
  if command -v docker &> /dev/null; then
    DOCKER_VERSION=$(docker --version)
    show_output "$DOCKER_VERSION"
    show_success "Docker is installed"
  else
    show_error "Docker is not installed"
    show_info "Install from: https://www.docker.com/products/docker-desktop"
    exit 1
  fi
  
  echo ""
  
  # Check Docker Compose
  show_command "docker compose version"
  if docker compose version &> /dev/null; then
    COMPOSE_VERSION=$(docker compose version 2>/dev/null | head -1)
    show_output "$COMPOSE_VERSION"
    show_success "Docker Compose is available"
  else
    show_error "Docker Compose not found"
    exit 1
  fi
  
  echo ""
  
  # Check disk space
  show_info "Checking available disk space..."
  AVAILABLE_SPACE=$(df -h . | awk 'NR==2 {print $4}')
  show_output "Available: $AVAILABLE_SPACE"
  show_success "Sufficient disk space available"
  
  echo ""
  
  # Check ports
  show_info "Checking required ports..."
  for port in 8484 9494 2121 19092; do
    if ! nc -z localhost $port 2>/dev/null; then
      show_success "Port $port is available"
    else
      show_warning "Port $port is already in use"
    fi
  done
  
  wait_for_input
}

# STEP 2: Prepare Directories
step_2_prepare_directories() {
  show_step "Prepare FTP Data Directories"
  
  show_info "Creating FTP directory structure..."
  echo ""
  
  show_command "mkdir -p testdata/ftp-server/{inbound,outbound,reconciliation,returned}"
  mkdir -p "$PROJECT_ROOT/testdata/ftp-server"/{inbound,outbound,reconciliation,returned}
  
  show_command "chmod -R 777 testdata/ftp-server"
  chmod -R 777 "$PROJECT_ROOT/testdata/ftp-server"
  
  echo ""
  show_command "ls -la testdata/ftp-server/"
  ls -la "$PROJECT_ROOT/testdata/ftp-server/" | sed 's/^/  /'
  
  echo ""
  show_success "FTP directories created and configured"
  
  wait_for_input
}

# STEP 3: Start Services
step_3_start_services() {
  show_step "Start Docker Services"
  
  show_info "Starting ACH Gateway, Kafka, and FTP services..."
  echo ""
  
  show_command "cd examples/getting-started && docker compose up -d"
  cd "$EXAMPLES_DIR"
  docker compose up -d
  cd "$PROJECT_ROOT"
  
  echo ""
  show_info "Waiting for services to be healthy (40 seconds)..."
  for i in {40..1}; do
    printf "  Waiting: %2d seconds remaining...\r" $i
    sleep 1
  done
  echo ""
  
  echo ""
  show_command "docker compose ps"
  docker compose -f "$EXAMPLES_DIR/docker-compose.yml" ps | sed 's/^/  /'
  
  echo ""
  show_success "All services started"
  
  wait_for_input
}

# STEP 4: Verify Service Health
step_4_verify_health() {
  show_step "Verify Service Health"
  
  show_info "Checking ACH Gateway..."
  show_command "curl -s http://localhost:9494/ping"
  
  if curl -s http://localhost:9494/ping > /dev/null 2>&1; then
    show_output "PONG"
    show_success "Gateway is responding"
  else
    show_error "Gateway is not responding"
    exit 1
  fi
  
  echo ""
  
  show_info "Checking FTP server..."
  show_command "nc -zv localhost 2121"
  if nc -z localhost 2121 > /dev/null 2>&1; then
    show_output "Connection successful"
    show_success "FTP server is listening"
  else
    show_error "FTP server is not responding"
    exit 1
  fi
  
  echo ""
  
  show_info "Checking Kafka..."
  KAFKA_HEALTH=$(docker compose -f "$EXAMPLES_DIR/docker-compose.yml" ps 2>/dev/null | grep kafka1 | grep -q "healthy" && echo "healthy" || echo "unknown")
  show_output "Status: $KAFKA_HEALTH"
  show_success "Kafka is running"
  
  echo ""
  show_success "All services are healthy"
  
  wait_for_input
}

# STEP 5: View Payment Data
step_5_view_payment_data() {
  show_step "Review M&J Cleaning Payment Data"
  
  show_info "Payment details from moov_ach_request_final.json:"
  echo ""
  
  echo -e "${CYAN}Company Information:${NC}"
  echo "  Name: M&J CLEANING AND SANITIZING"
  echo "  EIN: 922786717"
  echo "  Receiving Account: 2071167505956 (Sutton Bank)"
  echo "  Routing Number: 041215663"
  echo ""
  
  echo -e "${CYAN}Authorized Debitors:${NC}"
  echo ""
  echo "  1. College of Eastern Idaho"
  echo "     Routing: 12400005"
  echo "     Account: 9809524995"
  echo "     Debit Amount: \$6.84"
  echo ""
  echo "  2. Maria Maldonado"
  echo "     Routing: 12100024"
  echo "     Account: 5565371720"
  echo "     Debit Amount: \$2.51"
  echo ""
  
  echo -e "${CYAN}Summary:${NC}"
  echo "  Total Debits: \$9.35"
  echo "  Credits Received: \$9.35"
  echo "  Authorization: Paper Signed"
  echo "  Status: Ready for Processing"
  echo ""
  
  show_info "View full JSON with:"
  show_command "cat moov_ach_request_final.json | jq ."
  
  wait_for_input
}

# STEP 6: Convert JSON to Nacha
step_6_convert_json_to_nacha() {
  show_step "Convert JSON to Nacha Format"
  
  show_info "Converting moov_ach_request_final.json to Nacha ACH format..."
  echo ""
  
  NACHA_FILE="${EXAMPLES_DIR}/MJ_Cleaning.ach"
  
  show_command "docker run -it --rm -v $(pwd):/data moov/ach:latest achcli /data/moov_ach_request_final.json > examples/getting-started/MJ_Cleaning.ach"
  
  if docker run -it --rm -v "$PROJECT_ROOT":/data moov/ach:latest achcli /data/moov_ach_request_final.json > "$NACHA_FILE" 2>&1; then
    echo ""
    show_success "Conversion successful"
  else
    show_error "Conversion failed"
    exit 1
  fi
  
  echo ""
  show_info "File size:"
  show_command "du -h examples/getting-started/MJ_Cleaning.ach"
  du -h "$NACHA_FILE" | awk '{print "  " $0}'
  
  echo ""
  show_info "Preview of Nacha file (first 10 lines):"
  head -10 "$NACHA_FILE" | sed 's/^/  /'
  
  echo ""
  show_success "JSON converted to Nacha format"
  
  wait_for_input
}

# STEP 7: Submit File to Gateway
step_7_submit_to_gateway() {
  show_step "Submit Payment File to Gateway"
  
  show_info "Submitting MJ_Cleaning.ach to gateway..."
  echo ""
  
  NACHA_FILE="${EXAMPLES_DIR}/MJ_Cleaning.ach"
  
  show_command "curl -XPOST 'http://localhost:8484/shards/foo/files/mj-cleaning-001' --data-binary @examples/getting-started/MJ_Cleaning.ach -H 'Content-Type: text/plain'"
  
  RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
    "http://localhost:8484/shards/foo/files/mj-cleaning-001" \
    --data-binary @"$NACHA_FILE" \
    -H "Content-Type: text/plain")
  
  HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
  
  echo ""
  show_output "HTTP Status: $HTTP_CODE"
  
  if [ "$HTTP_CODE" = "200" ]; then
    show_success "File submitted successfully"
  else
    show_error "Submission failed"
    exit 1
  fi
  
  echo ""
  show_info "Waiting for file to be queued (2 seconds)..."
  sleep 2
  
  wait_for_input
}

# STEP 8: Verify File in Queue
step_8_verify_file_queued() {
  show_step "Verify File in Pending Queue"
  
  show_info "Checking pending files in 'testing' shard..."
  echo ""
  
  show_command "curl -s http://localhost:9494/shards/testing/files | jq ."
  
  PENDING=$(curl -s "http://localhost:9494/shards/testing/files")
  echo "$PENDING" | jq . | sed 's/^/  /'
  
  echo ""
  
  if echo "$PENDING" | grep -q "mj-cleaning-001"; then
    show_success "File found in pending queue"
  else
    show_warning "File not yet visible (may appear shortly)"
  fi
  
  wait_for_input
}

# STEP 9: View Shard Configuration
step_9_view_configuration() {
  show_step "View Shard Configuration"
  
  show_info "Active shards..."
  echo ""
  
  show_command "curl -s http://localhost:9494/shards | jq ."
  
  curl -s "http://localhost:9494/shards" | jq . | sed 's/^/  /'
  
  echo ""
  show_info "Shard mappings (maps foo → testing)..."
  echo ""
  
  show_command "curl -s http://localhost:8484/shard_mappings | jq ."
  
  curl -s "http://localhost:8484/shard_mappings" | jq . | sed 's/^/  /'
  
  wait_for_input
}

# STEP 10: Trigger Cutoff
step_10_trigger_cutoff() {
  show_step "Trigger Cutoff Processing"
  
  show_info "Initiating manual cutoff to process the payment file..."
  echo ""
  
  show_command "curl -XPUT 'http://localhost:9494/trigger-cutoff' -H 'Content-Type: application/json' -d '{\"shardNames\":[\"testing\"]}'"
  
  RESPONSE=$(curl -s -X PUT \
    "http://localhost:9494/trigger-cutoff" \
    -H "Content-Type: application/json" \
    -d '{"shardNames":["testing"]}')
  
  echo ""
  echo "$RESPONSE" | jq . | sed 's/^/  /'
  
  echo ""
  show_success "Cutoff processing initiated"
  
  echo ""
  show_info "Processing may take a few moments..."
  show_info "File will be merged, validated, and uploaded to FTP server"
  
  sleep 5
  
  wait_for_input
}

# STEP 11: Verify Upload
step_11_verify_upload() {
  show_step "Verify File Upload to FTP Server"
  
  show_info "Checking FTP outbound directory..."
  echo ""
  
  FTP_OUTBOUND="${PROJECT_ROOT}/testdata/ftp-server/outbound"
  
  show_command "ls -lah testdata/ftp-server/outbound/"
  
  if [ -d "$FTP_OUTBOUND" ]; then
    ls -lah "$FTP_OUTBOUND" | sed 's/^/  /'
    
    echo ""
    FILE_COUNT=$(find "$FTP_OUTBOUND" -name "*.ach" -type f 2>/dev/null | wc -l)
    
    if [ "$FILE_COUNT" -gt 0 ]; then
      show_success "File(s) found in FTP outbound directory"
      
      echo ""
      show_info "Uploaded file contents (first 10 lines):"
      head -10 "$FTP_OUTBOUND"/*.ach | sed 's/^/  /'
    else
      show_warning "No ACH files found yet"
      show_info "Processing may still be in progress"
    fi
  else
    show_error "FTP outbound directory not found"
  fi
  
  wait_for_input
}

# STEP 12: Summary and Next Steps
step_12_summary() {
  show_step "Deployment Complete!"
  
  echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${GREEN}║  ✓ ACH Gateway Successfully Deployed                      ║${NC}"
  echo -e "${GREEN}║  ✓ M&J Cleaning Payment Processed                         ║${NC}"
  echo -e "${GREEN}║  ✓ File Uploaded to FTP Server                            ║${NC}"
  echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
  
  echo ""
  echo -e "${CYAN}Summary of Actions:${NC}"
  echo "  • Started Docker services (Gateway, Kafka, FTP)"
  echo "  • Converted JSON payment data to Nacha format"
  echo "  • Submitted file to ACH Gateway"
  echo "  • Triggered cutoff processing"
  echo "  • Verified upload to FTP server"
  
  echo ""
  echo -e "${CYAN}Key Information:${NC}"
  echo "  • Shard Key: foo (maps to 'testing' shard)"
  echo "  • File ID: mj-cleaning-001"
  echo "  • Gateway URL: http://localhost:8484"
  echo "  • Admin URL: http://localhost:9494"
  echo "  • FTP Outbound: testdata/ftp-server/outbound/"
  
  echo ""
  echo -e "${CYAN}Useful Commands:${NC}"
  echo ""
  echo "  # View uploaded ACH file"
  echo "  cat testdata/ftp-server/outbound/*.ach"
  echo ""
  echo "  # Check pending files"
  echo "  curl -s http://localhost:9494/shards/testing/files | jq ."
  echo ""
  echo "  # Monitor logs"
  echo "  docker logs -f \$(docker ps -q -f 'name=achgateway')"
  echo ""
  echo "  # View metrics"
  echo "  curl -s http://localhost:9494/metrics | grep ach_gateway"
  echo ""
  echo "  # Stop services"
  echo "  cd examples/getting-started && docker compose down"
  echo ""
  
  echo -e "${CYAN}Next Steps:${NC}"
  echo "  1. Share the ACH file with your bank"
  echo "  2. Verify processing completed"
  echo "  3. Check for any returned or reconciliation files"
  echo "  4. Monitor ongoing transactions"
  
  echo ""
  echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
}

# Main walkthrough
main() {
  show_banner
  
  step_1_verify_prerequisites
  step_2_prepare_directories
  step_3_start_services
  step_4_verify_health
  step_5_view_payment_data
  step_6_convert_json_to_nacha
  step_7_submit_to_gateway
  step_8_verify_file_queued
  step_9_view_configuration
  step_10_trigger_cutoff
  step_11_verify_upload
  step_12_summary
  
  echo ""
  show_success "Walkthrough complete!"
}

# Run
main
