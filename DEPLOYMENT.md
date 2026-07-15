# Food Systems Gateway - Deployment Runbook

## Pre-Deployment Checklist

### Prerequisites
- [ ] All migrations 0009-0012 reviewed and approved
- [ ] Edge Functions tested in staging
- [ ] Integration tests passing (90%+ coverage)
- [ ] Database backups current
- [ ] Rollback plan documented and rehearsed
- [ ] Team trained on new routing architecture
- [ ] Monitoring and alerting configured

### Environment Variables

Ensure all Supabase environment variables are set:

```bash
SUPABASE_URL=https://jmltamnqlqewwsqvcvme.supabase.co
SUPABASE_SERVICE_ROLE_KEY=<secret>
SUPABASE_ANON_KEY=<public>
```

---

## Deployment Phases

### Phase 1: Database Migrations (Zero-Downtime)

**Duration:** ~5 minutes

```bash
# 1. Create snapshot for rollback
PG_DUMP_CMD="pg_dump --host=$DB_HOST --username=postgres --password=$DB_PASSWORD --format=custom"
$PG_DUMP_CMD $DB_NAME > backup-pre-gateway-$(date +%s).dump

# 2. Apply migrations in sequence
for migration in 0009_actor_role_types.sql 0010_multi_role_support.sql 0011_multi_role_rls.sql 0012_multi_role_functions.sql; do
  echo "Applying $migration..."
  psql -h $DB_HOST -U postgres -d $DB_NAME -f $migration
  if [ $? -ne 0 ]; then
    echo "FAILED: $migration. Rolling back..."
    exit 1
  fi
  echo "✓ $migration applied"
done

# 3. Verify new tables exist
psql -h $DB_HOST -U postgres -d $DB_NAME -c \
  "SELECT tablename FROM pg_tables WHERE tablename IN ('actor_roles', 'onboarding_state', 'routing_history', 'conversation_intelligence', 'actor_opportunity_matches')"
```

**Expected Output:**
```
          tablename          
-----------------------------
 actor_roles
 onboarding_state
 routing_history
 conversation_intelligence
 actor_opportunity_matches
(5 rows)
```

### Phase 2: Edge Function Deployment

**Duration:** ~10 minutes

#### Option A: Supabase CLI (Recommended)

```bash
# Link project
supabase link --project-ref jmltamnqlqewwsqvcvme

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

#### Option B: Supabase Dashboard

1. Go to Edge Functions
2. Click "Create function"
3. Name: `pulseid-gateway`
4. Paste code from `supabase/functions/pulseid-gateway/main.ts`
5. Click "Deploy"
6. Repeat for each specialist advisor

**Verification:**

```bash
# Test gateway endpoint
curl -X POST https://jmltamnqlqewwsqvcvme.functions.supabase.co/pulseid-gateway \
  -H "Content-Type: application/json" \
  -d '{
    "phone": "2348012345678",
    "message": "Hello, I am a farmer",
    "name": "Test User"
  }'
```

**Expected Response:**
```json
{
  "type": "question",
  "priority": "onboarding",
  "message": "Welcome to Pulse!\n\nWhat is your full name?",
  "field": "full_name"
}
```

### Phase 3: Specialist Advisor Registry Population

**Duration:** ~2 minutes

```sql
-- Seed specialist_advisors table
INSERT INTO public.specialist_advisors (
  code, name, description, target_roles, function_name, active
) VALUES
  ('farmer_advisor', 'Farmer Advisor', 'Crop/livestock guidance', 
   ARRAY['farmer'::actor_role_type, 'farmer_group'::actor_role_type], 
   'specialist-farmer-advisor', true),
  ('processor_advisor', 'Processor Advisor', 'Processing & value-add', 
   ARRAY['processor'::actor_role_type, 'manufacturer'::actor_role_type], 
   'specialist-processor-advisor', true),
  ('buyer_advisor', 'Buyer Advisor', 'Procurement & quality', 
   ARRAY['buyer'::actor_role_type, 'exporter'::actor_role_type, 'importer'::actor_role_type], 
   'specialist-buyer-advisor', true),
  ('aggregation_advisor', 'Aggregation Advisor', 'Volume & logistics', 
   ARRAY['aggregator'::actor_role_type, 'commodity_trader'::actor_role_type], 
   'specialist-aggregator-advisor', true),
  ('extension_advisor', 'Extension Advisor', 'Capacity & training', 
   ARRAY['extension_agent'::actor_role_type, 'ngo'::actor_role_type, 'university'::actor_role_type], 
   'specialist-extension-advisor', true),
  ('finance_advisor', 'Finance Advisor', 'Credit & insurance', 
   ARRAY['financial_institution'::actor_role_type, 'insurance_provider'::actor_role_type], 
   'specialist-finance-advisor', true),
  ('marketplace_advisor', 'Marketplace Advisor', 'Market dynamics', 
   ARRAY['farmer'::actor_role_type, 'buyer'::actor_role_type, 'commodity_trader'::actor_role_type], 
   'specialist-marketplace-advisor', true)
