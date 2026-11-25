# Exercise 7: From the log to the lake

## 1. Decision: Which architecture and why

I chose **Architecture B: The lake is the truth (staging + publish)**.

```python
def run_once():
    start = lake_position()
    new = read_new(start)
    run = write_files(new, STAGING)
    publish(run)
```

### Why this architecture?
1. **No dual-state desync (unlike Architecture A):** In Architecture A, we have two separate places holding state: the parquet files in the lake, and a `position.json` state file. If the job crashes after writing files but before saving the state file, the next run reads the same offsets again and writes duplicates. In Architecture B, we don't have an external state file at all. The lake itself is the single source of truth.
2. **Crash safety via atomic publish:** We write files into a temporary `STAGING` directory first. If the job crashes while writing, the partial files stay in staging and readers never see them. When the next run starts, leftovers in staging are automatically cleaned up. Once all files are written, `publish(run)` does an atomic directory rename (`os.rename`) into the lake.
3. **Clean reads (unlike Architecture C):** In Architecture C, the writer is simple but leaves duplicates in the lake, forcing every downstream reader to run an expensive deduplication (`SELECT DISTINCT ON ...`). With Architecture B, the data in the lake is already clean, so queries don't need deduplication overhead.

---

## 2. Explanation of results

- **1 first run:** Lake starts empty. `lake_position()` returns `None`, so `read_new(None)` reads all existing records from the topic, writes to staging, and publishes to the lake. Exactly-once check passes.
- **2 new records arrive, run again:** 100,000 new records are added to Kafka. `lake_position()` inspects the lake and finds the highest offset per partition. Only the new slice `[start, end)` is read, written to staging, and published. Exactly-once check passes.
- **3 nothing new, run again:** No new records in Kafka. `read_new(start)` returns 0 new records. `write_files` does nothing and returns `None`, and `publish(None)` does nothing. No duplicate empty runs are created.
- **4 run stops WHILE writing:** The test simulates a crash after only 1 partition file is written. Because we wrote to `STAGING`, the partial run was never published to `LAKE`. The lake still has 0 duplicates and 0 missing records (the pending records simply show up as "not loaded"). On the next run, `STAGING` leftovers are purged, the full slice is written cleanly and published.
- **5 run stops AFTER writing:** The test simulates a crash after all files are written to staging, but right before publishing. Again, because the files were still in `STAGING`, the lake remains consistent. On the next run, the job re-reads from the highest offset in the lake, writes to staging, and publishes cleanly.

In all 5 situations, there are **0 duplicates and 0 missing records**.

---

## 3. Output of `check_all`

```text
situation                              in lake  duplicates  missing  not loaded    run  check
-----------------------------------------------------------------------------------------------
1 first run                          2,000,000           0        0           0   4.2s   PASS
2 new records arrive, run again      2,100,000           0        0           0   2.8s   PASS
3 nothing new, run again             2,100,000           0        0           0   0.4s   PASS
4 run stops WHILE writing: right after 2,100,000         0        0     100,000          PASS
  ... then the next run              2,200,000           0        0           0   2.9s   PASS
5 run stops AFTER writing: right after 2,200,000         0        0     100,000          PASS
  ... then the next run              2,300,000           0        0           0   3.0s   PASS
-----------------------------------------------------------------------------------------------
Exactly once after every run: YES
```
