# tests/test_food_systems_gateway.py
# Comprehensive integration tests for Food Systems Gateway
# Run: pytest tests/test_food_systems_gateway.py -v

import pytest
import os
from datetime import datetime
from supabase import create_client, Client

# Initialize Supabase client
SUPABASE_URL = os.getenv('SUPABASE_URL')
SUPABASE_KEY = os.getenv('SUPABASE_SERVICE_ROLE_KEY')

@pytest.fixture
def supabase_client() -> Client:
    """Initialize Supabase client for testing."""
    return create_client(SUPABASE_URL, SUPABASE_KEY)

@pytest.fixture
def cleanup_test_data(supabase_client):
    """Cleanup test data after tests."""
    yield
    # Delete test actors by email pattern
    supabase_client.from_('actors').delete().ilike('email', '%test-farmer%').execute()
    supabase_client.from_('actors').delete().ilike('email', '%test-buyer%').execute()
    supabase_client.from_('actors').delete().ilike('email', '%test-processor%').execute()

# ========== Phase 1-2: Multi-Role Tests ==========

def test_create_actor_with_roles(supabase_client, cleanup_test_data):
    """Create an actor and add multiple roles."""
    # Create actor
    actor_response = supabase_client.from_('actors').insert([
        {
            'actor_type': 'farmer',
            'full_name': 'Test Farmer Multi-Role',
            'phone': '2348012345670',
            'email': 'test-farmer-multi@test.com',
            'active': True,
        }
    ]).execute()
    
    assert actor_response.data, "Actor creation failed"
    actor_id = actor_response.data[0]['id']
    
    # Add multiple roles
    role1 = supabase_client.rpc('app.add_actor_role', {
        'p_actor_id': actor_id,
        'p_role': 'farmer'
    }).execute()
    
    role2 = supabase_client.rpc('app.add_actor_role', {
        'p_actor_id': actor_id,
        'p_role': 'buyer'
    }).execute()
    
    role3 = supabase_client.rpc('app.add_actor_role', {
        'p_actor_id': actor_id,
        'p_role': 'processor'
    }).execute()
    
    # Verify all roles
    roles_response = supabase_client.rpc('app.actor_all_roles', {
        'p_actor_id': actor_id
    }).execute()
    
    roles = roles_response.data
    assert len(roles) == 3, f"Expected 3 roles, got {len(roles)}"
    assert 'farmer' in roles, "Farmer role missing"
    assert 'buyer' in roles, "Buyer role missing"
    assert 'processor' in roles, "Processor role missing"
    print(f"✓ Multi-role assignment: {roles}")

def test_actor_has_role(supabase_client, cleanup_test_data):
    """Test role existence check."""
    # Create actor
    actor_response = supabase_client.from_('actors').insert([
        {
            'actor_type': 'farmer',
            'full_name': 'Test Role Check',
            'phone': '2348012345671',
            'email': 'test-role-check@test.com',
        }
    ]).execute()
    
    actor_id = actor_response.data[0]['id']
    
    # Add role
    supabase_client.rpc('app.add_actor_role', {
        'p_actor_id': actor_id,
        'p_role': 'aggregator'
    }).execute()
    
    # Check role exists
    has_role = supabase_client.rpc('app.actor_has_role', {
        'p_actor_id': actor_id,
        'p_role': 'aggregator'
    }).execute()
    
    assert has_role.data == True, "Role check failed"
    print("✓ Role existence check passed")

# ========== Phase 3: Onboarding State Machine ==========

