# PostgreSQL GiST Spatial Indexing at 500M Points

Reproduces and extends a PostgreSQL 17 GiST tutorial on a dataset of 500 million
geo-points, comparing spatial query performance before and after indexing.

## What this shows

Spatial filters (box, circle, polygon) and K-NN nearest-neighbor search go from
full table scans taking ~60 seconds to index scans taking milliseconds, once a
GiST index is added.

| Query | Before GiST | After GiST |
|-------|-------------|------------|
| Box | 58,622 ms | 244 ms |
| Circle | 60,911 ms | 0.67 ms |
| Polygon | 60,890 ms | 7.07 ms |
| K-NN (top 100) | full sort needed | 0.83 ms |

Table size: 36 GB. GiST index: ~33 GB. Index build time: ~25 min on 4 cores.

## Setup

1. Copy the env template and fill in your own values:

```
   cp .env.example .env
```

2. Start the containers:

```
   docker compose up -d
```

3. Open pgAdmin at `http://localhost:8080` and log in with the pgAdmin
   credentials from your `.env`.

4. Register a server in pgAdmin:
   - Host: `db`
   - Port: `5432`
   - Database, username, password: from your `.env`

## Running the pipeline

Run the SQL steps in order (see `queries.sql` or the sections below):

1. Create the `locations` table with a `POINT` column.
2. Generate 500M points in batches of 10M.
3. `ANALYZE`, then run the box, circle, and polygon queries (before GiST).
4. Build the GiST index, `ANALYZE` again.
5. Rerun the same queries plus the K-NN query (after GiST).
6. Check index usage and table/index sizes.

## Hardware note

Tested on 4 cores, 32 GB RAM. The dataset needs ~77 GB free disk. On Windows with
WSL2, reclaim space after with `docker compose down -v` then compact the WSL
virtual disk using `diskpart` (WSL disks grow but do not shrink on their own).

## Requirements

- Docker and Docker Compose
- ~80 GB free disk for the full 500M run