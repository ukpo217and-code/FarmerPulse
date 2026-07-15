// supabase/functions/pulseid-gateway/main.ts
// Food Systems Gateway: Universal routing engine
// Routes all actor types to specialized advisors based on role + intent

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const supabaseUrl = Deno.env.get('SUPABASE_URL') || '';
const supabaseAnonKey = Deno.env.get('SUPABASE_ANON_KEY') || '';
const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '';

const supabase = createClient(supabaseUrl, supabaseServiceKey);

// ========== Types ==========

interface RequestBody {
  phone: string;
  message: string;
  name?: string;
}

interface OnboardingQuestion {
  type: 'question';
  priority: 'onboarding';
  message: string;
  field: string;
}

interface RoutedResponse {
  type: 'routed';
  specialist: string;
  intent: string;
  confidence: number;
  message: string;
}

interface WelcomeResponse {
  type: 'welcome';
  priority: string;
  message: string;
}

type GatewayResponse = OnboardingQuestion | RoutedResponse | WelcomeResponse;

// ========== Utility Functions ==========

function normalizePhone(phone: string): string {
  const digits = phone.replace(/[^0-9]/g, '');
  if (digits.length === 11 && digits[0] === '0') {
    return '234' + digits.substring(1);
  } else if (digits.length === 10) {
    return '234' + digits;
  }
  return digits;
}

interface IntentScore {
  [key: string]: number;
}

function detectIntent(text: string): [string, number] {
  const lowerText = text.toLowerCase();
  
  const intentKeywords: { [key: string]: string[] } = {
    'farmer_advice': ['farm', 'crop', 'harvest', 'soil', 'plant', 'grow', 'yield', 'pest', 'disease'],
    'buyer_query': ['buy', 'purchase', 'supply', 'bulk', 'order', 'price', 'sourcing', 'supplier'],
    'processor_guidance': ['process', 'add value', 'production', 'capacity', 'factory', 'quality'],
    'aggregator_needs': ['aggregate', 'collect', 'bulk', 'volume', 'storage', 'logistics'],
    'finance_inquiry': ['loan', 'credit', 'finance', 'insurance', 'fund', 'credit', 'disbursement'],
    'marketplace': ['market', 'sell', 'list', 'price check', 'trading', 'commodity'],
    'extension_support': ['training', 'technical', 'advisory', 'guidance', 'coaching'],
    'mechanization': ['machine', 'equipment', 'tractor', 'mechaniz', 'labour'],
    'export_docs': ['export', 'international', 'shipping', 'documentation', 'certificate'],
    'certification': ['certif', 'standard', 'organic', 'quality', 'compliance'],
    'climate_risk': ['weather', 'rain', 'drought', 'climate', 'risk', 'disaster'],
    'policy': ['government', 'policy', 'regulation', 'subsidy', 'program'],
    'research': ['research', 'study', 'innovation', 'experiment', 'technology'],
    'grant': ['grant', 'funding', 'fund', 'scholarship', 'donation'],
    'business': ['business', 'enterprise', 'startup', 'investment', 'profit'],
  };

  const scores: IntentScore = {};
  for (const [intent, keywords] of Object.entries(intentKeywords)) {
    const matches = keywords.filter(kw => lowerText.includes(kw)).length;
    scores[intent] = keywords.length > 0 ? matches / keywords.length : 0;
  }

  const maxIntent = Object.entries(scores).reduce((a, b) => a[1] > b[1] ? a : b);
  const bestIntent = maxIntent ? maxIntent[0] : 'general';
  const confidence = Math.min(maxIntent ? maxIntent[1] : 0.5, 1.0);

  return [bestIntent, confidence];
}

// ========== Database Operations ==========

async function getOrCreateActor(phone: string, name: string = 'Unknown User'): Promise<any> {
  const normalizedPhone = normalizePhone(phone);
  
  // Try to get existing actor
  const { data: existing } = await supabase
    .from('actors')
    .select('*')
    .eq('phone', normalizedPhone)
    .single()
    .catch(() => ({ data: null }));

  if (existing) {
    return existing;
  }

  // Create new actor
  const { data: newActor, error } = await supabase
    .from('actors')
    .insert([
      {
        actor_number: `FP-${new Date().getFullYear()}-${Math.random().toString(36).substring(7)}`,
        actor_type: 'farmer', // Default type; roles added via actor_roles
        full_name: name,
        phone: normalizedPhone,
        active: true,
        metadata: { source: 'gateway', created_at: new Date().toISOString() },
      },
    ])
    .select()
    .single();

  if (error) {
    console.error('Failed to create actor:', error);
    throw error;
  }

  return newActor;
}

async function getOnboardingState(actorId: string): Promise<any> {
  const { data } = await supabase
    .from('onboarding_state')
    .select('*')
    .eq('actor_id', actorId)
    .single()
    .catch(() => ({ data: null }));

  return data;
}

async function startOnboarding(actorId: string): Promise<string> {
  const { data, error } = await supabase
    .from('onboarding_state')
    .upsert(
      [
        {
          actor_id: actorId,
          current_step: 'name',
          pending_response_field: 'full_name',
          responses: {},
        },
      ],
      { onConflict: 'actor_id' }
    )
    .select()
    .single();

  if (error) throw error;
  return data?.pending_response_field || 'full_name';
}

