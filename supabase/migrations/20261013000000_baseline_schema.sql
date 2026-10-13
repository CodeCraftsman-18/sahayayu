-- =============================================================================
-- SAHAYAYU BASELINE MIGRATION
-- Extensions, Clinical Entities, Spatial Engine, and Lifecycle Retention
-- =============================================================================

-- 1. Enable Required Extensions
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- 2. Emergencies Registry
CREATE TABLE IF NOT EXISTS public.emergencies (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    status TEXT NOT NULL DEFAULT 'OPEN',
    source TEXT NOT NULL,
    heart_rate INTEGER,
    systolic_bp INTEGER,
    diastolic_bp INTEGER,
    shock_index NUMERIC(4, 2),
    latitude DOUBLE PRECISION,
    longitude DOUBLE PRECISION,
    location TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 3. CDC STEADI Longitudinal Profiles
CREATE TABLE IF NOT EXISTS public.elder_clinical_profiles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    elder_id TEXT,
    prior_falls_6m INTEGER DEFAULT 0,
    mobility_aid TEXT DEFAULT 'None',
    on_anticoagulants BOOLEAN DEFAULT FALSE,
    frequent_dizziness BOOLEAN DEFAULT FALSE,
    chronic_conditions TEXT[] DEFAULT '{}',
    fall_risk_score INTEGER DEFAULT 0,
    risk_level TEXT DEFAULT 'LOW',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 4. Hospital Admissions & Autonomous SBAR Records
CREATE TABLE IF NOT EXISTS public.hospital_admissions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    emergency_id BIGINT REFERENCES public.emergencies(id) ON DELETE CASCADE,
    elder_id TEXT,
    hospital_name TEXT NOT NULL,
    triage_level TEXT NOT NULL,
    pre_existing_conditions TEXT[] DEFAULT '{}',
    on_blood_thinners BOOLEAN DEFAULT FALSE,
    vitals_snapshot JSONB,
    sbar_briefing TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'INCOMING',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 5. Community Volunteer Responder Network (Spatial Registry)
CREATE TABLE IF NOT EXISTS public.volunteers (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name TEXT NOT NULL,
    phone TEXT NOT NULL,
    skills TEXT DEFAULT 'CPR, First Aid',
    geom GEOMETRY(Point, 4326) NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_volunteers_geom ON public.volunteers USING GIST (geom);

-- 6. PostGIS Spatial Responder Ranking RPC
CREATE OR REPLACE FUNCTION public.find_ranked_responders(
    incident_lat DOUBLE PRECISION,
    incident_lon DOUBLE PRECISION,
    max_radius_meters DOUBLE PRECISION DEFAULT 3500
)
RETURNS TABLE (
    id BIGINT,
    name TEXT,
    phone TEXT,
    skills TEXT,
    distance_meters DOUBLE PRECISION
)
LANGUAGE sql
STABLE
AS \$\$
    SELECT 
        v.id,
        v.name,
        v.phone,
        v.skills,
        ROUND(ST_Distance(
            v.geom::geography, 
            ST_SetSRID(ST_MakePoint(incident_lon, incident_lat), 4326)::geography
        )::NUMERIC, 2) AS distance_meters
    FROM public.volunteers v
    WHERE ST_DWithin(
        v.geom::geography,
        ST_SetSRID(ST_MakePoint(incident_lon, incident_lat), 4326)::geography,
        max_radius_meters
    )
    ORDER BY distance_meters ASC;
\$\$;

-- 7. Automated 36-Hour Incident Auto-Purge via pg_cron
SELECT cron.schedule(
    'purge-stale-emergencies-36h',
    '0 * * * *',
    \$\$
        DELETE FROM public.emergencies
        WHERE created_at < NOW() - INTERVAL '36 hours';
    \$\$
);
