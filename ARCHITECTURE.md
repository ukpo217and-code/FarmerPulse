# Food Systems Gateway Architecture

## Executive Summary

FarmerPulse is evolving from a single-role farmer platform into a **unified Food Systems Gateway** that intelligently serves all 31+ agricultural ecosystem actors through one conversational interface. Users can hold multiple roles simultaneously (e.g., Farmer + Processor + Buyer), maintain a single conversation history, and receive specialized routing to role-specific advisors.

**Key Principles:**
- **One user, many roles:** Never overwrite; always append new roles
- **Pending questions first:** Onboarding blocks intent detection until critical fields are answered
- **Intelligent routing:** Each message is classified and sent to the appropriate specialist
- **Ecosystem coordination:** Automatic opportunity matching connects complementary actors
- **Backward compatible:** All existing farmer workflows continue unchanged

---

## System Architecture

### High-Level Flow

```
┌─────────────────────────────────────────────────────────────────┐
│  USER MESSAGE (WhatsApp → Edge Function)                        │
└──────────────────────┬──────────────────────────────────────────┘
                       │
                       ▼
        ┌──────────────────────────────┐
        │  pulseid-gateway             │
        │  (Routing Engine)            │
        └──────────────────────────────┘
                       │
        ┌──────────────┼──────────────┐
        │              │              │
        ▼              ▼              ▼
   ┌─────────┐  ┌──────────────┐  ┌──────────┐
   │Onboarding│  │Conversation  │  │Specialist│
   │Check     │  │Intelligence  │  │Routing   │
   └─────────┘  │Extraction    │  └──────────┘
                └──────────────┘
                       │
        ┌──────────────┼──────────────────────────┐
        │              │                          │
        ▼              ▼                          ▼
   ┌────────────┐ ┌──────────────┐  ┌─────────────────────┐
   │Save State  │ │Log Routing   │  │Route to Specialist  │
   │(RLS-bound) │ │(Analytics)   │  │(farmer/buyer/etc)   │
   └────────────┘ └──────────────┘  └─────────────────────┘
                                             │
                                             ▼
                                    ┌────────────────────┐
                                    │Specialist Advisor  │
                                    │(15+ handlers)      │
                                    └────────────────────┘
                                             │
                                             ▼
                                    ┌────────────────────┐
                                    │Run Opportunity     │
                                    │Matching            │
                                    └────────────────────┘
                                             │
                                             ▼
                                    ┌────────────────────┐
                                    │Response to User    │
                                    │(with suggestions)  │
                                    └────────────────────┘
```

---

## Database Schema Extensions (Phases 1-4)

### Phase 1: Type System (0009_actor_role_types.sql)

**New ENUM:** `actor_role_type`

```
famer, farmer_group, cooperative, extension_agent, input_dealer,
agro_dealer, seed_company, fertilizer_supplier, veterinary_provider,
mechanization_provider, aggregator, commodity_trader, processor,
manufacturer, buyer, exporter, importer, transporter, warehouse,
cold_chain_operator, financial_institution, insurance_provider,
ngo, development_partner, government_agency, research_institution,
university, commodity_association, market_association,
youth_agripreneur, women_farmer_group, agritech_company,
consultant, other
```

**Backward Compatibility:** Existing `actor_type` enum unchanged. New roles are additive.

---

### Phase 2: Multi-Role Support Tables (0010_multi_role_support.sql)

#### Table: `actor_roles`
Maps actors to zero or more roles (append-only).

```sql
CREATE TABLE actor_roles (
  id uuid PRIMARY KEY,
  actor_id uuid NOT NULL REFERENCES actors(id) ON DELETE CASCADE,
  role actor_role_type NOT NULL,
  activated_at timestamp DEFAULT now(),
  metadata jsonb,
  created_at timestamp,
  UNIQUE(actor_id, role)  -- One role per actor only once
);
```

**Example:**
```
actor_id: 12345
roles: farmer, processor, buyer  (3 rows, one per role)
```

#### Table: `onboarding_state`
Tracks progression through 5-step onboarding (name → state → org → commodity → role).

```sql
CREATE TABLE onboarding_state (
  id uuid PRIMARY KEY,
  actor_id uuid UNIQUE NOT NULL REFERENCES actors(id),
  current_step text,  -- 'name', 'state', 'organization', 'commodity', 'role'
  pending_response_field text,  -- Which field are we waiting for?
  responses jsonb,  -- {"full_name": "John", "state": "Kogi", ...}
  completed_at timestamp,  -- When onboarding finished
  created_at timestamp,
  updated_at timestamp
);
```