async function saveOnboardingResponse(actorId: string, field: string, value: string): Promise<string | null> {
  // Call stored function to advance state machine
  const { data, error } = await supabase.rpc('app.save_onboarding_response', {
    p_actor_id: actorId,
    p_field: field,
    p_value: value,
  });

  if (error) {
    console.error('Failed to save onboarding response:', error);
    throw error;
  }

  // Get updated pending field
  const updated = await getOnboardingState(actorId);
  return updated?.pending_response_field || null;
}

async function logRouting(
  actorId: string,
  inputText: string,
  intent: string,
  routedTo: string,
  confidence: number
): Promise<void> {
  const { error } = await supabase.from('routing_history').insert([
    {
      actor_id: actorId,
      input_text: inputText,
      detected_intent: intent,
      routed_to: routedTo,
      confidence,
    },
  ]);

  if (error) {
    console.warn('Failed to log routing:', error);
    // Non-blocking; continue
  }
}

async function handleOnboarding(
  actorId: string,
  message: string,
  onboardingState: any
): Promise<OnboardingQuestion | null> {
  const pendingField = onboardingState?.pending_response_field;

  if (!pendingField) {
    // Onboarding not started
    await startOnboarding(actorId);
    return {
      type: 'question',
      priority: 'onboarding',
      message: 'Welcome to Pulse!\n\nWhat is your full name?',
      field: 'full_name',
    };
  }

  // Save response and advance
  const nextField = await saveOnboardingResponse(actorId, pendingField, message);

  const questions: { [key: string]: string } = {
    state: 'Which state are you in?',
    organization: 'What organization are you with? (or type "none")',
    commodity: "What's your main commodity or business activity?",
    role: 'What role(s) do you play? (e.g., farmer, buyer, processor)',
  };

  if (nextField && nextField in questions) {
    return {
      type: 'question',
      priority: 'onboarding',
      message: questions[nextField],
      field: nextField,
    };
  }

  // Onboarding complete
  return null;
}

// ========== Main Handler ==========

Deno.serve(async (req: Request) => {
  try {
    if (req.method === 'OPTIONS') {
      return new Response('ok', { headers: { 'Access-Control-Allow-Origin': '*' } });
    }

    const body = (await req.json()) as RequestBody;
    const { phone, message, name } = body;

    if (!phone || !message) {
      return new Response(
        JSON.stringify({ error: 'phone and message are required' }),
        {
          status: 400,
          headers: { 'Content-Type': 'application/json' },
        }
      );
    }

    // Step 1: Get or create actor
    const actor = await getOrCreateActor(phone, name);
    const actorId = actor.id;

    // Step 2: Check onboarding state
    const onboardingState = await getOnboardingState(actorId);
    const pendingField = onboardingState?.pending_response_field;

    if (pendingField) {
      const onboardingResponse = await handleOnboarding(actorId, message, onboardingState);
      if (onboardingResponse) {
        return new Response(JSON.stringify(onboardingResponse), {
          status: 200,
          headers: { 'Content-Type': 'application/json' },
        });
      }
    } else if (!onboardingState?.completed_at) {
      // Start onboarding
      const onboardingResponse = await handleOnboarding(actorId, message, null);
      if (onboardingResponse) {
        return new Response(JSON.stringify(onboardingResponse), {
          status: 200,
          headers: { 'Content-Type': 'application/json' },
        });
      }
    }

    // Step 3: Detect intent
    const [intent, confidence] = detectIntent(message);

    // Step 4: Get actor roles
    const { data: roles } = await supabase
      .from('actor_roles')
      .select('role')
      .eq('actor_id', actorId);

    const actorRoles = roles?.map((r: any) => r.role) || [];

    // Step 5: Map intent to specialist
    const specialistMap: { [key: string]: string } = {
      farmer_advice: 'farmer_advisor',
      processor_guidance: 'processor_advisor',
      buyer_query: 'buyer_advisor',
      aggregator_needs: 'aggregation_advisor',
      finance_inquiry: 'finance_advisor',
      marketplace: 'marketplace_advisor',
      extension_support: 'extension_advisor',
      mechanization: 'mechanization_advisor',
      export_docs: 'export_advisor',
      certification: 'certification_advisor',
      climate_risk: 'climate_advisor',
      policy: 'policy_advisor',
      research: 'research_advisor',
      grant: 'grant_advisor',
      business: 'business_advisor',
    };

    const specialist = specialistMap[intent] || 'general_advisor';

    // Step 6: Log routing
    await logRouting(actorId, message, intent, specialist, confidence);

    // Step 7: Extract conversation intelligence
    const { data: convData } = await supabase
      .from('conversations')
      .select('id')
      .eq('actor_id', actorId)
      .order('created_at', { ascending: false })
      .limit(1)
      .single()
      .catch(() => ({ data: null }));

    if (convData) {
      await supabase.from('conversation_intelligence').insert([
        {
          actor_id: actorId,
          conversation_id: convData.id,
          actor: actorRoles[0] || 'unknown',
          intent,
          confidence,
          created_at: new Date().toISOString(),
        },
      ]);
    }

    // Step 8: Return routing response
    const response: RoutedResponse = {
      type: 'routed',
      specialist,
      intent,
      confidence,
      message: `Connecting you to ${specialist.replace(/_/g, ' ')}...`,
    };

    return new Response(JSON.stringify(response), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    });
  } catch (error) {
    console.error('Gateway error:', error);
    return new Response(
      JSON.stringify({
        error: error instanceof Error ? error.message : 'Unknown error',
      }),
      {
        status: 500,
        headers: { 'Content-Type': 'application/json' },
      }
    );
  }
});
