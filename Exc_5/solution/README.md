# Exercise 5

## Stage A - Today's system

### Step 1 - 20 machines
- Database count: `SELECT count(*) FROM readings WHERE run = (SELECT max(run) FROM readings);` -> 4000 rows.
- Detector output: ~2566 rows read, 489 missing.

**Why readings are missing:**
All 4000 rows are in PostgreSQL. The missing readings happen because of concurrent gateway transactions:
1. The 4 gateways insert batches concurrently. `BIGSERIAL` assigns IDs at insert time before the transaction commits.
2. Gateway 1 gets IDs 100-114 and Gateway 2 gets 115-129.
3. Gateway 2 commits first. Gateway 1 commits slightly later due to network delay / sleep before commit.
4. The detector polls `WHERE id > last_id`. It sees IDs 115-129, updates `last_id = 129`.
5. Gateway 1 commits 100-114 afterwards, but the detector already moved past 129, so rows 100-114 are skipped forever.

### Step 2 - 60 machines (full plant)
- With 60 machines at 10 Hz (600 readings/s), backlog and delay constantly grow.
- Cause: `model.score()` has a 3 ms inference time per reading (`cost_ms = 3.0`).
- A single detector thread can only process `1000 / 3 = ~333 readings/s`.
- Since incoming rate (600/s) > processing rate (333/s), the backlog builds up and latency quickly exceeds the 5s requirement.


## Stage B - Decision Record

### Options
1. **PostgreSQL polling:**
   - Breaks R4 because dashboards and archive consumers will also poll the database, multiplying query load.
   - At 100,000 readings/s, Postgres will hit write/indexing bottlenecks.
   - Concurrent writes still risk commit/id order issues.
2. **Kafka event streaming:**
   - Gateways write directly to Kafka.
   - Using `key=machine_id` guarantees all readings for a machine go to the same partition in order (satisfies R2).
   - Independent consumer groups can read the stream for dashboard/archive without touching Postgres or slowing detectors (satisfies R4).

**Decision:** Option 2 (Kafka). Postgres is kept only for the machine registry.

### Sizing
- Model takes 3 ms per reading.
- **Lab (600 readings/s):**
  - Need `600 * 0.003 = 1.8` detector instances -> 2 instances minimum, 3 used with 6 partitions for safety margin (~200 readings/s each).
- **Production (100,000 readings/s):**
  - Need `100,000 * 0.003 = 300` detector instances and at least 300 partitions.
- **Tipping point:**
  - Polling Postgres is fine for small setups (under 50-100 readings/s total).
  - Beyond ~200-300 readings/s (where a single worker saturates its CPU core and multi-writer concurrency causes commit gaps), a log-based message broker like Kafka is required.


## Stage C - Build the core

### Topic creation
```bash
docker exec kafka kafka-topics.sh --bootstrap-server localhost:9092 --create --topic readings --partitions 6 --replication-factor 1
docker exec kafka kafka-topics.sh --bootstrap-server localhost:9092 --create --topic anomalies --partitions 2 --replication-factor 1
```

### Implementation
- `KafkaSink` in `plant.py`: sends readings to `readings` topic using `key=reading["machine_id"]` so messages for the same machine stay in the same partition. Added `linger.ms=10` and `acks=1`.
- `detector_service.py`: joins consumer group `guardian-detectors` on topic `readings`. Uses `auto.offset.reset="latest"` to avoid processing old data on restarts. Anomaly events are sent to `anomalies` with `key=reading["machine_id"]`.

### Scoreboard output
Ran 3 detector instances (`det-1`, `det-2`, `det-3`) with the 60-machine plant for 150 seconds:

```text
Detection  (topic anomalies: 818 anomaly events, models ['v1'])
   #  machine   start  detected   delay
   1  M-029       40s       yes   7.9 s
   2  M-026      100s       yes   8.2 s

  faults detected: 2/2, mean delay 8.1 s; false alarms (episodes on healthy machines): 0
  latency reading -> anomaly event: p50 0.10 s, p95 0.14 s, max 0.17 s
  duplicate anomaly events (same anomaly_id): 0

Detector instances  (model telemetry, this run)
  det-1          pid 18308   v1  readings    36,283  missing       0  out-of-order      0  machines   25  alive
  det-2          pid 7832    v1  readings    29,030  missing       0  out-of-order      0  machines   20  alive
  det-3          pid 20364   v1  readings    21,780  missing       0  out-of-order      0  machines   15  alive

Requirements (measurable part)
  [PASS] R2 complete and ordered: 0 readings missing, 0 out of order
  [PASS] R3 fresh: p95 latency < 5 s
  [PASS] detection: all faults found, at most 2 false alarms
```