**State Machine:**
```
start → pending_field='full_name' → save('John') → pending_field='state' → ...
  → pending_field='role' → save('farmer,buyer') → completed_at=now()
```

#### Table: `routing_history`
Every message, its detected intent, and specialist assignment (for analytics).

```sql
CREATE TABLE routing_history (
  id uuid PRIMARY KEY,
  actor_id uuid REFERENCES actors(id),
  input_text text,
  detected_intent text,  -- 'farmer_advice', 'buyer_query', etc.
  detected_roles jsonb,  -- roles active at message time
  routed_to text,  -- 'farmer_advisor', 'buyer_advisor', etc.
  confidence numeric(5,2),
  created_at timestamp
);
```

#### Table: `conversation_intelligence`
Structured extraction from each message (for ecosystem insights).

```sql
CREATE TABLE conversation_intelligence (
  id uuid PRIMARY KEY,
  actor_id uuid REFERENCES actors(id),
  conversation_id uuid,
  actor text,  -- 'farmer', 'buyer', etc.
  location jsonb,  -- {"state": "Kogi", "lga": "Lokoja"}
  commodity text,  -- 'maize', 'rice', etc.
  intent text,  -- 'buy', 'sell', 'get_advice'
  need text,  -- structured need
  constraint_text text,  -- budget, volume, quality, etc.
  opportunity text,  -- identified growth path
  urgency text,  -- 'immediate', 'this_month', 'this_season'
  sentiment text,  -- 'positive', 'neutral', 'negative'
  potential_matches jsonb,  -- [{"actor_id": "...", "score": 0.85}]
  confidence numeric(5,2),
  created_at timestamp
);
```

#### Table: `actor_opportunity_matches`
Proposed connections between complementary actors (farmer ↔ buyer, processor ↔ aggregator, etc.).

```sql
CREATE TABLE actor_opportunity_matches (
  id uuid PRIMARY KEY,
  actor_a_id uuid NOT NULL REFERENCES actors(id),
  actor_b_id uuid NOT NULL REFERENCES actors(id),
  match_type text,  -- 'farmer-buyer', 'processor-aggregator', etc.
  score numeric(6,2),  -- 0-100 confidence
  commodity text,
  location jsonb,
  proposed_date timestamp,
  status text,  -- 'proposed', 'accepted', 'rejected', 'completed'
  metadata jsonb,
  created_at timestamp,
  updated_at timestamp,
  UNIQUE(actor_a_id, actor_b_id, match_type)
);
```

---

### Phase 3: Row-Level Security (0011_multi_role_rls.sql)

**All new tables have RLS enabled:**

| Table | Policy | Who Can See |
|-------|--------|-------------|
| `actor_roles` | `actor_roles_access` | Self, org members, platform_admin |
| `onboarding_state` | `onboarding_state_access` | Self, platform_admin |
| `routing_history` | `routing_history_access` | Self, org members, platform_admin |
| `conversation_intelligence` | `conversation_intelligence_access` | Self, org members, platform_admin |
| `actor_opportunity_matches` | `actor_opportunity_matches_access` | Both actors, their orgs, platform_admin |

**Example Policy:**
```sql
CREATE POLICY actor_roles_access ON actor_roles FOR ALL TO authenticated
USING (
  app.is_platform_admin()
  OR (actor_id = app.current_actor_id())
  OR (app.actor_org_id(actor_id) IN (SELECT app.current_org_ids()))
)
WITH CHECK (...);
```

---

### Phase 4: Helper Functions (0012_multi_role_functions.sql)

#### Role Management
```sql
app.add_actor_role(actor_id, role) → uuid
  -- Appends role; no-op if already exists

app.actor_all_roles(actor_id) → SETOF actor_role_type
  -- Lists all roles for actor, ordered by activation date

app.actor_has_role(actor_id, role) → boolean
  -- Check if actor has specific role

app.remove_actor_role(actor_id, role) → void
  -- Deactivate role (keeps history)
```

#### Onboarding State Machine
```sql
app.start_onboarding(actor_id) → uuid
  -- Initialize onboarding; idempotent

app.get_onboarding_state(actor_id) → TABLE(...)
  -- Fetch current step, pending field, responses

app.get_pending_field(actor_id) → text
  -- Get field awaiting response; blocks intent detection

app.save_onboarding_response(actor_id, field, value) → void
  -- Save response, advance to next step or complete

app.is_onboarding_complete(actor_id) → boolean
  -- True if all 5 fields answered
```

