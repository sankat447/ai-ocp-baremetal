#!/bin/bash
#
# AITP Agentic AI - Demo Test Script
# Run this to test the agent capabilities
#

echo "=============================================="
echo "AITP Agentic AI - Demo Tests"
echo "=============================================="

PORTKEY_URL="https://llm-gateway.apps.ocp419.crucible.iisl.com"
N8N_URL="https://workflows.apps.ocp419.crucible.iisl.com"
OPENAI_API_KEY="${OPENAI_API_KEY:-your-api-key-here}"

echo ""
echo "=== Test 1: Portkey Gateway Health Check ==="
curl -s $PORTKEY_URL
echo ""
echo ""

echo "=== Test 2: RAG Knowledge Search ==="
echo "Query: 'What is the password policy?'"
curl -s -X POST "$N8N_URL/webhook/rag-search" \
  -H "Content-Type: application/json" \
  -d '{
    "query": "What is the password policy?",
    "max_results": 3
  }' | python3 -m json.tool 2>/dev/null || cat
echo ""

echo "=== Test 3: Create Support Ticket ==="
curl -s -X POST "$N8N_URL/webhook/create-ticket" \
  -H "Content-Type: application/json" \
  -d '{
    "title": "Demo Test Ticket",
    "description": "This is a test ticket created during the demo",
    "priority": "low",
    "category": "IT",
    "requester_email": "demo@example.com"
  }' | python3 -m json.tool 2>/dev/null || cat
echo ""

echo "=== Test 4: LLM Chat Completion (via Portkey) ==="
curl -s -X POST "$PORTKEY_URL/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -d '{
    "model": "gpt-3.5-turbo",
    "messages": [
      {"role": "user", "content": "Say hello and confirm you are working!"}
    ],
    "max_tokens": 50
  }' | python3 -m json.tool 2>/dev/null || cat
echo ""

echo "=== Test 5: Database Verification ==="
echo "PostgreSQL Documents:"
oc exec -it $(oc get pods -n aitp-data -l postgres-operator.crunchydata.com/role=master -o jsonpath='{.items[0].metadata.name}') -n aitp-data -c database -- psql -U postgres -d knowledge_base -c "SELECT id, title FROM documents;" 2>/dev/null

echo ""
echo "MongoDB Tickets:"
oc exec -it aitp-mongodb-cluster-0 -n aitp-data -- mongo agent_memory --quiet --eval "db.tickets.find().limit(3).toArray()" 2>/dev/null

echo ""
echo "=============================================="
echo "Demo Tests Complete!"
echo "=============================================="
echo ""
echo "Interactive Demo Suggestions:"
echo ""
echo "1. Open LibreChat: https://chat.apps.ocp419.crucible.iisl.com"
echo "   Ask: 'What is the remote work policy?'"
echo ""
echo "2. Open n8n: https://workflows.apps.ocp419.crucible.iisl.com"
echo "   Show the RAG Search and Ticket Creation workflows"
echo ""
echo "3. Show the Portkey Gateway: https://llm-gateway.apps.ocp419.crucible.iisl.com/public/"
echo "   Demonstrate LLM routing capabilities"
echo ""
