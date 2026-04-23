#!/usr/bin/env bash
# list.sh — Show all running Hermes agent instances
# Usage: ./scripts/list.sh

set -euo pipefail

echo "Hermes Agent Instances"
echo "======================="
echo ""

# Production instance
echo "🏠 Production (hermes namespace):"
kubectl get pods,svc,pvc -n hermes 2>/dev/null | head -20 || echo "  Not found"
echo ""

# Test instances (namespaces starting with hermes-)
TEST_NAMESPACES=$(kubectl get namespaces -o name 2>/dev/null | grep 'namespace/hermes-' | sed 's/namespace\///' || true)

if [ -n "$TEST_NAMESPACES" ]; then
  echo "🧪 Test instances:"
  for ns in $TEST_NAMESPACES; do
    echo "  ── $ns ──"
    kubectl get pods,svc,pvc -n "$ns" 2>/dev/null | sed 's/^/    /' || echo "    (empty)"
    echo ""
  done
else
  echo "🧪 No test instances running"
fi