ON CONFLICT (code) DO NOTHING;

SELECT COUNT(*) as advisor_count FROM specialist_advisors;
```

**Expected Output:**
```
 advisor_count
---------------
             7
(1 row)
```

### Phase 4: Health Checks

**Duration:** ~5 minutes

```bash
# 1. Database connectivity
psql -h $DB_HOST -U postgres -d $DB_NAME -c "SELECT app.health();"

# 2. New tables populated
psql -h $DB_HOST -U postgres -d $DB_NAME -c "
  SELECT 
    'actor_roles' as table_name, COUNT(*) as row_count FROM actor_roles
  UNION ALL
  SELECT 'onboarding_state', COUNT(*) FROM onboarding_state
  UNION ALL
  SELECT 'routing_history', COUNT(*) FROM routing_history
  UNION ALL
  SELECT 'conversation_intelligence', COUNT(*) FROM conversation_intelligence
  UNION ALL
  SELECT 'actor_opportunity_matches', COUNT(*) FROM actor_opportunity_matches
  UNION ALL
  SELECT 'specialist_advisors', COUNT(*) FROM specialist_advisors;
"

# 3. RLS policies enabled
psql -h $DB_HOST -U postgres -d $DB_NAME -c "
  SELECT tablename, COUNT(*) as policy_count
  FROM pg_policies
  WHERE tablename IN ('actor_roles', 'onboarding_state', 'routing_history', 'conversation_intelligence', 'actor_opportunity_matches')
  GROUP BY tablename;
"

# 4. Edge Functions responding
for func in pulseid-gateway specialist-farmer-advisor specialist-buyer-advisor specialist-processor-advisor specialist-aggregator-advisor specialist-finance-advisor specialist-extension-advisor; do
  echo "Testing $func..."
  curl -s -X POST https://jmltamnqlqewwsqvcvme.functions.supabase.co/$func \
    -H "Content-Type: application/json" \
    -d '{"actor_id": "test", "message": "test"}' | jq .
  echo ""
done
```

### Phase 5: Backward Compatibility Verification

**Duration:** ~10 minutes

```bash
# Test 1: Existing farmers can still register farms
curl -X POST https://jmltamnqlqewwsqvcvme.functions.supabase.co/test-backward-compat \
  -H "Content-Type: application/json" \
  -d '{
    "test": "farmer_farm_registration",
    "phone": "2348111111111",
    "farm_name": "Test Farm",
    "commodity": "maize"
  }'

# Test 2: Existing conversations still queryable
psql -h $DB_HOST -U postgres -d $DB_NAME -c "
  SELECT COUNT(*) as conversation_count FROM conversations;
"

# Test 3: Dashboard views functional
psql -h $DB_HOST -U postgres -d $DB_NAME -c "
  SELECT * FROM mv_dashboard_summary LIMIT 1;
"

# Test 4: Pulse scores intact
psql -h $DB_HOST -U postgres -d $DB_NAME -c "
  SELECT COUNT(*) as pulse_score_count FROM pulse_scores;
"
```

---

## Monitoring & Alerting (Post-Deployment)

### Key Metrics to Track

```sql
-- Onboarding completion rate
SELECT 
  DATE(created_at) as date,
  COUNT(*) as onboardings_started,
  COUNT(CASE WHEN completed_at IS NOT NULL THEN 1 END) as onboardings_completed,
  ROUND(100.0 * COUNT(CASE WHEN completed_at IS NOT NULL THEN 1 END) / COUNT(*), 2) as completion_rate
FROM onboarding_state
WHERE created_at > NOW() - INTERVAL '7 days'
GROUP BY DATE(created_at)
ORDER BY date DESC;

-- Routing accuracy
SELECT 
  detected_intent,
  routed_to,
  COUNT(*) as count,
  AVG(confidence) as avg_confidence
FROM routing_history
WHERE created_at > NOW() - INTERVAL '24 hours'
GROUP BY detected_intent, routed_to
ORDER BY count DESC;

-- Opportunity matches created
SELECT 
  DATE(created_at) as date,
  match_type,
  COUNT(*) as matches_proposed,
  COUNT(CASE WHEN status = 'accepted' THEN 1 END) as matches_accepted,
  ROUND(100.0 * COUNT(CASE WHEN status = 'accepted' THEN 1 END) / COUNT(*), 2) as acceptance_rate
FROM actor_opportunity_matches
WHERE created_at > NOW() - INTERVAL '7 days'
GROUP BY DATE(created_at), match_type
ORDER BY date DESC;

-- Multi-role adoption
SELECT 
  COUNT(DISTINCT actor_id) as actors_with_roles,
  AVG(role_count) as avg_roles_per_actor,
  MAX(role_count) as max_roles