#### Conversation Intelligence
```sql
app.extract_conversation_intelligence(
  actor_id, conversation_id, actor_type, location, commodity, intent,
  need, constraint, opportunity, urgency, sentiment, confidence
) → uuid
  -- Log structured intelligence from message

app.get_actor_intelligence_summary(actor_id) → TABLE(...)
  -- Analytics: total conversations, intents, commodities, sentiment, opportunities
```

#### Opportunity Matching
```sql
app.propose_actor_match(actor_a_id, actor_b_id, match_type, score, commodity, location) → uuid
  -- Create or update match; idempotent

app.accept_match(match_id) → void
  -- Mark match as accepted

app.reject_match(match_id) → void
  -- Mark match as rejected

app.get_actor_matches(actor_id) → TABLE(...)
  -- Fetch all active (proposed/accepted) matches for actor
```

---

## Onboarding Flow: Sequence Diagram

```
FARMER                          GATEWAY                      DATABASE
   │                               │                            │
   │─── Message: "Hello" ────────>│                            │
   │                               │─── Get/Create Actor ──────>│
   │                               │<─── actor_id: 12345 ───────│
   │                               │                            │
   │                               │─── Check Onboarding ──────>│
   │                               │<─── pending: 'full_name' ──│
   │                               │                            │
   │<─── "What's your name?" ─────│                            │
   │                               │                            │
   │─── Message: "John Obi" ──────>│                            │
   │                               │─── Save Response ────────>│
   │                               │<─── OK, next: 'state' ────│
   │                               │                            │
   │<─── "Which state?" ──────────│                            │
   │                               │                            │
   │─── Message: "Kogi" ──────────>│                            │
   │                               │─── Save Response ────────>│
   │                               │<─── OK, next: 'role' ─────│
   │                               │                            │
   │<─── "Your role(s)? farmer/buyer/..." ───┐                │
   │                               │          │                │
   │─ Message: "farmer, buyer" ─────>─────────┘                │
   │                               │─── Save & Add Roles ─────>│
   │                               │<─── OK, onboarding done ──│
   │                               │─── Log: routing_history ──>│
   │                               │                            │
   │<─── "How can I help you today?" ─────┐                   │
   │     [Menu: Crop Advice, Find Buyers] │                   │
   │                               │      │                   │
```

---

## Message Routing: Decision Tree

```
Incoming Message
    │
    ├─ [1] Is actor in onboarding?
    │   ├─ YES → Return onboarding question
    │   │        (block intent detection)
    │   └─ NO → Continue to [2]
    │
    ├─ [2] Detect intent from message
    │   ├─ farmer_advice
    │   ├─ buyer_query
    │   ├─ processor_guidance
    │   ├─ finance_inquiry
    │   ├─ marketplace
    │   ├─ extension_support
    │   ├─ mechanization
    │   ├─ export_docs
    │   ├─ certification
    │   ├─ climate_risk
    │   ├─ policy
    │   ├─ research
    │   ├─ grant
    │   ├─ business
    │   ├─ training
    │   └─ general (fallback)
    │
    ├─ [3] Check actor's active roles
    │   └─ Filter applicable specialists
    │
    ├─ [4] Extract conversation intelligence
    │   └─ Log: actor, location, commodity, intent, need, urgency, sentiment
    │
    ├─ [5] Route to specialist
    │   └─ Call specialist Edge Function
    │
    ├─ [6] Run opportunity matching
    │   └─ Find complementary actors (buyer/seller, processor/aggregator, etc.)
    │
    └─ [7] Return response + suggestions
        └─ Send to user via WhatsApp
```

---

## Specialist Advisors Registry

**Table: `specialist_advisors`**

```sql
CREATE TABLE specialist_advisors (
  id uuid PRIMARY KEY,
  code text UNIQUE,  -- 'farmer_advisor', 'buyer_advisor', etc.
  name text,
  description text,
  target_roles actor_role_type[],  -- Roles this specialist serves
  function_name text,  -- Edge Function name to invoke
  metadata jsonb,  -- Config, model info, etc.
  active boolean DEFAULT true,
  created_at timestamp
);
```

**Seeded Advisors:**

