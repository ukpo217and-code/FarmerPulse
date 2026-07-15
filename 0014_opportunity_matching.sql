-- ============================================================
-- 0014: Opportunity Matching Engine Queries
-- Find complementary actors & automate proposals
-- ============================================================

-- Find farmer matches for buyers (by commodity + location)
CREATE OR REPLACE FUNCTION app.find_farmers_for_buyer(
  p_buyer_id uuid,
  p_commodity text,
  p_quantity numeric DEFAULT NULL,
  p_state text DEFAULT NULL
)
 RETURNS TABLE(
   farmer_id uuid,
   farmer_name text,
   farm_name text,
   commodity text,
   available_qty numeric,
   location_match numeric,
   score numeric
 )
 LANGUAGE sql
 STABLE
 SET search_path TO 'app', 'public', 'pg_temp'
AS $function$
  SELECT
    a.id,
    a.full_name,
    f.farm_name,
    f.commodity,
    COALESCE(f.area_ha * 100, 0),  -- Estimate available
    CASE
      WHEN p_state IS NOT NULL AND a.state = p_state THEN 1.0
      WHEN p_state IS NOT NULL AND a.state IS NOT NULL THEN 0.5
      ELSE 0.3
    END,
    (
      CASE WHEN f.commodity = p_commodity THEN 1.0 ELSE 0.5 END * 0.5 +
      CASE
        WHEN p_state IS NOT NULL AND a.state = p_state THEN 1.0
        WHEN p_state IS NOT NULL AND a.state IS NOT NULL THEN 0.5
        ELSE 0.3
      END * 0.5
    ) as score
  FROM actors a
  JOIN farms f ON f.actor_id = a.id
  WHERE a.id != p_buyer_id
    AND (p_commodity IS NULL OR f.commodity = p_commodity)
    AND app.actor_has_role(a.id, 'farmer'::actor_role_type)
  ORDER BY score DESC
  LIMIT 10;
$function$;

-- Find buyers for farmers (by commodity + location)
CREATE OR REPLACE FUNCTION app.find_buyers_for_farmer(
  p_farmer_id uuid,
  p_commodity text,
  p_state text DEFAULT NULL
)
 RETURNS TABLE(
   buyer_id uuid,
   buyer_name text,
   buyer_type text,
   score numeric
 )
 LANGUAGE sql
 STABLE
 SET search_path TO 'app', 'public', 'pg_temp'
AS $function$
  SELECT
    a.id,
    a.full_name,
    COALESCE(b.buyer_type, 'general'),
    (
      CASE WHEN p_state IS NOT NULL AND a.state = p_state THEN 1.0 ELSE 0.7 END
    ) as score
  FROM actors a
  LEFT JOIN buyers b ON b.actor_id = a.id
  WHERE a.id != p_farmer_id
    AND app.actor_has_role(a.id, 'buyer'::actor_role_type)
    AND b.active = true
  ORDER BY score DESC
  LIMIT 10;
$function$;

-- Find aggregators for farmers (high-volume needs)
CREATE OR REPLACE FUNCTION app.find_aggregators_for_farmer(
  p_farmer_id uuid,
  p_commodity text,
  p_state text DEFAULT NULL
)
 RETURNS TABLE(
   aggregator_id uuid,
   aggregator_name text,
   score numeric
 )
 LANGUAGE sql
 STABLE
 SET search_path TO 'app', 'public', 'pg_temp'
AS $function$
  SELECT
    a.id,
    a.full_name,
    CASE
      WHEN p_state IS NOT NULL AND a.state = p_state THEN 0.95
      ELSE 0.75
    END as score
  FROM actors a
  WHERE a.id != p_farmer_id
    AND app.actor_has_role(a.id, 'aggregator'::actor_role_type)
  ORDER BY score DESC
  LIMIT 5;
$function$;

-- Find processors for commodity traders (sourcing)
CREATE OR REPLACE FUNCTION app.find_processors_for_trader(
  p_trader_id uuid,
  p_commodity text
)
 RETURNS TABLE(
   processor_id uuid,
   processor_name text,
   score numeric
 )
 LANGUAGE sql
 STABLE
 SET search_path TO 'app', 'public', 'pg_temp'
