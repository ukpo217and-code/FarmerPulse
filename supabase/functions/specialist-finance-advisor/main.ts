// supabase/functions/specialist-finance-advisor/main.ts
// Finance-specific advisor: credit products, insurance, savings groups

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

    // Fetch available financial institutions
    const { data: institutions } = await supabase
      .from('financial_institutions')
      .select('*')
      .eq('active', true)
      .limit(3);

    const suggestions = institutions
      ? institutions.map((inst: any) => ({
          type: 'financial_product',
          institution_name: inst.organization_name,
          institution_type: inst.institution_type,
        }))
      : [];

    return new Response(
      JSON.stringify({
        type: 'advice',
        message: `Hello ${actor.full_name}! I'm your Finance Advisor. I found ${suggestions.length} financial institutions that can help you.`,
        suggestions,
        intelligence_logged: true,
      }),
      { status: 200, headers: { 'Content-Type': 'application/json' } }
    );
  } catch (error) {
    console.error('Finance advisor error:', error);
    return new Response(
      JSON.stringify({ error: 'Advisor error' }),
      { status: 500, headers: { 'Content-Type': 'application/json' } }
    );
  }
});
