-- ============================================================
-- 0011: Row-Level Security for Multi-Role Tables
-- Policies: actors see own records, platform_admin sees all,
--           org members see org-scoped records
-- ============================================================

-- actor_roles: actor or platform_admin
CREATE POLICY actor_roles_access ON public.actor_roles FOR ALL TO authenticated
USING (
  app.is_platform_admin()
  OR (actor_id = app.current_actor_id())
  OR (app.actor_org_id(actor_id) IN (SELECT app.current_org_ids()))
)
WITH CHECK (
  app.is_platform_admin()
  OR (actor_id = app.current_actor_id())
  OR (app.actor_org_id(actor_id) IN (SELECT app.current_org_ids()))
);

-- onboarding_state: actor only (not shared)
CREATE POLICY onboarding_state_access ON public.onboarding_state FOR ALL TO authenticated
USING (
  app.is_platform_admin()
  OR (actor_id = app.current_actor_id())
)
WITH CHECK (
  app.is_platform_admin()
  OR (actor_id = app.current_actor_id())
);

-- routing_history: actor or org members (analytics)
CREATE POLICY routing_history_access ON public.routing_history FOR ALL TO authenticated
USING (
  app.is_platform_admin()
  OR (actor_id = app.current_actor_id())
  OR (app.actor_org_id(actor_id) IN (SELECT app.current_org_ids()))
)
WITH CHECK (
  app.is_platform_admin()
  OR (actor_id = app.current_actor_id())
  OR (app.actor_org_id(actor_id) IN (SELECT app.current_org_ids()))
);

-- conversation_intelligence: actor or org members (ecosystem insights)
CREATE POLICY conversation_intelligence_access ON public.conversation_intelligence FOR ALL TO authenticated
USING (
  app.is_platform_admin()
  OR (actor_id = app.current_actor_id())
  OR (app.actor_org_id(actor_id) IN (SELECT app.current_org_ids()))
)
WITH CHECK (
  app.is_platform_admin()
  OR (actor_id = app.current_actor_id())
  OR (app.actor_org_id(actor_id) IN (SELECT app.current_org_ids()))
);

-- actor_opportunity_matches: both actors can see, org can see (coordination)
CREATE POLICY actor_opportunity_matches_access ON public.actor_opportunity_matches FOR ALL TO authenticated
USING (
  app.is_platform_admin()
  OR (actor_a_id = app.current_actor_id())
  OR (actor_b_id = app.current_actor_id())
  OR (app.actor_org_id(actor_a_id) IN (SELECT app.current_org_ids()))
  OR (app.actor_org_id(actor_b_id) IN (SELECT app.current_org_ids()))
)
WITH CHECK (
  app.is_platform_admin()
  OR (actor_a_id = app.current_actor_id())
  OR (actor_b_id = app.current_actor_id())
);
