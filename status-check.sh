#!/bin/bash
# status-check.sh - Monitor and troubleshoot ACH Gateway deployment
# Usage: bash status-check.sh [--watch] [--logs] [--debug]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"
EXAMPLES_DIR="${PROJECT_ROOT}/examples/getting-started"
FTP_DATA_DIR="${PROJECT_ROOT}/testdata/ftp-server"

GATEWAY_URL="http://localhost:8484"
ADMIN_URL="http://localhost:9494"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Parse arguments
WATCH_MODE=false
SHOW_LOGS=false
DEBUG_MODE=false

for arg in "$@"; do
  case $arg in
    --watch)
      WATCH_MODE=true
      ;;
    --logs)
      SHOW_LOGS=true
      ;;
    --debug)
      DEBUG_MODE=true
      ;;
    --help)
      echo "Usage: bash status-check.sh [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --watch   Continuous monitoring (updates every 5 seconds)"
      echo "  --logs    Stream container logs"
      echo "  --debug   Show detailed debug information"
      echo "  --help    Show this help message"
      exit 0
      ;;
  esac
done

# Status check functions
check_docker() {
  if command -v docker &> /dev/null; then
    echo -e "${GREEN}✓${NC} Docker: $(docker --version | cut -d' ' -f3 | cut -d',' -f1)"
    return 0
  else
    echo -e "${RED}✗${NC} Docker not found"
    return 1
  fi
}

check_services() {
  echo -e "\n${CYAN}Container Status:${NC}"
  
  if [ ! -f "$EXAMPLES_DIR/docker-compose.yml" ]; then
    echo -e "${RED}✗${NC} docker-compose.yml not found"
    return 1
  fi

  docker compose -f "$EXAMPLES_DIR/docker-compose.yml" ps 2>/dev/null | tail -n +2 | while read line; do
    if echo "$line" | grep -q "Up"; then
      echo -e "${GREEN}✓${NC} $line"
    else
      echo -e "${RED}✗${NC} $line"
    fi
  done
}

check_gateway() {
  echo -e "\n${CYAN}ACH Gateway Health:${NC}"
  
  if curl -s "$ADMIN_URL/ping" > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} Gateway responding at $ADMIN_URL"
    
    # Get version if available
    VERSION=$(curl -s "$ADMIN_URL/metrics" 2>/dev/null | grep "achgateway_info" | head -1 | sed 's/.*version="\([^"]*\)".*/\1/' || echo "unknown")
    echo -e "  Version: $VERSION"
    
    return 0
  else
    echo -e "${RED}✗${NC} Gateway not responding at $ADMIN_URL"
    return 1
  fi
}

check_ftp() {
  echo -e "\n${CYAN}FTP Server Status:${NC}"
  
  if nc -z localhost 2121 > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} FTP listening on port 2121"
  else
    echo -e "${RED}✗${NC} FTP not responding on port 2121"
    return 1
  fi
}

check_kafka() {
  echo -e "\n${CYAN}Kafka Status:${NC}"
  
  KAFKA_STATUS=$(docker compose -f "$EXAMPLES_DIR/docker-compose.yml" ps 2>/dev/null | grep kafka1)
  
  if echo "$KAFKA_STATUS" | grep -q "healthy"; then
    echo -e "${GREEN}✓${NC} Kafka is healthy"
  elif echo "$KAFKA_STATUS" | grep -q "Up"; then
    echo -e "${YELLOW}⚠${NC} Kafka is up but health status unknown"
  else
    echo -e "${RED}✗${NC} Kafka is not running"
    return 1
  fi
}

check_pending_files() {
  echo -e "\n${CYAN}Pending Files:${NC}"
  
  PENDING=$(curl -s "$ADMIN_URL/shards/testing/files" 2>/dev/null)
  
  if [ -z "$PENDING" ] || echo "$PENDING" | grep -q "error"; then
    echo -e "${YELLOW}⚠${NC} Unable to retrieve pending files"
    return 1
  fi
  
  FILE_COUNT=$(echo "$PENDING" | jq '.files | length' 2>/dev/null || echo "0")
  
  if [ "$FILE_COUNT" -gt 0 ]; then
    echo -e "${GREEN}✓${NC} $FILE_COUNT file(s) pending"
    echo "$PENDING" | jq '.files[]' 2>/dev/null | sed 's/^/  /'
  else
    echo -e "${YELLOW}ℹ${NC} No pending files"
  fi
}

