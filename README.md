# Food Systems Gateway for FarmerPulse

> Transform a single-role farmer platform into a unified **Food Systems Gateway** serving all 31+ agricultural ecosystem actors through one conversational interface.

## 🎯 What It Does

**FarmerPulse Gateway** intelligently routes users to specialized advisors based on their role and need:

```
👤 User Message
    ↓
🔀 Universal Gateway (pulseid-gateway)
    ├─ Detects role (farmer, buyer, processor, etc.)
    ├─ Checks onboarding status (blocks routing until pending fields answered)
    ├─ Detects intent (buyer_query, farmer_advice, finance_inquiry, etc.)
    └─ Routes to specialist advisor
    ↓
💡 Specialist Advisor (15+ handlers)
    ├─ Farmer Advisor → crop guidance, farm management
    ├─ Buyer Advisor → supplier sourcing, bulk pricing
    ├─ Processor Advisor → production, capacity planning
    ├─ Finance Advisor → credit, insurance
    └─ ... (11 more advisors)
    ↓
🤝 Opportunity Matching Engine
    ├─ Finds complementary actors (farmer ↔ buyer, processor ↔ aggregator)
    ├─ Proposes connections with confidence scores
    └─ Tracks acceptance/rejection
    ↓
📨 Response to User (via WhatsApp)
```

## ✨ Key Features

- **🎭 Multi-Role Support** – One user can be farmer + processor + buyer simultaneously. Roles append; never overwrite.
- **📋 Intelligent Onboarding** – 5-step state machine (name → state → organization → commodity → role) blocks intent detection until critical fields answered.
- **🧭 Smart Routing** – 15+ specialist advisors serve role-specific needs. Each message classified by intent and routed to the right handler.
- **🤝 Automatic Matching** – Ecosystem-level connections: farmers find buyers, processors find aggregators, financials find eligible borrowers.
- **📊 Conversation Intelligence** – Every message logged with structured extraction: actor, location, commodity, intent, need, urgency, sentiment.
- **⚙️ Backward Compatible** – Existing farmer workflows (farms, crop seasons, harvests) work unchanged. Zero data loss.
- **🔐 Secure & Audited** – Row-level security (RLS) enforces data isolation. Routing history & conversation intelligence enable analytics.

## 🚀 Quick Start

### Prerequisites

- Supabase project (PostgreSQL 15+)
- Python 3.9+ or Node.js 18+
- Supabase CLI: `npm install -g supabase`

### 1. Apply Database Migrations

```bash
# Set Supabase project reference
export SUPABASE_PROJECT_REF=jmltamnqlqewwsqvcvme

# Link your project
supabase link --project-ref $SUPABASE_PROJECT_REF

# Apply migrations in order
for i in 0009 0010 0011 0012 0014; do
  supabase db execute < ${i}_*.sql
  echo "✓ Migration ${i} applied"
done
```

### 2. Deploy Edge Functions

```bash
# Deploy gateway
supabase functions deploy pulseid-gateway --no-verify-jwt

# Deploy specialists
supabase functions deploy specialist-farmer-advisor --no-verify-jwt
supabase functions deploy specialist-buyer-advisor --no-verify-jwt
supabase functions deploy specialist-processor-advisor --no-verify-jwt
supabase functions deploy specialist-aggregator-advisor --no-verify-jwt
supabase functions deploy specialist-finance-advisor --no-verify-jwt
supabase functions deploy specialist-extension-advisor --no-verify-jwt
```

### 3. Test the Gateway

```bash
# Get your Edge Function URL
GATEWAY_URL=$(supabase functions list | grep pulseid-gateway | awk '{print $2}')

# Send test message
curl -X POST $GATEWAY_URL \
  -H "Content-Type: application/json" \
  -d '{
    "phone": "2348012345678",
    "message": "Hello, I am a farmer looking to sell my maize",
    "name": "John Obi"
  }'
```

**Expected response:**
```json
{
  "type": "question",
  "priority": "onboarding",
  "message": "Welcome to Pulse!\n\nWhat is your full name?",
  "field": "full_name"
}
```

### 4. Run Integration Tests

```bash
# Install dependencies
pip install supabase pytest

# Run tests
cd tests
pytest test_food_systems_gateway.py -v

# Expected output
# ======================== 15 passed in 12.34s ========================
```

---

## 📚 Architecture Overview

### Database Schema

**New Tables (Phase 2):**