def test_onboarding_state_progression(supabase_client, cleanup_test_data):
    """Test onboarding state machine (name -> state -> org -> commodity -> role)."""
    # Create actor
    actor_response = supabase_client.from_('actors').insert([
        {
            'actor_type': 'farmer',
            'full_name': 'Onboarding Test',
            'phone': '2348012345672',
            'email': 'test-onboarding@test.com',
        }
    ]).execute()
    
    actor_id = actor_response.data[0]['id']
    
    # Start onboarding
    supabase_client.rpc('app.start_onboarding', {
        'p_actor_id': actor_id
    }).execute()
    
    # Check first pending field is 'full_name'
    pending = supabase_client.rpc('app.get_pending_field', {
        'p_actor_id': actor_id
    }).execute()
    
    assert pending.data == 'full_name', "Expected 'full_name' as first field"
    print("✓ Step 1: Asking for full_name")
    
    # Save full_name response -> should advance to 'state'
    supabase_client.rpc('app.save_onboarding_response', {
        'p_actor_id': actor_id,
        'p_field': 'full_name',
        'p_value': 'John Obi'
    }).execute()
    
    pending = supabase_client.rpc('app.get_pending_field', {
        'p_actor_id': actor_id
    }).execute()
    
    assert pending.data == 'state', "Expected 'state' as second field"
    print("✓ Step 2: Asking for state")
    
    # Save state -> advance to 'organization'
    supabase_client.rpc('app.save_onboarding_response', {
        'p_actor_id': actor_id,
        'p_field': 'state',
        'p_value': 'Kogi'
    }).execute()
    
    pending = supabase_client.rpc('app.get_pending_field', {
        'p_actor_id': actor_id
    }).execute()
    
    assert pending.data == 'organization', "Expected 'organization' as third field"
    print("✓ Step 3: Asking for organization")
    
    # Save organization -> advance to 'commodity'
    supabase_client.rpc('app.save_onboarding_response', {
        'p_actor_id': actor_id,
        'p_field': 'organization',
        'p_value': 'Cultivate Ltd'
    }).execute()
    
    pending = supabase_client.rpc('app.get_pending_field', {
        'p_actor_id': actor_id
    }).execute()
    
    assert pending.data == 'commodity', "Expected 'commodity' as fourth field"
    print("✓ Step 4: Asking for commodity")
    
    # Save commodity -> advance to 'role'
    supabase_client.rpc('app.save_onboarding_response', {
        'p_actor_id': actor_id,
        'p_field': 'commodity',
        'p_value': 'maize'
    }).execute()
    
    pending = supabase_client.rpc('app.get_pending_field', {
        'p_actor_id': actor_id
    }).execute()
    
    assert pending.data == 'role', "Expected 'role' as fifth field"
    print("✓ Step 5: Asking for role")
    
    # Save role -> complete onboarding
    supabase_client.rpc('app.save_onboarding_response', {
        'p_actor_id': actor_id,
        'p_field': 'role',
        'p_value': 'farmer,buyer'
    }).execute()
    
    # Check onboarding complete
    is_complete = supabase_client.rpc('app.is_onboarding_complete', {
        'p_actor_id': actor_id
    }).execute()
    
    assert is_complete.data == True, "Onboarding should be complete"
    print("✓ Onboarding complete")
    
    # Verify pending field is None
    pending = supabase_client.rpc('app.get_pending_field', {
        'p_actor_id': actor_id
    }).execute()
    
    assert pending.data is None, "Pending field should be None after completion"
    print("✓ State machine progression test passed")

def test_onboarding_idempotency(supabase_client, cleanup_test_data):
    """Test that starting onboarding twice doesn't break state."""
    # Create actor
    actor_response = supabase_client.from_('actors').insert([
        {
            'actor_type': 'farmer',
            'full_name': 'Idempotency Test',
            'phone': '2348012345673',
            'email': 'test-idempotency@test.com',
        }
    ]).execute()
    
    actor_id = actor_response.data[0]['id']
    
    # Start onboarding twice
    supabase_client.rpc('app.start_onboarding', {'p_actor_id': actor_id}).execute()
    supabase_client.rpc('app.start_onboarding', {'p_actor_id': actor_id}).execute()
    
    # Should still ask for full_name
    pending = supabase_client.rpc('app.get_pending_field', {'p_actor_id': actor_id}).execute()
    assert pending.data == 'full_name', "Idempotent start_onboarding failed"
    print("✓ Onboarding idempotency test passed")

# ========== Phase 4: Routing History ==========

