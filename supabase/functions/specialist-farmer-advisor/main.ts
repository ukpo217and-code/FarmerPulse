// supabase/functions/specialist-farmer-advisor/main.ts
// Farmer-specific advisor: crop guidance, farm management, input recommendations

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const supabase = createClient(
  Deno.env.get('SUPABASE_URL') || '',
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''
);

Deno.serve(async (req: Request) => {
  try {
    const { actor_id, message, context } = await req.json();

    // Retrieve farmer profile
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

    // Get farms
    const { data: farms } = await supabase
      .from('farms')
      .select('*')
      .eq('actor_id', actor_id);

    // Simulate AI advice (placeholder)
    const advice = `Hello ${actor.full_name}! I'm your Farmer Advisor.`;
    const suggestions = farms
      ? farms.map((farm: any) => ({
          type: 'farm_info',
          farm_name: farm.farm_name,
          commodity: farm.commodity,
          area_ha: farm.area_ha,
        }))
      : [];

    return new Response(
      JSON.stringify({
        type: 'advice',
        message: advice,
        suggestions,
        intelligence_logged: true,
      }),
      { status: 200, headers: { 'Content-Type': 'application/json' } }
    );
  } catch (error) {
    console.error('Farmer advisor error:', error);
    return new Response(
      JSON.stringify({ error: 'Advisor error' }),
      { status: 500, headers: { 'Content-Type': 'application/json' } }
    );
  }
});
