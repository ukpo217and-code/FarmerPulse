// supabase/functions/specialist-aggregator-advisor/main.ts
// Aggregator-specific advisor: volume logistics, storage, buyer connections

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const supabase = createClient(
  Deno.env.get('SUPABASE_URL') || '',
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''
);

Deno.serve(async (req: Request) => {
  try {
    const { actor_id, message, context } = await req.json();

    const { data: actor } = await supabase
      .from('actors')
      .select('*')
      .eq('id', actor_id)
      .single();

    if (!actor) {
      return new Response(
        JSON.stringify({ error: 'Actor not found' }),
        { status: 404, headers: { 'Content-Type': 'application/json' } }
      );
    }

    const advice = `Hello ${actor.full_name}! I'm your Aggregation Advisor.`;

    return new Response(
      JSON.stringify({
        type: 'advice',
        message: advice,
        suggestions: [
          { type: 'volume_optimization', message: 'How much volume can you handle?' },
          { type: 'logistics_planning', message: 'What transport do you have access to?' },
        ],
        intelligence_logged: true,
      }),
      { status: 200, headers: { 'Content-Type': 'application/json' } }
    );
  } catch (error) {
    console.error('Aggregator advisor error:', error);
    return new Response(
      JSON.stringify({ error: 'Advisor error' }),
      { status: 500, headers: { 'Content-Type': 'application/json' } }
    );
  }
});