check_ftp_outbound() {
  echo -e "\n${CYAN}FTP Outbound Directory:${NC}"
  
  if [ ! -d "$FTP_DATA_DIR/outbound" ]; then
    echo -e "${YELLOW}⚠${NC} Outbound directory not found"
    return 1
  fi
  
  FILE_COUNT=$(find "$FTP_DATA_DIR/outbound" -name "*.ach" -type f 2>/dev/null | wc -l)
  
  if [ "$FILE_COUNT" -gt 0 ]; then
    echo -e "${GREEN}✓${NC} $FILE_COUNT ACH file(s) in outbound"
    ls -lh "$FTP_DATA_DIR/outbound"/*.ach 2>/dev/null | sed 's/^/  /'
  else
    echo -e "${YELLOW}ℹ${NC} No ACH files in outbound directory"
  fi
}

check_shard_mappings() {
  echo -e "\n${CYAN}Shard Configuration:${NC}"
  
  MAPPINGS=$(curl -s "$GATEWAY_URL/shard_mappings" 2>/dev/null)
  
  if echo "$MAPPINGS" | jq . > /dev/null 2>&1; then
    COUNT=$(echo "$MAPPINGS" | jq 'length' 2>/dev/null || echo "0")
    echo -e "${GREEN}✓${NC} $COUNT shard mapping(s) configured"
    
    if [ "$DEBUG_MODE" = true ]; then
      echo "$MAPPINGS" | jq . | sed 's/^/  /'
    fi
  else
    echo -e "${RED}✗${NC} Unable to retrieve shard mappings"
  fi
}

check_metrics() {
  echo -e "\n${CYAN}Gateway Metrics:${NC}"
  
  METRICS=$(curl -s "$ADMIN_URL/metrics" 2>/dev/null | grep "ach_gateway" | head -10)
  
  if [ -z "$METRICS" ]; then
    echo -e "${YELLOW}⚠${NC} No metrics available yet"
  else
    echo -e "${GREEN}✓${NC} Metrics available"
    
    if [ "$DEBUG_MODE" = true ]; then
      echo "$METRICS" | sed 's/^/  /'
    fi
  fi
}

check_container_logs() {
  echo -e "\n${CYAN}Recent Container Logs:${NC}"
  
  CONTAINER=$(docker compose -f "$EXAMPLES_DIR/docker-compose.yml" ps -q achgateway 2>/dev/null)
  
  if [ -z "$CONTAINER" ]; then
    echo -e "${RED}✗${NC} ACH Gateway container not found"
    return 1
  fi
  
  echo -e "${BLUE}Last 20 log lines:${NC}"
  docker logs --tail 20 "$CONTAINER" 2>/dev/null | sed 's/^/  /' || echo -e "${RED}✗${NC} Unable to retrieve logs"
}

show_quick_commands() {
  echo -e "\n${CYAN}Quick Commands:${NC}"
  echo ""
  echo "  # View pending files"
  echo "  curl -s $ADMIN_URL/shards/testing/files | jq ."
  echo ""
  echo "  # Trigger cutoff manually"
  echo "  curl -XPUT $ADMIN_URL/trigger-cutoff -H 'Content-Type: application/json' -d '{\"shardNames\":[\"testing\"]}'"
  echo ""
  echo "  # Monitor logs"
  echo "  docker logs -f \$(docker ps -q -f 'name=achgateway')"
  echo ""
  echo "  # Stop services"
  echo "  cd $EXAMPLES_DIR && docker compose down"
  echo ""
  echo "  # View FTP outbound files"
  echo "  ls -lah $FTP_DATA_DIR/outbound/"
  echo ""
  echo "  # Validate ACH file"
  echo "  docker run -it --rm -v $PROJECT_ROOT:/data moov/ach:latest achcli /data/testdata/ftp-server/outbound/*.ach"
  echo ""
}

perform_check() {
  clear
  
  echo -e "${MAGENTA}╔════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${MAGENTA}║  ACH Gateway Status Check${NC}"
  echo -e "${MAGENTA}║  $(date '+%Y-%m-%d %H:%M:%S')${NC}"
  echo -e "${MAGENTA}╚════════════════════════════════════════════════════════════╝${NC}"
  
  # Run checks
  check_docker || true
  check_services || true
  check_gateway || true
  check_ftp || true
  check_kafka || true
  check_pending_files || true
  check_ftp_outbound || true
  check_shard_mappings || true
  check_metrics || true
  
  if [ "$SHOW_LOGS" = true ]; then
    check_container_logs || true
  fi
  
  show_quick_commands
  
  if [ "$WATCH_MODE" = true ]; then
    echo ""
    echo -e "${CYAN}Refreshing in 5 seconds (Press Ctrl+C to stop)...${NC}"
    sleep 5
    perform_check
  fi
}

# Run the check
perform_check
