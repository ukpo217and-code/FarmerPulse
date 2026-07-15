-- ============================================================
-- 0009: Actor Role Type System
-- Extended enum to support 31+ food system actors
-- ============================================================

CREATE TYPE public.actor_role_type AS ENUM (
  'farmer',
  'farmer_group',
  'cooperative',
  'extension_agent',
  'input_dealer',
  'agro_dealer',
  'seed_company',
  'fertilizer_supplier',
  'veterinary_provider',
  'mechanization_provider',
  'aggregator',
  'commodity_trader',
  'processor',
  'manufacturer',
  'buyer',
  'exporter',
  'importer',
  'transporter',
  'warehouse',
  'cold_chain_operator',
  'financial_institution',
  'insurance_provider',
  'ngo',
  'development_partner',
  'government_agency',
  'research_institution',
  'university',
  'commodity_association',
  'market_association',
  'youth_agripreneur',
  'women_farmer_group',
  'agritech_company',
  'consultant',
  'other'
);

-- BACKWARD COMPATIBILITY:
-- Existing actor_type enum (farmer, agro_dealer, etc.) remains unchanged.
-- This new actor_role_type is for multi-role assignment via actor_roles table.
-- Migration strategy: Existing actors keep their original actor_type.
-- New roles are appended via actor_roles (never overwriting).