AS $function$
  SELECT
    a.id,
    a.full_name,
    0.85 as score
  FROM actors a
  WHERE a.id != p_trader_id
    AND (app.actor_has_role(a.id, 'processor'::actor_role_type)
         OR app.actor_has_role(a.id, 'manufacturer'::actor_role_type))
  ORDER BY score DESC
  LIMIT 5;
$function$;

-- Find input suppliers for farmers
CREATE OR REPLACE FUNCTION app.find_input_suppliers_for_farmer(
  p_farmer_id uuid,
  p_input_type text,
  p_state text DEFAULT NULL
)
 RETURNS TABLE(
   supplier_id uuid,
   supplier_name text,
   supplier_type text,
   score numeric
 )
 LANGUAGE sql
 STABLE
 SET search_path TO 'app', 'public', 'pg_temp'
AS $function$
  SELECT
    i.actor_id,
    a.full_name,
    COALESCE(i.supplier_type, 'general'),
    CASE
      WHEN i.products @> jsonb_build_array(p_input_type) THEN 1.0
      WHEN p_state IS NOT NULL AND a.state = p_state THEN 0.85
      ELSE 0.7
    END as score
  FROM input_suppliers i
  JOIN actors a ON a.id = i.actor_id
  WHERE i.active = true
    AND a.id != p_farmer_id
  ORDER BY score DESC
  LIMIT 5;
$function$;

-- Find financial institutions for eligible actors
CREATE OR REPLACE FUNCTION app.find_financial_matches(
  p_actor_id uuid,
  p_loan_amount numeric DEFAULT NULL
)
 RETURNS TABLE(
   institution_id uuid,
   institution_name text,
   institution_type text,
   score numeric
 )
 LANGUAGE sql
 STABLE
 SET search_path TO 'app', 'public', 'pg_temp'
AS $function$
  SELECT
    f.id,
    f.organization_name,
    f.institution_type,
    0.80 as score
  FROM financial_institutions f
  WHERE f.active = true
  ORDER BY f.created_at DESC
  LIMIT 5;
$function$;

-- Find exporters for certified producers
CREATE OR REPLACE FUNCTION app.find_exporters_for_producer(
  p_producer_id uuid,
  p_commodity text
)
 RETURNS TABLE(
   exporter_id uuid,
   exporter_name text,
   score numeric
 )
 LANGUAGE sql
 STABLE
 SET search_path TO 'app', 'public', 'pg_temp'
AS $function$
  SELECT
    a.id,
    a.full_name,
    0.88 as score
  FROM actors a
  WHERE a.id != p_producer_id
    AND app.actor_has_role(a.id, 'exporter'::actor_role_type)
  ORDER BY score DESC
  LIMIT 3;
$function$;

-- Batch match operation: propose all matches for an actor
CREATE OR REPLACE FUNCTION app.batch_propose_matches(p_actor_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO 'app', 'public', 'pg_temp'
AS $function$
DECLARE
  v_count integer := 0;
  v_roles actor_role_type[];
  r RECORD;
BEGIN
  -- Get actor roles
  SELECT array_agg(role) INTO v_roles
  FROM actor_roles
  WHERE actor_id = p_actor_id;

  -- If farmer, find buyer/aggregator matches
  IF v_roles && ARRAY['farmer'::actor_role_type] THEN
    FOR r IN
      SELECT farmer_id, commodity, score
      FROM app.find_farmers_for_buyer(p_actor_id, NULL)
      LIMIT 5
    LOOP
      PERFORM app.propose_actor_match(p_actor_id, r.farmer_id, 'farmer-buyer', r.score);
      v_count := v_count + 1;
    END LOOP;
  END IF;

  -- If buyer, find farmer matches
  IF v_roles && ARRAY['buyer'::actor_role_type] THEN
    FOR r IN
      SELECT buyer_id, score
      FROM app.find_buyers_for_farmer(p_actor_id, NULL)
      LIMIT 5
    LOOP
      PERFORM app.propose_actor_match(p_actor_id, r.buyer_id, 'farmer-buyer', r.score);
      v_count := v_count + 1;
    END LOOP;
  END IF;

  RETURN v_count;
END;
$function$;
