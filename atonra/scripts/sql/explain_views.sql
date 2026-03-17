-- explain_views.sql
-- Generates EXPLAIN plans for all staging, intermediate and master views.
-- Safe: EXPLAIN without ANALYZE = read-only, no execution, no locks.
--
-- Usage:
--   psql "$DATA_DATABASE_URL" -f explain_views.sql -o explain_report.txt
--   Or copy-paste sections into any SQL client.

\pset format unaligned
\pset tuples_only on

-- ============================================================================
-- 1. VIEW INVENTORY: list all views with row estimates from pg_class
-- ============================================================================
\echo '================================================================================'
\echo '  VIEW INVENTORY — Estimated rows (from pg_class statistics)'
\echo '================================================================================'
\pset format aligned
\pset tuples_only off

SELECT
    n.nspname AS schema,
    c.relname AS view_name,
    s.n_live_tup AS estimated_rows,
    pg_size_pretty(pg_total_relation_size(c.oid)) AS total_size
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
LEFT JOIN pg_stat_user_tables s ON s.schemaname = n.nspname AND s.relname = c.relname
WHERE n.nspname IN ('staging', 'intermediate', 'master')
  AND c.relkind = 'v'
ORDER BY n.nspname, c.relname;

-- ============================================================================
-- 2. EXPLAIN PLANS — one per view
-- ============================================================================
\pset format unaligned
\pset tuples_only on

-- ---------- STAGING ----------
\echo ''
\echo '================================================================================'
\echo '  STAGING VIEWS'
\echo '================================================================================'

DO $$
DECLARE
    r RECORD;
    plan_line RECORD;
    separator TEXT := '--------------------------------------------------------------------------------';
BEGIN
    FOR r IN
        SELECT n.nspname AS schema_name, c.relname AS view_name
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'staging' AND c.relkind = 'v'
        ORDER BY c.relname
    LOOP
        RAISE NOTICE '';
        RAISE NOTICE '%', separator;
        RAISE NOTICE '  EXPLAIN: %.%', r.schema_name, r.view_name;
        RAISE NOTICE '%', separator;
        FOR plan_line IN
            EXECUTE format('EXPLAIN (COSTS, VERBOSE) SELECT * FROM %I.%I', r.schema_name, r.view_name)
        LOOP
            RAISE NOTICE '%', plan_line."QUERY PLAN";
        END LOOP;
    END LOOP;
END $$;

-- ---------- INTERMEDIATE ----------
\echo ''
\echo '================================================================================'
\echo '  INTERMEDIATE VIEWS'
\echo '================================================================================'

DO $$
DECLARE
    r RECORD;
    plan_line RECORD;
    separator TEXT := '--------------------------------------------------------------------------------';
BEGIN
    FOR r IN
        SELECT n.nspname AS schema_name, c.relname AS view_name
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'intermediate' AND c.relkind = 'v'
        ORDER BY c.relname
    LOOP
        RAISE NOTICE '';
        RAISE NOTICE '%', separator;
        RAISE NOTICE '  EXPLAIN: %.%', r.schema_name, r.view_name;
        RAISE NOTICE '%', separator;
        FOR plan_line IN
            EXECUTE format('EXPLAIN (COSTS, VERBOSE) SELECT * FROM %I.%I', r.schema_name, r.view_name)
        LOOP
            RAISE NOTICE '%', plan_line."QUERY PLAN";
        END LOOP;
    END LOOP;
END $$;

-- ---------- MASTER ----------
\echo ''
\echo '================================================================================'
\echo '  MASTER VIEWS'
\echo '================================================================================'

DO $$
DECLARE
    r RECORD;
    plan_line RECORD;
    separator TEXT := '--------------------------------------------------------------------------------';
BEGIN
    FOR r IN
        SELECT n.nspname AS schema_name, c.relname AS view_name
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'master' AND c.relkind = 'v'
        ORDER BY c.relname
    LOOP
        RAISE NOTICE '';
        RAISE NOTICE '%', separator;
        RAISE NOTICE '  EXPLAIN: %.%', r.schema_name, r.view_name;
        RAISE NOTICE '%', separator;
        FOR plan_line IN
            EXECUTE format('EXPLAIN (COSTS, VERBOSE) SELECT * FROM %I.%I', r.schema_name, r.view_name)
        LOOP
            RAISE NOTICE '%', plan_line."QUERY PLAN";
        END LOOP;
    END LOOP;
END $$;

-- ============================================================================
-- 3. INDEX COVERAGE — tables used by views that lack indexes
-- ============================================================================
\echo ''
\echo '================================================================================'
\echo '  TABLE STATISTICS — seq scans vs index scans (hot spots)'
\echo '================================================================================'
\pset format aligned
\pset tuples_only off

SELECT
    schemaname,
    relname AS table_name,
    n_live_tup AS estimated_rows,
    seq_scan,
    idx_scan,
    CASE WHEN (seq_scan + COALESCE(idx_scan, 0)) > 0
        THEN round(100.0 * seq_scan / (seq_scan + COALESCE(idx_scan, 0)), 1)
        ELSE 0
    END AS seq_scan_pct,
    pg_size_pretty(pg_total_relation_size(format('%I.%I', schemaname, relname)::regclass)) AS total_size
FROM pg_stat_user_tables
WHERE schemaname = 'raw'
  AND n_live_tup > 10000
ORDER BY seq_scan DESC
LIMIT 30;

-- ============================================================================
-- 4. MISSING INDEXES — tables with high seq_scan ratio and many rows
-- ============================================================================
\echo ''
\echo '================================================================================'
\echo '  MISSING INDEXES — high seq_scan on large tables'
\echo '================================================================================'

SELECT
    schemaname,
    relname AS table_name,
    n_live_tup AS estimated_rows,
    seq_scan,
    idx_scan,
    pg_size_pretty(pg_total_relation_size(format('%I.%I', schemaname, relname)::regclass)) AS total_size
FROM pg_stat_user_tables
WHERE schemaname IN ('raw', 'staging', 'intermediate', 'master')
  AND n_live_tup > 100000
  AND (idx_scan IS NULL OR idx_scan = 0)
  AND seq_scan > 0
ORDER BY n_live_tup DESC;