def test_log_routing(supabase_client, cleanup_test_data):
    """Test routing history logging."""
    # Create actor
    actor_response = supabase_client.from_('actors').insert([
        {
            'actor_type': 'farmer',
            'full_name': 'Routing Test',
            'phone': '2348012345674',
            'email': 'test-routing@test.com',
        }
    ]).execute()
    
    actor_id = actor_response.data[0]['id']
    
    # Log routing
    supabase_client.rpc('app.log_routing', {
        'p_actor_id': actor_id,
        'p_input_text': 'I need to buy rice in bulk',
        'p_intent': 'buyer_query',
        'p_routed_to': 'buyer_advisor',
        'p_confidence': 0.92
    }).execute()
    
    # Fetch routing history
    history = supabase_client.from_('routing_history').select('*').eq('actor_id', actor_id).execute()
    
    assert len(history.data) > 0, "Routing history not logged"
    assert history.data[0]['detected_intent'] == 'buyer_query', "Intent not logged correctly"
    assert history.data[0]['routed_to'] == 'buyer_advisor', "Specialist not logged correctly"
    print("✓ Routing history logging test passed")

# ========== Phase 5: Conversation Intelligence ==========

def test_extract_conversation_intelligence(supabase_client, cleanup_test_data):
    """Test conversation intelligence extraction."""
    # Create actor
    actor_response = supabase_client.from_('actors').insert([
        {
            'actor_type': 'farmer',
            'full_name': 'Intelligence Test',
            'phone': '2348012345675',
            'email': 'test-intelligence@test.com',
        }
    ]).execute()
    
    actor_id = actor_response.data[0]['id']
    
    # Extract intelligence
    supabase_client.rpc('app.extract_conversation_intelligence', {
        'p_actor_id': actor_id,
        'p_conversation_id': None,
        'p_actor': 'farmer',
        'p_location': {'state': 'Kogi', 'lga': 'Lokoja'},
        'p_commodity': 'maize',
        'p_intent': 'sell',
        'p_need': 'Find buyers',
        'p_constraint': 'Transport to market',
        'p_opportunity': 'Join cooperative',
        'p_urgency': 'this_season',
        'p_sentiment': 'positive',
        'p_confidence': 0.85
    }).execute()
    
    # Fetch intelligence
    intel = supabase_client.from_('conversation_intelligence').select('*').eq('actor_id', actor_id).execute()
    
    assert len(intel.data) > 0, "Conversation intelligence not recorded"
    assert intel.data[0]['commodity'] == 'maize', "Commodity not extracted"
    assert intel.data[0]['sentiment'] == 'positive', "Sentiment not extracted"
    print("✓ Conversation intelligence extraction test passed")

# ========== Phase 6: Opportunity Matching ==========

def test_propose_actor_match(supabase_client, cleanup_test_data):
    """Test opportunity matching proposal."""
    # Create two actors
    farmer_response = supabase_client.from_('actors').insert([
        {
            'actor_type': 'farmer',
            'full_name': 'Farmer for Matching',
            'phone': '2348012345676',
            'email': 'test-farmer-match@test.com',
        }
    ]).execute()
    
    buyer_response = supabase_client.from_('actors').insert([
        {
            'actor_type': 'buyer',
            'full_name': 'Buyer for Matching',
            'phone': '2348012345677',
            'email': 'test-buyer-match@test.com',
        }
    ]).execute()
    
    farmer_id = farmer_response.data[0]['id']
    buyer_id = buyer_response.data[0]['id']
    
    # Add roles
    supabase_client.rpc('app.add_actor_role', {'p_actor_id': farmer_id, 'p_role': 'farmer'}).execute()
    supabase_client.rpc('app.add_actor_role', {'p_actor_id': buyer_id, 'p_role': 'buyer'}).execute()
    
    # Propose match
    match_response = supabase_client.rpc('app.propose_actor_match', {
        'p_actor_a_id': farmer_id,
        'p_actor_b_id': buyer_id,
        'p_match_type': 'farmer-buyer',
        'p_score': 0.92,
        'p_commodity': 'maize',
        'p_location': {'state': 'Kogi'}
    }).execute()
    
    # Verify match
    matches = supabase_client.from_('actor_opportunity_matches').select('*').eq('actor_a_id', farmer_id).execute()
    
    assert len(matches.data) > 0, "Match not created"
    assert matches.data[0]['status'] == 'proposed', "Initial status should be 'proposed'"
    assert matches.data[0]['score'] == 0.92, "Score not saved"
    print("✓ Opportunity match proposal test passed")