FROM (
  SELECT actor_id, COUNT(*) as role_count
  FROM actor_roles
  GROUP BY actor_id
) sub;
```

### Alert Thresholds

| Alert | Threshold | Action |
|-------|-----------|--------|
| Onboarding completion rate < 60% | 2 hours | Review questions; check intent detection |
| Routing average confidence < 0.70 | 1 hour | Retrain intent classifier |
| Match acceptance rate < 30% | 4 hours | Review match algorithm scoring |
| Edge Function error rate > 5% | 30 min | Check logs; rollback if necessary |
| Database query latency > 500ms | 1 hour | Review indexes; optimize queries |

---

## Rollback Procedure

**If critical issues arise, execute rollback within 15 minutes:**

### Immediate Actions

```bash
# 1. Disable Food Systems Gateway (revert to original pulseid-intake)
echo "Reverting to original gateway..."
supabase functions deploy pulseid-intake --no-verify-jwt

# 2. Disable all specialist advisors
psql -h $DB_HOST -U postgres -d $DB_NAME -c "
  UPDATE specialist_advisors SET active = false;
"

# 3. Monitor error rates
watch -n 5 "curl -s https://jmltamnqlqewwsqvcvme.functions.supabase.co/pulseid-intake -d '{}' | jq ."
```

### Database Rollback (if needed)

```bash
# 1. Identify backup
ls -lah backup-pre-gateway-*.dump | tail -1

# 2. Stop all connections
psql -h $DB_HOST -U postgres -c "
  SELECT pg_terminate_backend(pid)
  FROM pg_stat_activity
  WHERE datname = 'farmerpulse' AND state = 'active';
"

# 3. Drop new schema objects (careful!)
psql -h $DB_HOST -U postgres -d $DB_NAME -f rollback-0009-0012.sql

# 4. Restore from backup
pg_restore --host=$DB_HOST --username=postgres --password=$DB_PASSWORD \
  --format=custom --clean --no-owner \
  --dbname=$DB_NAME backup-pre-gateway-$(date -r backup-pre-gateway-*.dump +%s).dump
```

**Verification after rollback:**

```bash
# Confirm new tables removed
psql -h $DB_HOST -U postgres -d $DB_NAME -c "
  SELECT tablename FROM pg_tables 
  WHERE tablename IN ('actor_roles', 'onboarding_state', 'routing_history', 
                      'conversation_intelligence', 'actor_opportunity_matches');
"

# Should return: (0 rows)
```

---

## Post-Deployment Validation

### Week 1 Checklist

- [ ] **Day 1:**
  - [ ] No error spikes in logs
  - [ ] All Edge Functions responding
  - [ ] Database performance normal
  - [ ] Onboarding completion > 60%

- [ ] **Day 2-3:**
  - [ ] Multi-role adoption tracking
  - [ ] Routing accuracy > 80%
  - [ ] Opportunity matches > 5/day
  - [ ] Zero backward compatibility issues

- [ ] **Day 4-7:**
  - [ ] Run full integration test suite
  - [ ] Review error logs for patterns
  - [ ] Measure performance baseline
  - [ ] Gather user feedback

### Success Criteria

✅ **Deployment successful if:**
- No emergency rollbacks required
- Onboarding completion rate > 60%
- Routing confidence > 0.75 average
- Zero data loss
- All existing workflows operational
- Match acceptance rate > 25%

---

## Support & Troubleshooting

### Common Issues

**Issue:** Onboarding questions not advancing
- **Cause:** Pending field not properly saved
- **Fix:** Check `app.save_onboarding_response()` logic; verify RLS policies

**Issue:** Routing always defaulting to "general"
- **Cause:** Intent detection confidence too low
- **Fix:** Review intent keywords in `pulseid-gateway/main.ts`; increase threshold

**Issue:** Opportunity matches not proposed
- **Cause:** `batch_propose_matches()` not invoked; matching functions returning empty
- **Fix:** Manually trigger matching; verify actor roles in `actor_roles` table

**Issue:** Edge Function timeouts
- **Cause:** Database query too slow; too many network calls
- **Fix:** Enable indexes; cache advisor registry; reduce match search scope

### Logging

```bash
# View Edge Function logs
supabase functions list
supabase functions logs pulseid-gateway

# View database activity
psql -h $DB_HOST -U postgres -d $DB_NAME -c "
  SELECT query, calls, total_time FROM pg_stat_statements
  WHERE query LIKE '%actor_roles%'
  ORDER BY total_time DESC;
"

# Check RLS policy violations
psql -h $DB_HOST -U postgres -d $DB_NAME -c "
  SELECT * FROM audit_logs WHERE action LIKE '%policy%'
  ORDER BY created_at DESC LIMIT 20;
"
```

---

## Contacts & Escalation

| Role | Contact | On-Call |
|------|---------|----------|
| Lead Architect | andrew@cultivate.ng | 24/7 |
| Database Admin | dba@supabase.io | 24/7 |
| Edge Functions | edge-support@supabase.io | Business hours |
| Product Lead | product@farmerpulse.io | Business hours |

---

## Sign-Off

**Deployment executed by:** ____________________
**Date & Time:** ____________________
**Status:** ☐ Success | ☐ Rollback | ☐ Partial
**Notes:** ____________________
