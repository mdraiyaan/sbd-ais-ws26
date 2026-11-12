# Exercise 6

## Part 1 - Decision

For this scenario, log-based CDC with Debezium is the right choice because the payment path (`card_processor.py`) is certified and cannot be modified, and PostgreSQL cannot take extra polling queries from multiple fraud models and archives. Polling misses out-of-order commits (like in Exercise 5), and dual write risks losing or inventing events if the app crashes between the DB commit and the Kafka send. Debezium reads PostgreSQL's write-ahead log (WAL) directly, so every committed payment is published in commit order with zero code changes or extra queries on the payment path. The main cost is the PostgreSQL replication slot: Postgres retains all WAL files that the connector has not read yet, so if Debezium stops for a long time, the disk can fill up and bring down the database and payment path. In production, the team can catch this early by alerting on replication slot lag (`pg_replication_slots`), WAL disk usage, and Debezium connector status. If our team owned the payment path, the transactional outbox pattern would be preferred because it avoids tying database availability to an external replication slot while keeping commits and events atomic.


## Part 2 - Three Runs

### Run 1 - Debezium defaults

**Prediction:** Only one velocity instance will read from the topic because Debezium creates a single partition by default, so the other two instances will sit idle and lag will grow past 5 seconds.

```text
  velocity model (card testing)
    R3  frauds caught          0/4  (0%)   FAIL  (>= 90 %)
    R3  false alerts           0   PASS  (at most 10 % of the flagged transactions)
    R4  no alerts; worst lag of the velocity agents 52.2 s   FAIL  (<= 5 s)
        duplicate alerts       0   (info: alerts case management got twice)
```

With only 1 partition, Kafka assigns it to a single velocity instance (`vel-1`) while `vel-2` and `vel-3` stay idle. Since the velocity model takes 2 ms per payment (~400-500 payments/s max), one instance cannot keep up with 1,000 payments/s, so lag quickly climbs to 52.2 s (R4 fails) and frauds are still sitting in the backlog (R3 fails).

### Run 2 - 6 partitions

**Prediction:** With 6 partitions, all three velocity instances will share the load and keep lag under 5 seconds (R4 passes), but R3 will still fail because Debezium still keys events by payment `id` instead of cardholder.

```text
  velocity model (card testing)
    R3  frauds caught          0/4  (0%)   FAIL  (>= 90 %)
    R3  false alerts           0   PASS  (at most 10 % of the flagged transactions)
    R4  no alerts; worst lag of the velocity agents 1.5 s   PASS  (<= 5 s)
        duplicate alerts       0   (info: alerts case management got twice)
```

All three velocity instances got 2 partitions each and kept up with the 1,000 payments/s rate, dropping worst lag to 1.5 s (R4 passes). However, Debezium's default key is the primary key `id`, so a stolen card's 12 test payments get hashed across all 6 partitions and split between the 3 instances, meaning no single instance sees 8 payments within 60 s (R3 fails at 0%).

### Run 3 - Cardholder as the key (`user_id`)

**Prediction:** Setting `message.key.columns` to `public.transactions:user_id` will route all payments of each cardholder to the same partition and velocity instance, so both R3 and R4 will pass.

```text
  velocity model (card testing)
    R3  frauds caught          4/4  (100%)   PASS  (>= 90 %)
    R3  false alerts           0   PASS  (at most 10 % of the flagged transactions)
    R4  alert latency p50/p95  0.5 s / 1.2 s   PASS  (p95 <= 5 s after the commit)
        duplicate alerts       0   (info: alerts case management got twice)
```

With `user_id` as the message key, every payment for a given cardholder lands in the same partition in commit order and goes to the same velocity instance. All 3 instances still split the 1,000/s load cleanly (p95 latency 1.2 s, R4 passes), and the velocity model catches 4/4 card-testing frauds with 0 false alerts (R3 passes).


## Closing

Debezium's two critical defaults were creating the topic with **1 partition** and using the table's **primary key (`id`)** as the Kafka message key. If nobody changed them in production, the system would fail silently in two ways: only one velocity worker would do all the work while extra scaled instances sit idle causing growing alert lag, and even after increasing partitions, stateful per-cardholder models would miss multi-payment attacks because each cardholder's events get scattered across partitions. The team could have noticed this by checking consumer group partition assignments and lag (seeing idle members and rising lag on partition 0), inspecting message keys in Kafka UI (`{"id": ...}` instead of `{"user_id": ...}`), and verifying detection rates against test/chargeback frauds.