| Code | Name | Target Roles | Function |
|------|------|--------------|----------|
| `farmer_advisor` | Farmer Advisor | farmer, farmer_group | specialist-farmer-advisor |
| `processor_advisor` | Processor Advisor | processor, manufacturer | specialist-processor-advisor |
| `buyer_advisor` | Buyer Advisor | buyer, exporter, importer | specialist-buyer-advisor |
| `aggregation_advisor` | Aggregation Advisor | aggregator, commodity_trader | specialist-aggregator-advisor |
| `extension_advisor` | Extension Advisor | extension_agent, ngo, university | specialist-extension-advisor |
| `finance_advisor` | Finance Advisor | financial_institution, insurance_provider | specialist-finance-advisor |
| `marketplace_advisor` | Marketplace Advisor | farmer, buyer, trader | specialist-marketplace-advisor |
| `mechanization_advisor` | Mechanization Advisor | mechanization_provider, input_dealer | specialist-mechanization-advisor |
| `export_advisor` | Export Advisor | exporter, processor | specialist-export-advisor |
| `certification_advisor` | Certification Advisor | farmer, processor, buyer | specialist-certification-advisor |
| `climate_advisor` | Climate Advisor | farmer, extension_agent, research | specialist-climate-advisor |
| `policy_advisor` | Policy Advisor | government_agency, development_partner | specialist-policy-advisor |
| `research_advisor` | Research Advisor | research_institution, university, agritech | specialist-research-advisor |
| `grant_advisor` | Grant Advisor | ngo, cooperative, women_farmer_group | specialist-grant-advisor |
| `business_advisor` | Business Advisor | agritech, youth_agripreneur, consultant | specialist-business-advisor |
| `training_advisor` | Training Advisor | extension_agent, university, ngo | specialist-training-advisor |

---

## Opportunity Matching Engine

### Match Types

```
farm-buyer            Farmer produces commodity → Buyer purchases
processor-aggregator  Processor wants volume → Aggregator supplies
input-farmer          Input dealer has stock → Farmer needs inputs
finance-business      Financial institution → Eligible business for credit
ngo-beneficiary       NGO program → Target beneficiary community
research-farmer       Researcher needs data → Farmer willing to participate
export-producer       Exporter needs certified → Producer with certification
```

### Matching Algorithm (Phase 5)

```python
def find_matches_for_actor(actor_id, role, commodity=None, location=None):
    """
    1. Load actor's profile, location, commodity, needs
    2. Find complementary actors (via conversation_intelligence)
    3. Score each pair on:
       - Role compatibility (farmer + buyer = 1.0)
       - Commodity match (same commodity = 1.0)
       - Geographic proximity (same LGA = 1.0, same state = 0.7)
       - Timing alignment (urgency match)
    4. Propose top 3-5 matches
    """
    score = (
      role_compat_score * 0.4 +
      commodity_match * 0.3 +
      location_proximity * 0.2 +
      timing_alignment * 0.1
    )
    return sorted_matches if score > 0.65 else []
```

---

## API Contracts (Edge Functions)

### pulseid-gateway

**Request:**
```json
{
  "phone": "2348012345678",
  "message": "I'm looking to buy rice in bulk",
  "name": "Zainab Ahmed"  // optional, used if new actor
}
```

**Response: Onboarding Pending**
```json
{
  "type": "question",
  "priority": "onboarding",
  "message": "What's your full name?",
  "field": "full_name"
}
```

**Response: Routed to Specialist**
```json
{
  "type": "routed",
  "specialist": "buyer_advisor",
  "intent": "buyer_query",
  "confidence": 0.89,
  "message": "Connecting you to buyer advisor..."
}
```

### specialist-buyer-advisor

**Request:**
```json
{
  "actor_id": "550e8400-e29b-41d4-a716-446655440000",
  "message": "I need 500 bags of rice",
  "context": {
    "roles": ["buyer", "processor"],
    "location": {"state": "Lagos", "lga": "Ikorodu"},
    "commodities": ["rice", "maize"]
  }
}
```

**Response:**
```json
{
  "type": "advice",
  "message": "I found 3 aggregators near you with rice in stock...",
  "suggestions": [
    {
      "type": "match",
      "actor_name": "Musa's Aggregators",
      "actor_id": "...",
      "commodity": "rice",
      "quantity_available": 600,
      "location": {"state": "Lagos", "lga": "Ikorodu"},
      "price_per_unit": 45000,
      "score": 0.92,
      "action": "connect"
    }
  ],
  "intelligence_logged": true
}
```