def test_accept_reject_match(supabase_client, cleanup_test_data):
    """Test accepting and rejecting opportunity matches."""
    # Create match (as above)
    farmer_response = supabase_client.from_('actors').insert([
        {
            'actor_type': 'farmer',
            'full_name': 'Farmer Accept Test',
            'phone': '2348012345678',
            'email': 'test-farmer-accept@test.com',
        }
    ]).execute()
    
    buyer_response = supabase_client.from_('actors').insert([
        {
            'actor_type': 'buyer',
            'full_name': 'Buyer Accept Test',
            'phone': '2348012345679',
            'email': 'test-buyer-accept@test.com',
        }
    ]).execute()
    
    farmer_id = farmer_response.data[0]['id']
    buyer_id = buyer_response.data[0]['id']
    
    # Propose match
    match_id = supabase_client.rpc('app.propose_actor_match', {
        'p_actor_a_id': farmer_id,
        'p_actor_b_id': buyer_id,
        'p_match_type': 'farmer-buyer',
        'p_score': 0.88
    }).execute()
    
    # Get match ID
    matches = supabase_client.from_('actor_opportunity_matches').select('id').eq('actor_a_id', farmer_id).execute()
    match_id = matches.data[0]['id']
    
    # Accept match
    supabase_client.rpc('app.accept_match', {'p_match_id': match_id}).execute()
    
    # Verify status changed
    match = supabase_client.from_('actor_opportunity_matches').select('*').eq('id', match_id).single().execute()
    assert match.data['status'] == 'accepted', "Match status not updated"
    print("✓ Match acceptance test passed")
    
    # Create another match to test rejection
    match2_id = supabase_client.rpc('app.propose_actor_match', {
        'p_actor_a_id': farmer_id,
        'p_actor_b_id': buyer_id,
        'p_match_type': 'farmer-aggregator',
        'p_score': 0.75
    }).execute()
    
    matches2 = supabase_client.from_('actor_opportunity_matches').select('id').eq('actor_a_id', farmer_id).eq('match_type', 'farmer-aggregator').execute()
    match2_id = matches2.data[0]['id']
    
    # Reject match
    supabase_client.rpc('app.reject_match', {'p_match_id': match2_id}).execute()
    
    # Verify status changed
    match2 = supabase_client.from_('actor_opportunity_matches').select('*').eq('id', match2_id).single().execute()
    assert match2.data['status'] == 'rejected', "Match rejection failed"
    print("✓ Match rejection test passed")

# ========== Phase 7: Backward Compatibility ==========

def test_farmer_workflow_unchanged(supabase_client, cleanup_test_data):
    """Verify existing farmer workflows still work."""
    # Create farmer (existing way)
    farmer_response = supabase_client.from_('actors').insert([
        {
            'actor_type': 'farmer',
            'full_name': 'Legacy Farmer',
            'phone': '2348012345680',
            'email': 'test-legacy-farmer@test.com',
            'state': 'Kogi',
            'lga': 'Lokoja',
            'primary_crop': 'maize',
        }
    ]).execute()
    
    farmer_id = farmer_response.data[0]['id']
    
    # Register farm (existing workflow)
    farm_response = supabase_client.from_('farms').insert([
        {
            'actor_id': farmer_id,
            'farm_name': 'North Farm',
            'commodity': 'maize',
            'area_ha': 5.0,
            'latitude': 7.1536,
            'longitude': 6.7281,
        }
    ]).execute()
    
    assert farm_response.data, "Farm registration failed"
    farm_id = farm_response.data[0]['id']
    
    # Create crop season (existing workflow)
    season_response = supabase_client.from_('crop_seasons').insert([
        {
            'farm_id': farm_id,
            'crop_id': None,
            'season_year': 2024,
            'season_name': 'rainy',
            'planting_date': '2024-06-01',
            'expected_harvest_date': '2024-10-01',
            'area_ha': 5.0,
            'status': 'planned',
        }
    ]).execute()
    
    assert season_response.data, "Crop season creation failed"
    print("✓ Farmer workflow backward compatibility test passed")

