-- ============================================================
-- 0012: Multi-Role Helper Functions
-- Core operations: add role, get roles, onboarding state machine,
--                 conversation intelligence extraction, opportunity matching
-- ============================================================

-- ========== Actor Role Management ==========

CREATE OR REPLACE FUNCTION app.add_actor_role(p_actor_id uuid, p_role actor_role_type)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO 'app', 'public', 'pg_temp'
AS $function$
DECLARE
  v_id uuid;
BEGIN
  INSERT INTO actor_roles(actor_id, role)
  VALUES(p_actor_id, p_role)
  ON CONFLICT (actor_id, role) DO NOTHING
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$function$;

CREATE OR REPLACE FUNCTION app.actor_all_roles(p_actor_id uuid)
 RETURNS SETOF actor_role_type
 LANGUAGE sql
 STABLE
 SET search_path TO 'app', 'public', 'pg_temp'
AS $function$
  SELECT role FROM actor_roles WHERE actor_id = p_actor_id ORDER BY activated_at;
$function$;

CREATE OR REPLACE FUNCTION app.actor_has_role(p_actor_id uuid, p_role actor_role_type)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'app', 'public', 'pg_temp'
AS $function$
  SELECT EXISTS(SELECT 1 FROM actor_roles WHERE actor_id = p_actor_id AND role = p_role);
$function$;

CREATE OR REPLACE FUNCTION app.remove_actor_role(p_actor_id uuid, p_role actor_role_type)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'app', 'public', 'pg_temp'
AS $function$
BEGIN
  DELETE FROM actor_roles WHERE actor_id = p_actor_id AND role = p_role;
END;
$function$;

-- ========== Onboarding State Machine ==========

