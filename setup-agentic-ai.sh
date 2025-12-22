#!/bin/bash
#
# AITP Agentic AI Project - Quick Setup Script
# This script sets up the Enterprise Knowledge Assistant demo
#

set -e

echo "=============================================="
echo "AITP Agentic AI Project - Quick Setup"
echo "=============================================="

# Configuration
POSTGRES_POD=$(oc get pods -n aitp-data -l postgres-operator.crunchydata.com/role=master -o jsonpath='{.items[0].metadata.name}')
MONGODB_POD="aitp-mongodb-cluster-0"

echo ""
echo "[1/5] Setting up PostgreSQL Database..."
echo "----------------------------------------------"

oc exec -it $POSTGRES_POD -n aitp-data -c database -- psql -U postgres << 'EOSQL'
-- Create database
CREATE DATABASE knowledge_base;
\c knowledge_base

-- Enable vector extension
CREATE EXTENSION IF NOT EXISTS vector;

-- Create documents table
CREATE TABLE IF NOT EXISTS documents (
    id SERIAL PRIMARY KEY,
    title VARCHAR(500),
    content TEXT,
    source VARCHAR(255),
    doc_type VARCHAR(50),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create chunks table for RAG
CREATE TABLE IF NOT EXISTS document_chunks (
    id SERIAL PRIMARY KEY,
    document_id INTEGER REFERENCES documents(id) ON DELETE CASCADE,
    chunk_index INTEGER,
    content TEXT,
    embedding vector(1536),
    token_count INTEGER,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create index for vector similarity search
CREATE INDEX IF NOT EXISTS idx_chunks_embedding ON document_chunks 
USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);

-- Create tool executions logging table
CREATE TABLE IF NOT EXISTS tool_executions (
    id SERIAL PRIMARY KEY,
    conversation_id VARCHAR(100),
    tool_name VARCHAR(100),
    input_params JSONB,
    output_result JSONB,
    execution_time_ms INTEGER,
    status VARCHAR(20),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create user for the agent
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_user WHERE usename = 'agent_user') THEN
        CREATE USER agent_user WITH PASSWORD 'AgentSecurePass123!';
    END IF;
END
$$;

GRANT ALL PRIVILEGES ON DATABASE knowledge_base TO agent_user;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO agent_user;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO agent_user;

-- Insert sample documents
INSERT INTO documents (title, content, source, doc_type) VALUES
(
    'Remote Work Policy',
    'Employees may work remotely up to 3 days per week with manager approval. Remote work requires:
    1. Stable internet connection (minimum 25 Mbps)
    2. Dedicated workspace
    3. Availability during core hours (10 AM - 3 PM local time)
    4. Participation in all scheduled meetings
    
    Equipment provided: Laptop, monitor, keyboard, mouse.
    Stipend: $50/month for internet and utilities.
    
    Request process: Submit request through HR portal at least 2 weeks in advance.
    Approval: Direct manager and HR must approve.
    
    Review: Remote work arrangements are reviewed quarterly.',
    'HR Policies',
    'policy'
),
(
    'Expense Reimbursement Policy',
    'Employees can submit expense reimbursements for business-related costs.
    
    Categories and Limits:
    - Travel: Pre-approved, actual costs reimbursed
    - Meals (client meetings): Up to $75 per person
    - Office supplies: Up to $100/month without approval
    - Training/Conferences: Pre-approved, registration + travel
    - Software/Tools: Must be on approved list or get IT approval
    
    Submission Process:
    1. Submit within 30 days of expense
    2. Include original receipt
    3. Provide business justification
    4. Submit through Expense Management System
    
    Processing Time: 5-7 business days after approval
    Payment: Direct deposit to payroll account',
    'Finance Policies',
    'policy'
),
(
    'IT Security Guidelines',
    'All employees must follow these security practices:
    
    Password Requirements:
    - Minimum 12 characters
    - Mix of uppercase, lowercase, numbers, symbols
    - Change every 90 days
    - No password reuse (last 12 passwords)
    
    Device Security:
    - Enable full-disk encryption
    - Install approved antivirus software
    - Keep operating system updated
    - Lock screen when away (auto-lock after 5 minutes)
    
    Data Handling:
    - Classify data (Public, Internal, Confidential, Restricted)
    - Never share credentials
    - Use approved file sharing tools only
    - Report suspicious emails to security@company.com
    
    VPN Required for:
    - Accessing internal systems remotely
    - Using public WiFi
    - Accessing confidential data',
    'IT Security',
    'guideline'
),
(
    'Annual Leave Policy',
    'Leave Entitlements:
    - Annual Leave: 20 days per year (accrued monthly)
    - Sick Leave: 10 days per year
    - Personal Days: 3 days per year
    - Parental Leave: 12 weeks paid
    
    Requesting Leave:
    1. Submit request in HR system
    2. Minimum notice: 2 weeks for vacation, 1 day for sick leave
    3. Manager approval required for all leave
    
    Carryover:
    - Maximum 5 days can be carried to next year
    - Carried days must be used by March 31
    - No payout for unused leave
    
    Holidays: 10 company holidays per year (see calendar)
    
    Extended Leave: Contact HR for leaves longer than 2 weeks',
    'HR Policies',
    'policy'
),
(
    'Software Development Standards',
    'Code Quality Standards:
    
    Version Control:
    - Use Git for all projects
    - Branch naming: feature/*, bugfix/*, hotfix/*
    - Commit messages: conventional commits format
    - Pull requests required for main branch
    
    Code Review:
    - Minimum 1 reviewer approval required
    - Review within 24 hours
    - Address all comments before merge
    
    Testing:
    - Unit test coverage minimum 80%
    - Integration tests for APIs
    - E2E tests for critical flows
    
    Documentation:
    - README.md for all repositories
    - API documentation (OpenAPI/Swagger)
    - Architecture Decision Records (ADRs)
    
    Deployment:
    - CI/CD pipelines required
    - Staging environment testing
    - Production deployments during low-traffic hours
    - Rollback plan documented',
    'Engineering',
    'standard'
);

SELECT 'PostgreSQL setup complete. ' || COUNT(*) || ' documents inserted.' FROM documents;
EOSQL

echo ""
echo "[2/5] Setting up MongoDB Collections..."
echo "----------------------------------------------"

oc exec -it $MONGODB_POD -n aitp-data -- mongo << 'EOMONGO'
use agent_memory

// Create collections
db.createCollection("conversations")
db.createCollection("agent_state")
db.createCollection("tickets")
db.createCollection("tool_definitions")

// Create indexes
db.conversations.createIndex({ "conversation_id": 1 })
db.conversations.createIndex({ "created_at": -1 })
db.agent_state.createIndex({ "conversation_id": 1 })
db.tickets.createIndex({ "ticketId": 1 })

// Insert tool definitions
db.tool_definitions.deleteMany({})
db.tool_definitions.insertMany([
    {
        name: "search_knowledge_base",
        description: "Search the company knowledge base for relevant information",
        parameters: {
            type: "object",
            properties: {
                query: { type: "string", description: "The search query" },
                max_results: { type: "integer", description: "Maximum results", default: 5 }
            },
            required: ["query"]
        }
    },
    {
        name: "create_ticket",
        description: "Create a support ticket in the ticketing system",
        parameters: {
            type: "object",
            properties: {
                title: { type: "string", description: "Ticket title" },
                description: { type: "string", description: "Detailed description" },
                priority: { type: "string", enum: ["low", "medium", "high", "critical"] },
                category: { type: "string", description: "Ticket category" }
            },
            required: ["title", "description", "priority"]
        }
    },
    {
        name: "send_notification",
        description: "Send a notification to a user or team",
        parameters: {
            type: "object",
            properties: {
                recipient: { type: "string", description: "Email or team name" },
                subject: { type: "string", description: "Subject" },
                message: { type: "string", description: "Message body" },
                channel: { type: "string", enum: ["email", "slack", "teams"] }
            },
            required: ["recipient", "subject", "message"]
        }
    },
    {
        name: "generate_report",
        description: "Generate a report on specified topic",
        parameters: {
            type: "object",
            properties: {
                report_type: { type: "string", enum: ["summary", "detailed", "analytics"] },
                topic: { type: "string", description: "Report topic" },
                format: { type: "string", enum: ["text", "markdown", "json"] }
            },
            required: ["report_type", "topic"]
        }
    }
])

print("MongoDB setup complete. Tool definitions inserted.")
EOMONGO

echo ""
echo "[3/5] Configuring pg_hba.conf for agent connections..."
echo "----------------------------------------------"

oc exec -it $POSTGRES_POD -n aitp-data -c database -- bash -c "
if ! grep -q '10.0.0.0/8' /pgdata/pg15/pg_hba.conf; then
    echo 'host all all 10.0.0.0/8 md5' >> /pgdata/pg15/pg_hba.conf
    echo 'host knowledge_base agent_user 10.0.0.0/8 md5' >> /pgdata/pg15/pg_hba.conf
fi
"
oc exec -it $POSTGRES_POD -n aitp-data -c database -- psql -U postgres -c "SELECT pg_reload_conf();"

echo ""
echo "[4/5] Verifying Setup..."
echo "----------------------------------------------"

echo "PostgreSQL documents:"
oc exec -it $POSTGRES_POD -n aitp-data -c database -- psql -U postgres -d knowledge_base -c "SELECT id, title, doc_type FROM documents;"

echo ""
echo "MongoDB collections:"
oc exec -it $MONGODB_POD -n aitp-data -- mongo agent_memory --quiet --eval "db.getCollectionNames()"

echo ""
echo "[5/5] Setup Complete!"
echo "=============================================="
echo ""
echo "Access Points:"
echo "  - LibreChat:  https://chat.apps.ocp419.crucible.iisl.com"
echo "  - n8n:        https://workflows.apps.ocp419.crucible.iisl.com"
echo "  - Portkey:    https://llm-gateway.apps.ocp419.crucible.iisl.com"
echo ""
echo "Database Connections:"
echo "  - PostgreSQL: aitp-postgres-primary.aitp-data:5432/knowledge_base"
echo "  - MongoDB:    aitp-mongodb-cluster.aitp-data:27017/agent_memory"
echo ""
echo "Next Steps:"
echo "  1. Configure n8n workflows (see documentation)"
echo "  2. Set up LibreChat custom endpoint"
echo "  3. Generate document embeddings"
echo "  4. Test the agent!"
echo ""
echo "=============================================="
