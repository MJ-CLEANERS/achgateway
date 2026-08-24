#!/bin/bash
# quick-start.sh - One-command ACH Gateway deployment
# Usage: bash quick-start.sh

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║        ACH Gateway - Quick Start Deployment               ║"
echo "║        M&J Cleaning Paper-Authorized Debit Processing     ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Check prerequisites
echo "Checking prerequisites..."
if ! command -v docker &> /dev/null; then
    echo "❌ Docker not installed. Please install Docker Desktop."
    exit 1
fi
echo "✓ Docker installed"

if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null 2>&1; then
    echo "❌ Docker Compose not installed."
    exit 1
fi
echo "✓ Docker Compose available"

echo ""
echo "Starting ACH Gateway deployment..."
echo ""

# Run the full deployment
bash "$PROJECT_ROOT/deploy-achgateway.sh" --full --cleanup

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  ✓ ACH Gateway deployment complete!                       ║"
echo "║  ✓ M&J Cleaning payment file has been processed           ║"
echo "║  ✓ File is uploaded to FTP server                         ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "💡 To view the uploaded ACH file:"
echo "   cat testdata/ftp-server/outbound/*.ach"
echo ""
echo "💡 To check payment details:"
echo "   curl -s http://localhost:9494/shards/testing/files | jq ."
echo ""
echo "💡 To stop services:"
echo "   cd examples/getting-started && docker compose down"
echo ""
