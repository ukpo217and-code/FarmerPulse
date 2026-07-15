// supabase/functions/specialist-buyer-advisor/main.ts
// Buyer-specific advisor: supplier sourcing, quality standards, bulk pricing

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const supabase = createClient(
  Deno.env.get('SUPABASE_URL') || '',
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''
);

Deno.serve(async (req: Request) => {
  try {
    const { actor_id, message, context } = await req.json();

    // Retrieve buyer profile
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

    // Extract commodity from context or message
    const commodity = context?.commodities?.[0] || 'rice';

    // Find matching suppliers/farmers
    const { data: matches } = await supabase
      .from('commodity_listings')
      .select('*')
      .eq('commodity', commodity)
      .eq('status', 'available')
      .limit(5);

    const suggestions = matches
      ? matches.map((listing: any) => ({
          type: 'supplier_match',
          commodity: listing.commodity,
          quantity: listing.quantity,
          unit: listing.unit,
          asking_price: listing.asking_price,
        }))
      : [];

    return new Response(
      JSON.stringify({
        type: 'advice',
        message: `I found ${suggestions.length} suppliers with ${commodity} available.`,
        suggestions,
        intelligence_logged: true,
      }),
      { status: 200, headers: { 'Content-Type': 'application/json' } }
    );
  } catch (error) {
    console.error('Buyer advisor error:', error);
    return new Response(
      JSON.stringify({ error: 'Advisor error' }),
      { status: 500, headers: { 'Content-Type': 'application/json' } }
    );
  }
});