---

## Backward Compatibility Matrix

| Feature | Status | Notes |
|---------|--------|-------|
| Farmer Registration | ✅ Works | Actors still created with actor_type='farmer' |
| Farm Management | ✅ Works | farms, crop_seasons, harvests unchanged |
| WhatsApp Sessions | ✅ Works | whatsapp_sessions, messages unaffected |
| AI Conversations | ✅ Works | ai_conversations table unchanged |
| Pulse Scores | ✅ Works | pulse_scores calculation logic intact |
| Projects & M&E | ✅ Works | projects, interventions, beneficiaries unchanged |
| Market Prices | ✅ Works | market_prices reference data accessible |
| Weather Data | ✅ Works | weather_observations unaffected |
| Dashboard Views | ✅ Works | mv_dashboard_summary intact |
| Existing RLS | ✅ Works | All existing policies remain; new tables added |

**Migration Path for Existing Users:**
1. First message after upgrade → onboarding detects existing actor
2. Skips already-answered fields (name, state)
3. Asks only for new information (primary role, secondary roles)
4. Appends roles via `app.add_actor_role()`
5. No data loss; user history preserved

---

## Performance Considerations

### Indexes (Automatically Created)

```sql
-- All new tables have indexes on foreign keys + frequently-queried columns
idx_actor_roles_actor_id
idx_actor_roles_role
idx_onboarding_state_actor_id
idx_onboarding_state_completed
idx_routing_history_actor_id
idx_routing_history_intent
idx_routing_history_routed_to
idx_conv_intel_actor_id
idx_conv_intel_commodity
idx_conv_intel_intent
idx_conv_intel_created
idx_matches_actor_a
idx_matches_actor_b
idx_matches_status
idx_matches_created
```

### Query Optimization

**High-frequency queries:**
- `get_pending_field()` → indexed on actor_id
- `log_routing()` → batch-insert, no complex joins
- `extract_conversation_intelligence()` → JSONB storage, no normalization
- `get_actor_matches()` → indexed on both actor_ids

**Materialized views (Phase 7+):**
- `mv_actor_ecosystem_summary` – commodity, location, role distribution
- `mv_match_opportunities` – precomputed match scores

---

## Security Model

### Authentication
- Supabase Auth (JWT-based)
- Per-user isolation via `auth.uid()` → `users.actor_id` → RLS policies

### Authorization (RLS)
- **Platform Admin:** Sees all records across all orgs
- **Org Member:** Sees own org's records + self records
- **Actor:** Sees only own records (self-service)

### Data Isolation
- `onboarding_state`: Self-only (no org visibility)
- `routing_history`: Self + org (for analytics)
- `conversation_intelligence`: Self + org (for ecosystem insights)
- `actor_opportunity_matches`: Both actors + their orgs (for coordination)

### Audit Trail
- `routing_history` logs every message + routing decision
- `audit_logs` (existing) captures profile mutations
- `activities` (existing) tracks major events

---

## Deployment Checklist

- [ ] **Phase 1-4:** Migrations 0009-0012 applied
- [ ] **Phase 5:** pulseid-gateway Edge Function deployed
- [ ] **Phase 6:** 15+ specialist advisor functions deployed
- [ ] **Phase 7:** Opportunity matching queries optimized
- [ ] **Phase 8:** Role-specific onboarding questionnaires loaded
- [ ] **Phase 9:** Help menu & discovery UI tested
- [ ] **Phase 10:** Test suite passing (90%+ coverage)
- [ ] **Phase 11:** Technical documentation complete
- [ ] **Phase 12:** Staging UAT with 5 test users
- [ ] **Phase 13:** Production cutover (zero-downtime)

---

## Rollback Plan

If issues arise:

```bash
# 1. Disable food systems gateway (maintain backward compat)
UPDATE specialist_advisors SET active = false;

# 2. Revert edge functions to original pulseid-intake
# (Points to farmer-only routing)

# 3. Migrations 0009-0012 remain (inert; no impact on existing flows)

# 4. All data in new tables preserved; no data loss
```

---

## References

- **Migrations:** `0009_actor_role_types.sql`, `0010_multi_role_support.sql`, `0011_multi_role_rls.sql`, `0012_multi_role_functions.sql`
- **Edge Functions:** Phase 5 (pulseid-gateway), Phase 6 (specialists)
- **Tests:** Phase 10 (pytest suite)
- **Deployment:** Phase 11 (runbook)