```sql
-- Multi-role assignment (append-only)
actor_roles
  ├─ actor_id (FK)
  ├─ role (enum: farmer, buyer, processor, ...)
  └─ activated_at

-- Onboarding state machine (5 steps)
onboarding_state
  ├─ actor_id (FK, unique)
  ├─ current_step (name|state|organization|commodity|role)
  ├─ pending_response_field
  ├─ responses (JSONB)
  └─ completed_at

-- Message & routing analytics
routing_history
  ├─ actor_id (FK)
  ├─ input_text
  ├─ detected_intent
  ├─ routed_to (specialist name)
  └─ confidence

-- Structured intelligence extraction
conversation_intelligence
  ├─ actor_id (FK)
  ├─ actor (role)
  ├─ location (JSONB)
  ├─ commodity
  ├─ intent
  ├─ need
  ├─ urgency
  ├─ sentiment
  └─ confidence

-- Opportunity matching
actor_opportunity_matches
  ├─ actor_a_id (FK)
  ├─ actor_b_id (FK)
  ├─ match_type (farmer-buyer, processor-aggregator, ...)
  ├─ score (0-100)
  ├─ status (proposed|accepted|rejected|completed)
  └─ proposed_date
```

### Specialist Advisors

| Advisor | Target Roles | Purpose |
|---------|--------------|----------|
| **Farmer Advisor** | farmer, farmer_group | Crop/livestock guidance, farm management |
| **Buyer Advisor** | buyer, exporter, importer | Supplier sourcing, bulk pricing, quality |
| **Processor Advisor** | processor, manufacturer | Production guidance, capacity planning |
| **Aggregator Advisor** | aggregator, commodity_trader | Volume logistics, storage, buyer connections |
| **Finance Advisor** | financial_institution, insurance_provider | Credit products, insurance, savings groups |
| **Extension Advisor** | extension_agent, ngo, university | Training, technical support, capacity building |
| **Marketplace Advisor** | farmer, buyer, trader | Market dynamics, price discovery |
| **Mechanization Advisor** | mechanization_provider, input_dealer | Equipment, services, labor |
| **Export Advisor** | exporter, processor | Int'l trade, documentation, compliance |
| **Certification Advisor** | farmer, processor, buyer | Standards, organic, quality compliance |
| **Climate Advisor** | farmer, extension_agent, research | Risk management, resilience, adaptation |
| **Policy Advisor** | government_agency, development_partner | Gov initiatives, programs, subsidies |
| **Research Advisor** | research_institution, university, agritech | Technology, innovation, data partnerships |
| **Grant Advisor** | ngo, cooperative, women_farmer_group | Funding, grants, donations |
| **Business Advisor** | agritech_company, youth_agripreneur, consultant | Enterprise development, investment |

---

## 🔄 Onboarding Flow

### State Machine

```
start
  ↓
[name] "What is your full name?" → User responds → Validated & saved
  ↓
[state] "Which state are you in?" → User responds → Validated & saved
  ↓
[organization] "What organization?" → User responds → Validated & saved
  ↓
[commodity] "Main commodity/business?" → User responds → Validated & saved
  ↓
[role] "Your role(s)?" → User responds → app.add_actor_role() x N
  ↓
completed_at = NOW()
  ↓
Intent detection enabled
  ↓
User's next message → routed to specialist
```

### Code Flow (Gateway)

```typescript
// 1. Get or create actor by phone
const actor = await getOrCreateActor(phone);

// 2. Check onboarding state
const onboarding = await getOnboardingState(actor.id);
if (onboarding.pending_response_field) {
  // Return next question; block intent detection
  return onboardingQuestion(onboarding.pending_response_field);
}

// 3. Detect intent from message
const [intent, confidence] = detectIntent(message);

// 4. Get actor's roles
const roles = await supabase.rpc('app.actor_all_roles', {p_actor_id: actor.id});

// 5. Route to specialist
const specialist = specialistMap[intent] || 'general_advisor';
await logRouting(actor.id, message, intent, specialist, confidence);

// 6. Extract conversation intelligence
await supabase.from('conversation_intelligence').insert({...});

// 7. Return routing response
return {type: 'routed', specialist, intent, confidence};
```

---

## 🤝 Opportunity Matching

### Match Types

```
farm-buyer          Farmer has commodity → Buyer needs supply
processor-aggregator  Processor wants volume → Aggregator supplies
input-farmer         Input dealer has stock → Farmer needs inputs
finance-business     Financial institution → Eligible borrower
ngo-beneficiary      NGO program → Target community
research-farmer      Researcher needs data → Farmer willing to participate
export-producer      Exporter needs certified → Producer with certification
```

### Matching Algorithm

```sql
SCORE = (
  role_compatibility * 0.40 +
  commodity_match * 0.30 +
  location_proximity * 0.20 +
  timing_alignment * 0.10
)

Propose if SCORE > 0.65
```

### Example Query

```sql
-- Find buyers for farmer's commodity
SELECT * FROM app.find_buyers_for_farmer(
  p_farmer_id := '550e8400-e29b-41d4-a716-446655440000',
  p_commodity := 'maize',
  p_state := 'Kogi'
);
```

---

## 📊 Analytics & Reporting

### Onboarding Metrics