CREATE OR REPLACE FUNCTION app.start_onboarding(p_actor_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO 'app', 'public', 'pg_temp'
AS $function$
DECLARE
  v_id uuid;
BEGIN
  INSERT INTO onboarding_state(actor_id, current_step, pending_response_field)
  VALUES(p_actor_id, 'name', 'full_name')
  ON CONFLICT (actor_id) DO UPDATE
  SET updated_at = NOW()
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$function$;

CREATE OR REPLACE FUNCTION app.get_onboarding_state(p_actor_id uuid)
 RETURNS TABLE(
   id uuid,
   current_step text,
   pending_response_field text,
   responses jsonb,
   completed_at timestamp with time zone
 )
 LANGUAGE sql
 STABLE
 SET search_path TO 'app', 'public', 'pg_temp'
AS $function$
  SELECT id, current_step, pending_response_field, responses, completed_at
  FROM onboarding_state
  WHERE actor_id = p_actor_id;
$function$;

CREATE OR REPLACE FUNCTION app.get_pending_field(p_actor_id uuid)
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO 'app', 'public', 'pg_temp'
AS $function$
  SELECT pending_response_field FROM onboarding_state WHERE actor_id = p_actor_id;
$function$;

CREATE OR REPLACE FUNCTION app.save_onboarding_response(p_actor_id uuid, p_field text, p_value text)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'app', 'public', 'pg_temp'
AS $function$
DECLARE
  v_next_field text;
BEGIN
  -- Save response
  UPDATE onboarding_state
  SET responses = responses || jsonb_build_object(p_field, p_value),
      updated_at = NOW()
  WHERE actor_id = p_actor_id;

  -- Determine next field
  v_next_field := CASE p_field
    WHEN 'full_name' THEN 'state'
    WHEN 'state' THEN 'organization'
    WHEN 'organization' THEN 'commodity'
    WHEN 'commodity' THEN 'role'
    ELSE NULL
  END;

  -- Advance to next step or mark complete
  IF v_next_field IS NOT NULL THEN
    UPDATE onboarding_state
    SET pending_response_field = v_next_field,
        current_step = v_next_field
    WHERE actor_id = p_actor_id;
  ELSE
    UPDATE onboarding_state
    SET pending_response_field = NULL,
        completed_at = NOW()
    WHERE actor_id = p_actor_id;
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION app.is_onboarding_complete(p_actor_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'app', 'public', 'pg_temp'
AS $function$
  SELECT COALESCE(completed_at IS NOT NULL, FALSE)
  FROM onboarding_state
  WHERE actor_id = p_actor_id;
$function$;

-- ========== Routing History ==========

CREATE OR REPLACE FUNCTION app.log_routing(p_actor_id uuid, p_input_text text, p_intent text, p_routed_to text, p_confidence numeric DEFAULT 0.5)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO 'app', 'public', 'pg_temp'
AS $function$
DECLARE
  v_id uuid;
BEGIN
  INSERT INTO routing_history(actor_id, input_text, detected_intent, routed_to, confidence)
  VALUES(p_actor_id, p_input_text, p_intent, p_routed_to, p_confidence)
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$function$;

-- ========== Conversation Intelligence Extraction ==========

CREATE OR REPLACE FUNCTION app.extract_conversation_intelligence(
  p_actor_id uuid,
  p_conversation_id uuid,
  p_actor text,
  p_location jsonb,
  p_commodity text,
  p_intent text,
  p_need text,
  p_constraint text,
  p_opportunity text,
  p_urgency text,
  p_sentiment text,
  p_confidence numeric DEFAULT 0.5
)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO 'app', 'public', 'pg_temp'
AS $function$
DECLARE
  v_id uuid;
BEGIN
  INSERT INTO conversation_intelligence(
    actor_id, conversation_id, actor, location, commodity, intent, need,
    constraint_text, opportunity, urgency, sentiment, confidence
  )
  VALUES(
    p_actor_id, p_conversation_id, p_actor, p_location, p_commodity, p_intent, p_need,
    p_constraint, p_opportunity, p_urgency, p_sentiment, p_confidence
  )
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$function$;

CREATE OR REPLACE FUNCTION app.get_actor_intelligence_summary(p_actor_id uuid)
 RETURNS TABLE(
   total_conversations integer,
   unique_intents integer,
   primary_commodity text,
   avg_sentiment numeric,
   opportunities_identified integer
 )
 LANGUAGE sql
 STABLE
 SET search_path TO 'app', 'public', 'pg_temp'
AS $function$
  SELECT
    COUNT(DISTINCT conversation_id)::integer,
    COUNT(DISTINCT intent)::integer,
    (array_agg(commodity))[1],
    AVG(CASE WHEN sentiment = 'positive' THEN 1 WHEN sentiment = 'negative' THEN -1 ELSE 0 END),
    COUNT(CASE WHEN opportunity IS NOT NULL THEN 1 END)::integer
  FROM conversation_intelligence
  WHERE actor_id = p_actor_id;
$function$;

-- ========== Opportunity Matching ==========

CREATE OR REPLACE FUNCTION app.propose_actor_match(
  p_actor_a_id uuid,
  p_actor_b_id uuid,
  p_match_type text,
  p_score numeric,
  p_commodity text DEFAULT NULL,
  p_location jsonb DEFAULT NULL
)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO 'app', 'public', 'pg_temp'
AS $function$
DECLARE
  v_id uuid;
BEGIN
  INSERT INTO actor_opportunity_matches(
    actor_a_id, actor_b_id, match_type, score, commodity, location
  )
  VALUES(p_actor_a_id, p_actor_b_id, p_match_type, p_score, p_commodity, p_location)
  ON CONFLICT (actor_a_id, actor_b_id, match_type)
  DO UPDATE SET score = EXCLUDED.score, updated_at = NOW()
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$function$;

CREATE OR REPLACE FUNCTION app.accept_match(p_match_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'app', 'public', 'pg_temp'
AS $function$
BEGIN
  UPDATE actor_opportunity_matches
  SET status = 'accepted', updated_at = NOW()
  WHERE id = p_match_id;
END;
$function$;

CREATE OR REPLACE FUNCTION app.reject_match(p_match_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'app', 'public', 'pg_temp'
AS $function$
BEGIN
  UPDATE actor_opportunity_matches
  SET status = 'rejected', updated_at = NOW()
  WHERE id = p_match_id;
END;
$function$;

CREATE OR REPLACE FUNCTION app.get_actor_matches(p_actor_id uuid)
 RETURNS TABLE(
   id uuid,
   other_actor_id uuid,
   other_actor_name text,
   match_type text,
   commodity text,
   score numeric,
   status text
 )
 LANGUAGE sql
 STABLE
 SET search_path TO 'app', 'public', 'pg_temp'
AS $function$
  SELECT
    am.id,
    CASE WHEN am.actor_a_id = p_actor_id THEN am.actor_b_id ELSE am.actor_a_id END,
    a.full_name,
    am.match_type,
    am.commodity,
    am.score,
    am.status
  FROM actor_opportunity_matches am
  JOIN actors a ON a.id = (CASE WHEN am.actor_a_id = p_actor_id THEN am.actor_b_id ELSE am.actor_a_id END)
  WHERE (am.actor_a_id = p_actor_id OR am.actor_b_id = p_actor_id)
  AND am.status IN ('proposed', 'accepted')
  ORDER BY am.score DESC;
$function$;