# ========== Integration Test ==========

def test_end_to_end_gateway_flow(supabase_client, cleanup_test_data):
    """Complete end-to-end test: new user onboarding -> role assignment -> routing."""
    phone = '2348012345681'
    
    # Step 1: User sends initial message
    actor_response = supabase_client.from_('actors').insert([
        {'actor_type': 'farmer', 'full_name': 'E2E Test User', 'phone': phone, 'email': 'test-e2e@test.com'}
    ]).execute()
    
    actor_id = actor_response.data[0]['id']
    print(f"✓ Step 1: Actor created ({actor_id})")
    
    # Step 2: Onboarding starts
    supabase_client.rpc('app.start_onboarding', {'p_actor_id': actor_id}).execute()
    pending = supabase_client.rpc('app.get_pending_field', {'p_actor_id': actor_id}).execute()
    assert pending.data == 'full_name', "Onboarding should start with full_name"
    print("✓ Step 2: Onboarding initiated")
    
    # Step 3: User answers questions
    supabase_client.rpc('app.save_onboarding_response', {
        'p_actor_id': actor_id, 'p_field': 'full_name', 'p_value': 'E2E User Full'
    }).execute()
    supabase_client.rpc('app.save_onboarding_response', {
        'p_actor_id': actor_id, 'p_field': 'state', 'p_value': 'Lagos'
    }).execute()
    supabase_client.rpc('app.save_onboarding_response', {
        'p_actor_id': actor_id, 'p_field': 'organization', 'p_value': 'None'
    }).execute()
    supabase_client.rpc('app.save_onboarding_response', {
        'p_actor_id': actor_id, 'p_field': 'commodity', 'p_value': 'rice'
    }).execute()
    supabase_client.rpc('app.save_onboarding_response', {
        'p_actor_id': actor_id, 'p_field': 'role', 'p_value': 'farmer,buyer'
    }).execute()
    print("✓ Step 3: Onboarding completed")
    
    # Step 4: Verify multi-role assignment
    roles = supabase_client.rpc('app.actor_all_roles', {'p_actor_id': actor_id}).execute()
    assert 'farmer' in roles.data and 'buyer' in roles.data, "Multi-role assignment failed"
    print(f"✓ Step 4: Multi-role assignment ({roles.data})")
    
    # Step 5: User sends intent-based message
    supabase_client.rpc('app.log_routing', {
        'p_actor_id': actor_id,
        'p_input_text': "I'm looking to buy rice in bulk for my restaurant",
        'p_intent': 'buyer_query',
        'p_routed_to': 'buyer_advisor',
        'p_confidence': 0.89
    }).execute()
    print("✓ Step 5: Intent detected and routed to buyer_advisor")
    
    # Step 6: Conversation intelligence extracted
    supabase_client.rpc('app.extract_conversation_intelligence', {
        'p_actor_id': actor_id,
        'p_conversation_id': None,
        'p_actor': 'buyer',
        'p_location': {'state': 'Lagos'},
        'p_commodity': 'rice',
        'p_intent': 'bulk_purchase',
        'p_need': 'Find suppliers',
        'p_urgency': 'immediate',
        'p_sentiment': 'positive',
        'p_confidence': 0.88
    }).execute()
    print("✓ Step 6: Conversation intelligence extracted")
    
    print("✅ End-to-end gateway flow test PASSED")

if __name__ == '__main__':
    pytest.main([__file__, '-v'])
