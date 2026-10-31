"""Real concurrency test: several separate database connections try to book at the same instant.
Run from the repo root with the venv active:   python database/postgres/tests/concurrency_test.py
Uses the limited app role from .env. All test bookings are removed afterwards (slots return to AVAILABLE)."""
import sys, threading, time
from collections import Counter
from pathlib import Path

import psycopg
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts"))
from _env import pg_kwargs

results = []


def connect():
    return psycopg.connect(**pg_kwargs(), autocommit=False)


def book(barrier, patient_id, slot_id, out, tag):
    con = connect()
    try:
        barrier.wait()                                   # all threads fire together
        t0 = time.perf_counter()
        try:
            with con.transaction():
                con.execute("SELECT book_appointment(%s, %s, NULL, 'concurrency test')", (patient_id, slot_id))
            out.append(("OK", time.perf_counter() - t0, tag))
        except psycopg.Error as e:
            out.append((e.sqlstate, time.perf_counter() - t0, tag))
    finally:
        con.close()


def run_threads(jobs):
    barrier = threading.Barrier(len(jobs))
    out = []
    ts = [threading.Thread(target=book, args=(barrier, p, s, out, i)) for i, (p, s) in enumerate(jobs)]
    [t.start() for t in ts]
    [t.join() for t in ts]
    return out


def check(name, ok, detail):
    results.append(ok)
    print(f"[{'PASS' if ok else 'FAIL'}] {name}  ->  {detail}")


con = connect()
cur = con.cursor()
cur.execute("""select p.patient_id from patients p join users u using(user_id)
               where u.is_active and u.email between 'patient21@mediconnect.test' and 'patient29@mediconnect.test'
               order by u.email""")
patients = [r[0] for r in cur.fetchall()]
cur.execute("""select slot_id from time_slots where status='AVAILABLE' and start_ts > now() + interval '3 days'
               order by start_ts, doctor_id limit 1""")
one_slot = cur.fetchone()[0]
cur.execute("""select t1.slot_id, t2.slot_id from time_slots t1 join time_slots t2
               on t1.start_ts = t2.start_ts and t1.doctor_id < t2.doctor_id
               where t1.status='AVAILABLE' and t2.status='AVAILABLE' and t1.start_ts > now() + interval '4 days'
               order by t1.start_ts desc limit 1""")
pair = cur.fetchone()
cur.execute("""select slot_id from time_slots where status='AVAILABLE' and start_ts > now() + interval '5 days'
               order by start_ts desc, doctor_id limit 400""")
distinct = []
seen = set()
cur.execute("""select distinct on (doctor_id) slot_id from time_slots where status='AVAILABLE' and start_ts > now() + interval '6 days'
               order by doctor_id, start_ts""")
distinct = [r[0] for r in cur.fetchall()][:8]
con.rollback()

print(f"\n=== Scenario 1: {len(patients)} patients race for ONE slot ===")
out = run_threads([(p, one_slot) for p in patients])
c = Counter(r[0] for r in out)
print("outcomes:", dict(c))
cur.execute("select count(*) from appointments where slot_id=%s and status<>'CANCELLED'", (one_slot,))
active = cur.fetchone()[0]
cur.execute("select status from time_slots where slot_id=%s", (one_slot,))
slot_status = cur.fetchone()[0]
check("Exactly one booking wins", c["OK"] == 1 and c["MC001"] == len(patients) - 1, f"{c['OK']} success, {c['MC001']} rejected with MC001 (slot taken)")
check("Database holds exactly one active appointment for the slot", active == 1 and slot_status == "BOOKED", f"active={active}, slot status={slot_status}")
print(f"latency: winner {min(r[1] for r in out if r[0]=='OK')*1000:.1f} ms, slowest loser {max(r[1] for r in out)*1000:.1f} ms")

print("\n=== Scenario 2: ONE patient races for TWO overlapping slots (different doctors, same time) ===")
out2 = run_threads([(patients[0], pair[0]), (patients[0], pair[1])]) if pair else []
c2 = Counter(r[0] for r in out2)
print("outcomes:", dict(c2))
check("Patient ends up with one appointment, other attempt gets MC008", c2["OK"] == 1 and c2["MC008"] == 1, f"{dict(c2)}")

jobs3 = list(zip(patients[2:], distinct))
print(f"\n=== Scenario 3: {len(jobs3)} different patients book {len(jobs3)} DIFFERENT slots at once ===")
out3 = run_threads(jobs3)
c3 = Counter(r[0] for r in out3)
print("outcomes:", dict(c3))
check("Independent bookings do not block each other", c3["OK"] == len(jobs3), f"{dict(c3)}")
print(f"latency: median {sorted(r[1] for r in out3)[len(out3)//2]*1000:.1f} ms, max {max(r[1] for r in out3)*1000:.1f} ms")

# cleanup: delete the test bookings; trigger trg_appt_sync_slot returns each slot to AVAILABLE
slots = [one_slot] + list(pair or []) + list(distinct)
cur.execute("delete from appointments where reason='concurrency test' and slot_id = any(%s)", (slots,))
cur.execute("select count(*) from time_slots where slot_id = any(%s) and status<>'AVAILABLE'", (slots,))
stuck = cur.fetchone()[0]
con.commit()
check("Cleanup returns every test slot to AVAILABLE", stuck == 0, f"{stuck} slots not released")
print(f"\n{sum(results)} of {len(results)} checks passed")
sys.exit(0 if all(results) else 1)