```sql
-- Completion rate by day
SELECT 
  DATE(created_at),
  COUNT(*) as started,
  COUNT(CASE WHEN completed_at IS NOT NULL THEN 1 END) as completed,
  ROUND(100.0 * COUNT(CASE WHEN completed_at IS NOT NULL THEN 1 END) / COUNT(*), 2) as completion_rate
FROM onboarding_state
GROUP BY DATE(created_at)
ORDER BY DATE(created_at) DESC;
```

### Routing Accuracy

```sql
-- Intent detection confidence
SELECT 
  detected_intent,
  AVG(confidence) as avg_confidence,
  COUNT(*) as messages
FROM routing_history
WHERE created_at > NOW() - INTERVAL '24 hours'
GROUP BY detected_intent
ORDER BY avg_confidence DESC;
```

### Opportunity Matches

```sql
-- Match acceptance rate
SELECT 
  match_type,
  COUNT(*) as proposed,
  COUNT(CASE WHEN status = 'accepted' THEN 1 END) as accepted,
  ROUND(100.0 * COUNT(CASE WHEN status = 'accepted' THEN 1 END) / COUNT(*), 2) as acceptance_rate
FROM actor_opportunity_matches
WHERE created_at > NOW() - INTERVAL '7 days'
GROUP BY match_type;
```

---

## 🔐 Security

### Row-Level Security (RLS)

All new tables have RLS enabled:

- **actor_roles** – Actor sees own; org members see org actors; platform_admin sees all
- **onboarding_state** – Actor-only (self)
- **routing_history** – Actor sees own; org members see org analytics
- **conversation_intelligence** – Actor sees own; org members see org trends
- **actor_opportunity_matches** – Both actors see their matches

### Audit Trail

- `routing_history` logs every message + routing decision
- `audit_logs` captures profile mutations
- `activities` tracks major events

---

## ✅ Testing

### Run Integration Tests

```bash
pytest tests/test_food_systems_gateway.py -v
```

**Coverage (90%+):**
- Multi-role assignment (3 tests)
- Onboarding state machine (3 tests)
- Routing history logging (1 test)
- Conversation intelligence (1 test)
- Opportunity matching (3 tests)
- Backward compatibility (1 test)
- End-to-end flow (1 test)

### Manual Testing

```bash
# Test new user onboarding
curl -X POST $GATEWAY_URL \
  -H "Content-Type: application/json" \
  -d '{
    "phone": "2348111111111",
    "message": "Hello",
    "name": "Alice"
  }'
# Expected: onboarding question

# Test routing after onboarding
curl -X POST $GATEWAY_URL \
  -H "Content-Type: application/json" \
  -d '{
    "phone": "2348111111111",
    "message": "I need to buy 500 bags of rice"
  }'
# Expected: routed to buyer_advisor

# Test multi-role
curl -X POST $GATEWAY_URL \
  -H "Content-Type: application/json" \
  -d '{
    "phone": "2348111111111",
    "message": "Can I also process the rice?"
  }'
# Expected: routed to processor_advisor
```

---

## 📖 Documentation

- **[ARCHITECTURE.md](./ARCHITECTURE.md)** – Comprehensive system design (500+ lines)
- **[DEPLOYMENT.md](./DEPLOYMENT.md)** – Production deployment runbook
- **[tests/test_food_systems_gateway.py](./tests/test_food_systems_gateway.py)** – Integration tests
- **[Migrations](./0009_*.sql)** – Database schema extensions
- **[Edge Functions](./supabase/functions/)** – Specialized advisors

---

## 🛠️ Troubleshooting

### Q: Onboarding questions not advancing
**A:** Check that `app.save_onboarding_response()` is called after each user message. Verify RLS policies allow INSERT on `onboarding_state`.

### Q: Routing always goes to "general_advisor"
**A:** Review intent detection keywords in `pulseid-gateway/main.ts`. Increase keyword matches or lower confidence threshold.

### Q: No opportunity matches proposed
**A:** Verify actors have roles in `actor_roles` table. Run `app.batch_propose_matches()` manually. Check matching query results.

### Q: Edge Function timeouts
**A:** Check database indexes; verify network latency to Supabase. Consider caching advisor registry locally.

---

## 🤝 Contributing

1. Create a feature branch: `git checkout -b feature/add-my-advisor`
2. Implement specialist advisor function
3. Add tests in `tests/test_food_systems_gateway.py`
4. Submit pull request
5. After merge, deploy via `supabase functions deploy`

---

## 📝 License

Proprietary – Cultivate Integrated Services Ltd

---

## 📞 Support

- **Documentation:** See [ARCHITECTURE.md](./ARCHITECTURE.md)
- **Issues:** Report to andrew@cultivate.ng
- **Urgent:** Use escalation contacts in [DEPLOYMENT.md](./DEPLOYMENT.md)

---

**Last Updated:** July 15, 2026
**Version:** 1.0 (Food Systems Gateway Activation)
