#!/bin/bash
# Compare test results between Kamailio and Go SBC
# Usage: ./compare-backends.sh
set -e

cd "$(dirname "$0")/.."

echo "========================================="
echo "  Running tests with GO SBC"
echo "========================================="

# Ensure Go SBC is running (default compose)
docker compose -f docker-compose-e2e-telephony.yaml --env-file .env.e2e -p comcent-e2e-telephony up -d 2>&1 | tail -5
docker compose -f docker-compose-e2e-telephony.yaml --env-file .env.e2e -p comcent-e2e-telephony restart sipp sipp-uas sipp-agent-a sipp-agent-b freeswitch 2>&1 | tail -3
sleep 5

cd e2e
npx playwright test telephony/ --workers=1 --reporter=list 2>&1 | grep -E '^\s+(✓|✘|-)' > /tmp/sbc-results.txt
SBC_PASS=$(grep -c '✓' /tmp/sbc-results.txt || true)
SBC_FAIL=$(grep -c '✘' /tmp/sbc-results.txt || true)
SBC_SKIP=$(grep -c '\-' /tmp/sbc-results.txt || true)
cd ..

echo ""
echo "========================================="
echo "  Switching to KAMAILIO"
echo "========================================="

# Switch to Kamailio
docker compose -f docker-compose-e2e-telephony.yaml -f docker-compose-e2e-kamailio.yaml --env-file .env.e2e -p comcent-e2e-telephony up -d kamailio 2>&1 | tail -5
docker compose -f docker-compose-e2e-telephony.yaml --env-file .env.e2e -p comcent-e2e-telephony restart sipp sipp-uas sipp-agent-a sipp-agent-b freeswitch 2>&1 | tail -3
sleep 10  # Kamailio needs more startup time

echo "========================================="
echo "  Running tests with KAMAILIO"
echo "========================================="

cd e2e
npx playwright test telephony/ --workers=1 --reporter=list 2>&1 | grep -E '^\s+(✓|✘|-)' > /tmp/kamailio-results.txt
KAM_PASS=$(grep -c '✓' /tmp/kamailio-results.txt || true)
KAM_FAIL=$(grep -c '✘' /tmp/kamailio-results.txt || true)
KAM_SKIP=$(grep -c '\-' /tmp/kamailio-results.txt || true)
cd ..

# Switch back to Go SBC
docker compose -f docker-compose-e2e-telephony.yaml --env-file .env.e2e -p comcent-e2e-telephony up -d kamailio 2>&1 | tail -3

echo ""
echo "========================================="
echo "  COMPARISON"
echo "========================================="
echo ""
printf "%-40s %-10s %-10s\n" "Test" "Go SBC" "Kamailio"
printf "%-40s %-10s %-10s\n" "----" "------" "--------"

paste -d'|' /tmp/sbc-results.txt /tmp/kamailio-results.txt 2>/dev/null | while IFS='|' read -r sbc kam; do
  sbc_status=$(echo "$sbc" | grep -o '[✓✘-]' | head -1)
  kam_status=$(echo "$kam" | grep -o '[✓✘-]' | head -1)
  test_name=$(echo "$sbc" | sed 's/.*› //' | cut -c1-38)
  printf "%-40s %-10s %-10s\n" "$test_name" "$sbc_status" "$kam_status"
done

echo ""
echo "Summary:"
echo "  Go SBC:   $SBC_PASS passed, $SBC_FAIL failed, $SBC_SKIP skipped"
echo "  Kamailio: $KAM_PASS passed, $KAM_FAIL failed, $KAM_SKIP skipped"
