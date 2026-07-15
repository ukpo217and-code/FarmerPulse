-- ============================================================
-- 0010: Multi-Role Support Tables
-- Enables single user to hold multiple food system roles
-- ============================================================

-- Table: actor_roles
-- Purpose: Map actors to zero or more roles
-- Key: Never delete existing roles; append new ones.
-- One actor can be: farmer + processor + buyer simultaneously

CREATE TABLE public.actor_roles (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  actor_id uuid NOT NULL REFERENCES public.actors(id) ON DELETE CASCADE,
  role public.actor_role_type NOT NULL,
  activated_at timestamp with time zone DEFAULT now(),
  metadata jsonb DEFAULT '{}'::jsonb,
  created_at timestamp with time zone DEFAULT now(),
  UNIQUE(actor_id, role)
);

CREATE INDEX idx_actor_roles_actor_id ON public.actor_roles(actor_id);
CREATE INDEX idx_actor_roles_role ON public.actor_roles(role);

-- Table: onboarding_state
-- Purpose: Track onboarding progress (name -> state -> organization -> commodity -> role)
-- Key: Pending questions are asked sequentially; responses saved immediately.
-- One row per actor.

CREATE TABLE public.onboarding_state (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  actor_id uuid NOT NULL REFERENCES public.actors(id) ON DELETE CASCADE UNIQUE,
  current_step text NOT NULL DEFAULT 'name',
  pending_response_field text,
  responses jsonb DEFAULT '{}'::jsonb,
  completed_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now()
);

CREATE INDEX idx_onboarding_state_actor_id ON public.onboarding_state(actor_id);
CREATE INDEX idx_onboarding_state_completed ON public.onboarding_state(completed_at);

-- Table: routing_history
-- Purpose: Log every message, its detected intent, and which specialist it was routed to
-- Key: Enables analytics, re-training, and debugging of routing logic.

CREATE TABLE public.routing_history (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  actor_id uuid NOT NULL REFERENCES public.actors(id) ON DELETE CASCADE,
  input_text text NOT NULL,
  detected_intent text,
  detected_roles jsonb DEFAULT '[]'::jsonb,
  routed_to text,
  confidence numeric(5,2),
  created_at timestamp with time zone DEFAULT now()
);

CREATE INDEX idx_routing_history_actor_id ON public.routing_history(actor_id);
CREATE INDEX idx_routing_history_intent ON public.routing_history(detected_intent);
CREATE INDEX idx_routing_history_routed_to ON public.routing_history(routed_to);

-- Table: conversation_intelligence
-- Purpose: Extract structured intelligence from each conversation turn
-- Key: Records actor, location, commodity, intent, need, constraint, opportunity, urgency, sentiment.
-- Enables matching, analytics, and ecosystem coordination.

CREATE TABLE public.conversation_intelligence (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  actor_id uuid NOT NULL REFERENCES public.actors(id) ON DELETE CASCADE,
  conversation_id uuid,
  actor text,
  location jsonb,
  commodity text,
  intent text,
  need text,
  constraint_text text,
  opportunity text,
  urgency text,
  sentiment text,
  potential_matches jsonb DEFAULT '[]'::jsonb,
  confidence numeric(5,2),
  created_at timestamp with time zone DEFAULT now()
);

CREATE INDEX idx_conv_intel_actor_id ON public.conversation_intelligence(actor_id);
CREATE INDEX idx_conv_intel_commodity ON public.conversation_intelligence(commodity);
CREATE INDEX idx_conv_intel_intent ON public.conversation_intelligence(intent);
CREATE INDEX idx_conv_intel_created ON public.conversation_intelligence(created_at);

-- Table: actor_opportunity_matches
-- Purpose: Record proposed connections between actors (farmer ↔ buyer, processor ↔ aggregator, etc.)
-- Key: One match per (actor_a, actor_b, match_type) tuple; status progresses from proposed → accepted/rejected → completed.

CREATE TABLE public.actor_opportunity_matches (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  actor_a_id uuid NOT NULL REFERENCES public.actors(id) ON DELETE CASCADE,
  actor_b_id uuid NOT NULL REFERENCES public.actors(id) ON DELETE CASCADE,
  match_type text NOT NULL,
  score numeric(6,2),
  commodity text,
  location jsonb,
  proposed_date timestamp with time zone,
  status text DEFAULT 'proposed'::text,
  metadata jsonb DEFAULT '{}'::jsonb,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  UNIQUE(actor_a_id, actor_b_id, match_type),
  CONSTRAINT check_actors_different CHECK (actor_a_id != actor_b_id),
  CONSTRAINT check_status_valid CHECK (status IN ('proposed', 'accepted', 'rejected', 'completed'))
);

CREATE INDEX idx_matches_actor_a ON public.actor_opportunity_matches(actor_a_id);
CREATE INDEX idx_matches_actor_b ON public.actor_opportunity_matches(actor_b_id);
CREATE INDEX idx_matches_status ON public.actor_opportunity_matches(status);
CREATE INDEX idx_matches_created ON public.actor_opportunity_matches(created_at);

-- Enable RLS on all new tables
ALTER TABLE public.actor_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.onboarding_state ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.routing_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversation_intelligence ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.actor_opportunity_matches ENABLE ROW LEVEL SECURITY;

-- Set updated_at trigger for onboarding_state
CREATE TRIGGER onboarding_state_set_updated_at
  BEFORE UPDATE ON public.onboarding_state
  FOR EACH ROW
  EXECUTE FUNCTION app.set_updated_at();

CREATE TRIGGER actor_opportunity_matches_set_updated_at
  BEFORE UPDATE ON public.actor_opportunity_matches
  FOR EACH ROW
  EXECUTE FUNCTION app.set_updated_at();
