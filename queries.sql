-- ============================================================
-- PostgreSQL GiST Spatial Indexing at 500M Points
-- Run these steps in order.
-- ============================================================

-- ------------------------------------------------------------
-- Step 1: Create the locations table (POINT geometry)
-- POINT holds (x, y) = (longitude, latitude)
-- ------------------------------------------------------------
CREATE TABLE locations (
    location_id  BIGSERIAL PRIMARY KEY,
    name         TEXT,
    geolocation  POINT
);

-- ------------------------------------------------------------
-- Step 2: Generate 500M points in 50 batches of 10M each
-- Batching keeps memory flat instead of one giant transaction.
-- Watch the Messages tab for "Batch N done".
-- Takes ~24 min on 4 cores.
-- ------------------------------------------------------------
DO $$
BEGIN
  FOR i IN 0..49 LOOP
    INSERT INTO locations (name, geolocation)
    SELECT
      'Location_' || g,
      POINT( -180 + random()*360,     -- lon [-180, 180]
             -90  + random()*180 )    -- lat [-90, 90]
    FROM generate_series(i*10000000 + 1, (i+1)*10000000) AS g;
    RAISE NOTICE 'Batch % done', i;
  END LOOP;
END $$;

-- Confirm row count (should be 500000000)
SELECT count(*) FROM locations;

-- ------------------------------------------------------------
-- Step 3: Update planner stats after bulk load
-- ------------------------------------------------------------
ANALYZE locations;

-- ============================================================
-- BEFORE GiST: spatial filters do a Parallel Seq Scan (seconds)
-- ============================================================

-- Box query (points inside a NYC rectangle)
EXPLAIN ANALYZE
SELECT *
FROM locations
WHERE geolocation <@ box '((-74.1,40.6),(-73.7,40.9))';

-- Circle query (radius around Times Square)
EXPLAIN ANALYZE
SELECT *
FROM locations
WHERE geolocation <@ circle '((-73.9855,40.7580), 0.02)';

-- Polygon query (count inside a midtown polygon)
EXPLAIN ANALYZE
SELECT count(*)
FROM locations
WHERE geolocation <@ polygon '((-74.02,40.70),(-73.94,40.70),(-73.94,40.80),(-74.02,40.80))';

-- ------------------------------------------------------------
-- Step 4: Build the GiST index, then re-analyze
-- This is the slow step (~25 min on 4 cores).
-- Build AFTER loading, not before: bulk build is far faster.
-- ------------------------------------------------------------
CREATE INDEX idx_locations_gist ON locations USING gist (geolocation);
ANALYZE locations;

-- ============================================================
-- AFTER GiST: same filters now use index scans (milliseconds)
-- ============================================================

-- Box query -> Bitmap Index Scan
EXPLAIN ANALYZE
SELECT *
FROM locations
WHERE geolocation <@ box '((-74.1,40.6),(-73.7,40.9))';

-- Circle query -> Bitmap Index Scan
EXPLAIN ANALYZE
SELECT *
FROM locations
WHERE geolocation <@ circle '((-73.9855,40.7580), 0.02)';

-- Polygon query -> Index Only Scan
EXPLAIN ANALYZE
SELECT count(*)
FROM locations
WHERE geolocation <@ polygon '((-74.02,40.70),(-73.94,40.70),(-73.94,40.80),(-74.02,40.80))';

-- ------------------------------------------------------------
-- K-NN nearest neighbor: 100 closest points to Times Square
-- Uses the <-> distance operator. GiST returns rows already
-- in distance order, no full scan or sort.
-- ------------------------------------------------------------
EXPLAIN ANALYZE
SELECT location_id, name, geolocation
FROM locations
ORDER BY geolocation <-> POINT(-73.9855, 40.7580)
LIMIT 100;

-- ============================================================
-- Verification
-- ============================================================

-- Is the index being used? (idx_scan should be > 0)
SELECT indexrelid::regclass AS index_name,
       idx_scan, idx_tup_read, idx_tup_fetch
FROM pg_stat_user_indexes
WHERE relid = 'locations'::regclass
ORDER BY idx_scan DESC;

-- Table vs index sizes
SELECT
  pg_size_pretty(pg_relation_size('locations'))        AS table_only,
  pg_size_pretty(pg_indexes_size('locations'))         AS indexes_only,
  pg_size_pretty(pg_total_relation_size('locations'))  AS total_with_indexes;