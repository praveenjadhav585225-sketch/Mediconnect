"""
MediConnect synthetic data generator.

Writes (all SYNTHETIC - no real patient data, no real people):
  database/postgres/seed/01_reference_and_users.sql
  database/postgres/seed/02_cases.sql
  database/postgres/seed/03_slots_appointments.sql
  database/mongodb/seed/seed_all.js
  database/synthetic-data/case_texts.json     (text that gets embedded by embed_cases.py)

Run (optional - the generated files are already committed):
  pip install argon2-cffi
  python database/synthetic-data/generate_seed.py

Everything is deterministic (fixed random seed + uuid5 ids) so reruns give the same ids.
Only password hashes differ between runs (random salts).

Demo login password for every synthetic account:  Demo@12345
Narratives only DESCRIBE symptoms. No diagnosis or treatment text is generated anywhere.
"""
import hashlib
import json
import random
import re
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path

from argon2 import PasswordHasher

ROOT = Path(__file__).resolve().parents[2]
PG_SEED = ROOT / "database" / "postgres" / "seed"
MONGO_SEED = ROOT / "database" / "mongodb" / "seed"
SYN = ROOT / "database" / "synthetic-data"

NS = uuid.UUID("6f1d2c3e-8a41-4b7e-9c55-2d0f3a6b7e10")
REF = datetime(2026, 10, 31, 9, 0, tzinfo=timezone.utc)  # reference "today" for historic timestamps
DEMO_PASSWORD = "Demo@12345"
rng = random.Random(42)
ph = PasswordHasher()


def uid(kind: str, key) -> uuid.UUID:
    return uuid.uuid5(NS, f"{kind}:{key}")


def md5_uuid(text: str) -> uuid.UUID:
    return uuid.UUID(hashlib.md5(text.encode()).hexdigest())


def q(s):
    """SQL string literal (or NULL)."""
    if s is None:
        return "NULL"
    return "'" + str(s).replace("'", "''") + "'"


def iso(dt):
    return dt.strftime("%Y-%m-%d %H:%M:%S+00")


# ----------------------------------------------------------------- reference data
SPECS = [
    ("Cardiology", "Heart and blood-vessel conditions"),
    ("Dermatology", "Skin, hair and nail conditions"),
    ("Neurology", "Brain, nerve and headache conditions"),
    ("Orthopedics", "Bones, joints and muscles"),
    ("Pulmonology", "Lung and breathing conditions"),
    ("Gastroenterology", "Digestive system conditions"),
    ("Endocrinology", "Hormone and metabolic conditions"),
    ("General Medicine", "First-contact and everyday health concerns"),
]
SPEC_ID = {name: i + 1 for i, (name, _) in enumerate(SPECS)}  # identity starts at 1 on a fresh schema

FIRST = ["Aarav", "Vivaan", "Aditya", "Arjun", "Rohan", "Karthik", "Siddharth", "Nikhil", "Rahul", "Varun",
         "Ananya", "Diya", "Isha", "Kavya", "Meera", "Neha", "Priya", "Riya", "Sneha", "Tanvi",
         "Rajesh", "Suresh", "Mahesh", "Lakshmi", "Sunita", "Deepa", "Anil", "Vikram", "Pooja", "Swati"]
LAST = ["Sharma", "Iyer", "Reddy", "Nair", "Menon", "Gowda", "Patil", "Kulkarni", "Rao", "Shetty",
        "Hegde", "Bhat", "Joshi", "Desai", "Kapoor", "Mehta", "Naidu", "Pillai", "Verma", "Das"]

# (full_name, specialization, years, fee, status, bio)
DOCTORS = [
    ("Meera Iyer", "Cardiology", 18, 900, "VERIFIED", "Consultant cardiologist with interest in heart rhythm and blood pressure clinics."),
    ("Rajesh Nair", "Cardiology", 12, 800, "VERIFIED", "Cardiology specialist focused on preventive heart health and exercise testing."),
    ("Kavya Reddy", "Dermatology", 9, 700, "VERIFIED", "Dermatologist treating rashes, eczema, acne and hair or nail concerns."),
    ("Arjun Menon", "Neurology", 15, 1000, "VERIFIED", "Neurologist for headache, migraine, numbness and dizziness consultations."),
    ("Sunita Patil", "Orthopedics", 20, 850, "VERIFIED", "Orthopedic consultant for joint, spine and sports injury problems."),
    ("Vikram Rao", "Pulmonology", 14, 800, "VERIFIED", "Pulmonologist managing cough, wheeze, breathlessness and sleep-related breathing issues."),
    ("Deepa Kulkarni", "Gastroenterology", 11, 750, "VERIFIED", "Gastroenterologist for acidity, bloating, abdominal pain and bowel concerns."),
    ("Anil Shetty", "Endocrinology", 16, 900, "VERIFIED", "Endocrinologist focused on diabetes, thyroid and weight-related concerns."),
    ("Priya Desai", "General Medicine", 8, 500, "VERIFIED", "General physician for fever, infections, fatigue and routine health check-ups."),
    ("Mahesh Joshi", "General Medicine", 22, 600, "VERIFIED", "Senior general physician with long experience in family medicine."),
    ("Neha Kapoor", "General Medicine", 3, 450, "PENDING", "Recently registered general physician awaiting verification."),
    ("Suresh Gowda", "General Medicine", 25, 600, "SUSPENDED", "General physician (account suspended for demonstration of admin controls)."),
]

# --------------------------------------------------------------- symptom clusters
CLUSTERS = {
    "Cardiology": dict(
        symptoms=[("chest tightness on exertion", "a tight, heavy feeling in the chest when I climb stairs or walk fast"),
                  ("racing heartbeat", "episodes where my heart seems to race or flutter without warning"),
                  ("breathlessness on stairs", "becoming short of breath after one or two flights of stairs"),
                  ("dizziness on standing", "feeling light-headed when I stand up quickly"),
                  ("swollen ankles", "swelling around both ankles by the evening"),
                  ("tiredness with light activity", "unusual tiredness even after light household work"),
                  ("chest discomfort at rest", "a dull pressure in the centre of the chest while sitting")],
        contexts=["after climbing stairs", "when I walk uphill", "in the evening", "after heavy meals", "during stressful days"]),
    "Dermatology": dict(
        symptoms=[("itchy red patches", "itchy red patches on my forearms and elbows"),
                  ("dry flaking skin", "dry, flaking skin on my hands and legs"),
                  ("rash after sun exposure", "a rash that appears after I spend time in the sun"),
                  ("painful bumps on face", "small painful bumps along my cheeks and jaw"),
                  ("patchy hair thinning", "patches where my hair has become thin"),
                  ("skin discolouration", "lighter patches of skin on my neck and shoulders"),
                  ("blisters on hands", "small fluid-filled blisters on my palms")],
        contexts=["in dry weather", "after sweating", "after using certain soaps", "at night", "during humid days"]),
    "Neurology": dict(
        symptoms=[("one-sided headaches", "throbbing headaches that settle on one side of my head"),
                  ("light sensitivity", "bright lights becoming uncomfortable during headaches"),
                  ("numb fingers", "numbness in my fingertips, mostly in the morning"),
                  ("tingling in feet", "a pins-and-needles feeling in both feet"),
                  ("spells of dizziness", "short spells of spinning dizziness"),
                  ("poor concentration", "trouble concentrating on work for long periods"),
                  ("memory lapses", "forgetting recent conversations and appointments")],
        contexts=["after poor sleep", "during screen-heavy days", "in the morning", "when I skip meals", "in bright sunlight"]),
    "Orthopedics": dict(
        symptoms=[("knee pain on stairs", "pain in my knee when going up or down stairs"),
                  ("morning back stiffness", "stiffness in my lower back that eases after moving around"),
                  ("shoulder pain lifting arm", "pain in my shoulder when I lift my arm above my head"),
                  ("swollen ankle after twist", "a swollen, tender ankle after a twisting fall"),
                  ("wrist pain when typing", "an aching wrist after long hours of typing"),
                  ("hip pain after walking", "an ache in the hip after walking for twenty minutes"),
                  ("limited neck movement", "difficulty turning my neck fully to the right")],
        contexts=["after sitting for long hours", "after exercise", "in cold weather", "when I wake up", "when carrying bags"]),
    "Pulmonology": dict(
        symptoms=[("persistent dry cough", "a dry cough that has not gone away"),
                  ("night-time wheezing", "a whistling sound in my chest at night"),
                  ("breathlessness when walking", "getting short of breath when walking at a normal pace"),
                  ("chest tightness in cold air", "a tight chest when I step into cold air"),
                  ("cough with phlegm", "a cough that brings up phlegm in the morning"),
                  ("breathlessness lying flat", "needing extra pillows because lying flat makes breathing uncomfortable"),
                  ("frequent chest infections", "repeated chest infections over the last few months")],
        contexts=["in the early morning", "in dusty places", "during seasonal changes", "after climbing stairs", "at night"]),
    "Gastroenterology": dict(
        symptoms=[("burning after meals", "a burning feeling behind the breastbone after meals"),
                  ("bloating", "persistent bloating and a feeling of fullness"),
                  ("stomach cramps", "cramping pain in the lower abdomen"),
                  ("morning nausea", "nausea that is strongest early in the morning"),
                  ("loose stools", "loose stools several times a day"),
                  ("constipation", "difficulty passing stools for several days at a time"),
                  ("upper abdominal pain", "a gnawing pain in the upper abdomen")],
        contexts=["after spicy food", "after skipping meals", "late at night", "after tea or coffee", "when I am stressed"]),
    "Endocrinology": dict(
        symptoms=[("excess thirst", "feeling thirsty all the time"),
                  ("frequent urination", "needing to pass urine much more often than before"),
                  ("unexplained weight change", "losing weight without trying"),
                  ("cold intolerance and fatigue", "feeling tired and unusually cold compared with others"),
                  ("excessive sweating", "sweating heavily even in cool rooms"),
                  ("trembling hands", "a fine tremor in both hands"),
                  ("hair loss", "more hair than usual coming out when I comb it")],
        contexts=["through the day", "at night", "after meals", "during the afternoon", "for several weeks now"]),
    "General Medicine": dict(
        symptoms=[("fever with body ache", "a fever with aching muscles and chills"),
                  ("sore throat", "a sore, scratchy throat that hurts when swallowing"),
                  ("runny nose and sneezing", "a blocked, runny nose with frequent sneezing"),
                  ("headache and tiredness", "a dull headache with constant tiredness"),
                  ("loss of appetite", "little interest in food for several days"),
                  ("joint aches", "aching joints without any injury"),
                  ("general weakness", "a general feeling of weakness and low energy")],
        contexts=["in the evening", "since the weather changed", "after a family member fell ill", "through the day", "when I try to work"]),
}
OPENERS = ["For about {d} days I have noticed {s}.", "Over the last {d} days there has been {s}.",
           "I have been experiencing {s} for roughly {d} days.", "Starting around {d} days ago, I developed {s}."]
ALSO = ["I also have {s}.", "Along with this there is {s}.", "In addition, I have been having {s}."]
CLOSERS = ["It is affecting my daily routine.", "It has not improved on its own.",
           "It comes and goes through the day.", "I would like a doctor to review this.",
           "It is slightly worse than last week."]


def make_case(spec_name):
    cl = CLUSTERS[spec_name]
    syms = rng.sample(cl["symptoms"], k=rng.choice([2, 3, 3, 4]))
    days = rng.choice([3, 5, 7, 10, 14, 21, 30, 45, 60, 90])
    parts = [rng.choice(OPENERS).format(d=days, s=syms[0][1])]
    for s in syms[1:]:
        parts.append(rng.choice(ALSO).format(s=s[1]))
    parts.append(f"It tends to be worse {rng.choice(cl['contexts'])}.")
    parts.append(rng.choice(CLOSERS))
    narrative = " ".join(parts)
    title = f"{syms[0][0].capitalize()} for {days} days"
    severity = rng.choice(["LOW", "MODERATE", "MODERATE", "HIGH"])
    sym_docs = [{"name": s[0], "onset_days": max(1, days - rng.randint(0, min(days - 1, 5))),
                 "intensity": rng.randint(2, 9)} for s in syms]
    summary = (f"Adult presenting with {syms[0][0]}"
               + (f" and {syms[1][0]}" if len(syms) > 1 else "")
               + f" for about {days} days; {severity.lower()} severity.")
    vitals = {"temperature_c": round(rng.uniform(36.3, 38.9), 1) if spec_name == "General Medicine" else round(rng.uniform(36.2, 37.4), 1),
              "heart_rate": rng.randint(60, 112), "bp_systolic": rng.randint(105, 148),
              "bp_diastolic": rng.randint(68, 94), "spo2": rng.randint(94, 99)}
    return dict(title=title, narrative=narrative, days=days, severity=severity,
                symptoms=sym_docs, summary=summary, vitals=vitals)


# ----------------------------------------------------------------------- users
users, patients, doctors = [], [], []
pw_hash = lambda: ph.hash(DEMO_PASSWORD)

users.append(dict(id=uid("user", "admin"), email="admin@mediconnect.test", role="ADMIN"))

used = set()
for i in range(30):
    while True:
        name = f"{rng.choice(FIRST)} {rng.choice(LAST)}"
        if name not in used:
            used.add(name)
            break
    uidv = uid("user", f"patient{i+1}")
    users.append(dict(id=uidv, email=f"patient{i+1:02d}@mediconnect.test", role="PATIENT"))
    dob = datetime(1950, 1, 1) + timedelta(days=rng.randint(0, 365 * 58))
    patients.append(dict(id=uid("patient", i + 1), user_id=uidv, name=name, dob=dob.date().isoformat(),
                         gender=rng.choice(["MALE", "FEMALE", "OTHER"]) if i % 15 == 14 else ("MALE" if i % 2 else "FEMALE"),
                         phone=f"+9190000{i+1:05d}"))

for i, (name, spec, yrs, fee, status, bio) in enumerate(DOCTORS):
    uidv = uid("user", f"doctor{i+1}")
    users.append(dict(id=uidv, email=f"doctor{i+1:02d}@mediconnect.test", role="DOCTOR"))
    doctors.append(dict(id=uid("doctor", i + 1), user_id=uidv, name=name, spec=spec, years=yrs, fee=fee,
                        status=status, bio=bio, license=f"KMC-{2010 + i}-{10001 + i}"))

# ------------------------------------------------------ 01_reference_and_users.sql
sql = ["-- 01_reference_and_users.sql  (SYNTHETIC DATA. Generated by synthetic-data/generate_seed.py)",
       "-- Demo password for every account: Demo@12345 (stored only as an Argon2id hash)", "BEGIN;", ""]
sql.append("INSERT INTO specializations (name, description) VALUES")
sql.append(",\n".join(f"  ({q(n)}, {q(d)})" for n, d in SPECS) + ";\n")
sql.append("INSERT INTO users (user_id, email, password_hash, role, is_active, created_at) VALUES")
rows = []
for u in users:
    created = REF - timedelta(days=rng.randint(40, 400))
    active = "false" if u["email"] == "patient30@mediconnect.test" else "true"  # one inactive user for the admin demo
    rows.append(f"  ({q(u['id'])}, {q(u['email'])}, {q(pw_hash())}, {q(u['role'])}, {active}, {q(iso(created))})")
sql.append(",\n".join(rows) + ";\n")
sql.append("INSERT INTO patients (patient_id, user_id, full_name, date_of_birth, gender, phone) VALUES")
sql.append(",\n".join(f"  ({q(p['id'])}, {q(p['user_id'])}, {q(p['name'])}, {q(p['dob'])}, {q(p['gender'])}, {q(p['phone'])})" for p in patients) + ";\n")
sql.append("INSERT INTO doctors (doctor_id, user_id, specialization_id, full_name, license_number, experience_years, consultation_fee, bio, verification_status) VALUES")
sql.append(",\n".join(f"  ({q(d['id'])}, {q(d['user_id'])}, {SPEC_ID[d['spec']]}, {q(d['name'])}, {q(d['license'])}, {d['years']}, {d['fee']}, {q(d['bio'])}, {q(d['status'])})" for d in doctors) + ";\n")

rules = []
verified = [d for d in doctors if d["status"] == "VERIFIED"]
for di, d in enumerate(verified):
    slot_len = [30, 30, 20, 30, 45, 30, 15, 30, 30, 20][di]
    for dow in range(1, 6):  # Mon-Fri morning
        rules.append((d["id"], dow, "09:00", "13:00", slot_len))
    if di % 3 == 0:
        for dow in (2, 4):  # some afternoons
            rules.append((d["id"], dow, "15:00", "17:00", slot_len))
sql.append("INSERT INTO availability_rules (doctor_id, day_of_week, start_time, end_time, slot_minutes) VALUES")
sql.append(",\n".join(f"  ({q(a)}, {b}, {q(c)}, {q(e)}, {f})" for a, b, c, e, f in rules) + ";\n")
sql.append("COMMIT;")
(PG_SEED / "01_reference_and_users.sql").write_text("\n".join(sql) + "\n")

# ------------------------------------------------------------------- cases
cases, case_texts = [], []
HIST_PER_SPEC = 8
spec_names = [s[0] for s in SPECS]
for si, sname in enumerate(spec_names):
    for k in range(HIST_PER_SPEC):
        c = make_case(sname)
        c.update(id=uid("case", f"{sname}-{k}"), spec=sname,
                 patient=patients[(si * 7 + k * 3) % 30]["id"],
                 status="RESOLVED" if k % 2 == 0 else "CLOSED",
                 consent=(si * HIST_PER_SPEC + k) % 7 != 0,       # roughly 1 in 7 did NOT consent
                 created=REF - timedelta(days=rng.randint(60, 700), hours=rng.randint(0, 20)))
        cases.append(c)
# active (submitted) cases for the demo: patients 1-6, one per specialization
for i, sname in enumerate(spec_names[:6]):
    c = make_case(sname)
    c.update(id=uid("case", f"active-{sname}"), spec=sname, patient=patients[i]["id"], status="SUBMITTED",
             consent=True, created=REF - timedelta(days=rng.randint(0, 3), hours=rng.randint(0, 10)))
    cases.append(c)
# one case that failed mid-way, for the DRAFT_INCOMPLETE recovery demo
c = make_case("General Medicine")
c.update(id=uid("case", "draft-incomplete"), spec="General Medicine", patient=patients[9]["id"],
         status="DRAFT_INCOMPLETE", consent=False, created=REF - timedelta(hours=5))
cases.append(c)

sql = ["-- 02_cases.sql  (SYNTHETIC. Case header only. The narrative lives in MongoDB case_details.)", "BEGIN;", "",
       "INSERT INTO medical_cases (case_id, patient_id, title, specialization_id, severity, duration_days, status, consent_for_matching, mongo_detail_id, created_at, updated_at) VALUES"]
sql.append(",\n".join(
    f"  ({q(c['id'])}, {q(c['patient'])}, {q(c['title'])}, {SPEC_ID[c['spec']]}, {q(c['severity'])}, {c['days']}, {q(c['status'])}, {str(c['consent']).lower()}, {q(c['id'])}, {q(iso(c['created']))}, {q(iso(c['created']))})"
    for c in cases) + ";")
sql.append("\nCOMMIT;")
(PG_SEED / "02_cases.sql").write_text("\n".join(sql) + "\n")

for c in cases:
    if c["status"] != "DRAFT_INCOMPLETE":  # the draft has no mongo doc and no embedding
        case_texts.append({"case_id": str(c["id"]), "text": f"{c['title']}. {c['narrative']}"})
(SYN / "case_texts.json").write_text(json.dumps(case_texts, indent=1))

# -------------------------------------------- 03_slots_appointments.sql (relative to load date)
N_PAST = 30
past_status = lambda rn: "CANCELLED" if rn % 6 == 0 else ("NO_SHOW" if rn % 6 == 5 else "COMPLETED")
sql = f"""-- 03_slots_appointments.sql  (SYNTHETIC)
-- Slots are generated relative to the day you load the seed: 21 days back, 13 days ahead.
-- Appointments, consultations and reviews use deterministic ids, so MongoDB seeds can reference them.
SET timezone = 'Asia/Kolkata';
BEGIN;

-- 1. Slots from the weekly availability rules (this is what generate_slots() will do in Day 3)
INSERT INTO time_slots (doctor_id, start_ts, end_ts)
SELECT r.doctor_id, ts, ts + make_interval(mins => r.slot_minutes)
FROM availability_rules r
CROSS JOIN generate_series(current_date::timestamp - interval '21 days', current_date::timestamp + interval '13 days', interval '1 day') AS d(day)
CROSS JOIN LATERAL generate_series(d.day + r.start_time,
                                   d.day + r.end_time - make_interval(mins => r.slot_minutes),
                                   make_interval(mins => r.slot_minutes)) AS ts
WHERE extract(dow FROM d.day) = r.day_of_week;

-- 2. Thirty past appointments. rn picks doctor (rn-1)%10, patient (rn-1)%30, and that doctor's ((rn-1)/10+1)-th slot.
WITH vd AS (SELECT doctor_id, row_number() OVER (ORDER BY license_number COLLATE "C") - 1 AS di
            FROM doctors WHERE verification_status = 'VERIFIED'),
     pt AS (SELECT p.patient_id, row_number() OVER (ORDER BY u.email COLLATE "C") - 1 AS pi
            FROM patients p JOIN users u USING (user_id)),
     ps AS (SELECT slot_id, doctor_id, start_ts, end_ts,
                   row_number() OVER (PARTITION BY doctor_id ORDER BY start_ts) AS sn
            FROM time_slots WHERE end_ts < now() - interval '1 hour'),
     seq AS (SELECT n AS rn FROM generate_series(1, {N_PAST}) n)
INSERT INTO appointments (appointment_id, patient_id, doctor_id, slot_id, status, reason, booked_at, cancelled_at, cancel_reason)
SELECT md5('appt:' || rn)::uuid, pt.patient_id, vd.doctor_id, ps.slot_id,
       CASE WHEN rn % 6 = 0 THEN 'CANCELLED' WHEN rn % 6 = 5 THEN 'NO_SHOW' ELSE 'COMPLETED' END,
       'Synthetic follow-up visit', ps.start_ts - interval '3 days',
       CASE WHEN rn % 6 = 0 THEN ps.start_ts - interval '1 day' END,
       CASE WHEN rn % 6 = 0 THEN 'Patient unavailable (synthetic)' END
FROM seq
JOIN vd ON vd.di = (rn - 1) % 10
JOIN pt ON pt.pi = (rn - 1) % 30
JOIN ps ON ps.doctor_id = vd.doctor_id AND ps.sn = (rn - 1) / 10 + 1;

-- 3. Consultations for COMPLETED appointments, ids derived from the appointment id
INSERT INTO consultations (consultation_id, appointment_id, status, started_at, ended_at, follow_up_required, notes_doc_id)
SELECT md5('consult:' || a.appointment_id::text)::uuid, a.appointment_id, 'COMPLETED', s.start_ts, s.end_ts,
       get_byte(decode(md5(a.appointment_id::text), 'hex'), 2) % 5 = 0,
       md5('consult:' || a.appointment_id::text)::uuid::text
FROM appointments a JOIN time_slots s USING (slot_id)
WHERE a.status = 'COMPLETED';

-- 4. Reviews for roughly three quarters of completed consultations
INSERT INTO reviews (consultation_id, rating, comment, created_at)
SELECT c.consultation_id,
       3 + get_byte(decode(md5(c.consultation_id::text), 'hex'), 0) % 3,
       CASE get_byte(decode(md5(c.consultation_id::text), 'hex'), 1) % 3
            WHEN 0 THEN 'Clear explanation, on time.' WHEN 1 THEN 'Smooth video session (synthetic).' ELSE NULL END,
       c.ended_at + interval '2 hours'
FROM consultations c
WHERE get_byte(decode(md5(c.consultation_id::text), 'hex'), 1) % 4 <> 0;

-- 5. Demo scenario: each active SUBMITTED case gets the earliest future slot of a VERIFIED doctor in its specialization
INSERT INTO appointments (patient_id, doctor_id, slot_id, case_id, status, reason, booked_at)
SELECT c.patient_id, s.doctor_id, s.slot_id, c.case_id, 'BOOKED', 'Consultation for submitted case', now() - interval '2 hours'
FROM medical_cases c
CROSS JOIN LATERAL (
    SELECT ts.slot_id, ts.doctor_id
    FROM time_slots ts JOIN doctors d ON d.doctor_id = ts.doctor_id
    WHERE d.specialization_id = c.specialization_id AND d.verification_status = 'VERIFIED'
      AND ts.status = 'AVAILABLE' AND ts.start_ts > now() + interval '1 day'
    ORDER BY ts.start_ts, d.license_number COLLATE "C" LIMIT 1) s
WHERE c.status = 'SUBMITTED';

UPDATE time_slots SET status = 'BOOKED'
WHERE slot_id IN (SELECT slot_id FROM appointments WHERE status <> 'CANCELLED');

-- 6. Eight more future bookings without a case (every second one already confirmed)
WITH vd AS (SELECT doctor_id, row_number() OVER (ORDER BY license_number COLLATE "C") - 1 AS di
            FROM doctors WHERE verification_status = 'VERIFIED'),
     pt AS (SELECT p.patient_id, row_number() OVER (ORDER BY u.email COLLATE "C") - 1 AS pi
            FROM patients p JOIN users u USING (user_id) WHERE u.is_active),
     fs AS (SELECT slot_id, doctor_id, row_number() OVER (PARTITION BY doctor_id ORDER BY start_ts) AS sn
            FROM time_slots WHERE status = 'AVAILABLE' AND start_ts > now() + interval '1 day'),
     seq AS (SELECT n AS rn FROM generate_series(1, 8) n)
INSERT INTO appointments (patient_id, doctor_id, slot_id, status, reason, booked_at, confirmed_at)
SELECT pt.patient_id, vd.doctor_id, fs.slot_id,
       CASE WHEN rn % 2 = 0 THEN 'CONFIRMED' ELSE 'BOOKED' END, 'Synthetic general consultation',
       now() - interval '1 day', CASE WHEN rn % 2 = 0 THEN now() - interval '20 hours' END
FROM seq JOIN vd ON vd.di = (rn + 2) % 10 JOIN pt ON pt.pi = rn + 10
JOIN fs ON fs.doctor_id = vd.doctor_id AND fs.sn = 3;

UPDATE time_slots SET status = 'BOOKED'
WHERE slot_id IN (SELECT slot_id FROM appointments WHERE status <> 'CANCELLED');

COMMIT;
"""
(PG_SEED / "03_slots_appointments.sql").write_text(sql)

(PG_SEED.parent / "run_seed.sql").write_text(
    "-- Loads all synthetic data (run AFTER run_all.sql).\n"
    "--   psql -U postgres -d mediconnect -f database/postgres/run_seed.sql\n"
    "\\set ON_ERROR_STOP on\n"
    "SET mediconnect.skip_audit = on;   -- synthetic loading should not flood the audit log\n"
    "\\ir seed/01_reference_and_users.sql\n\\ir seed/02_cases.sql\n\\ir seed/03_slots_appointments.sql\n"
    "RESET mediconnect.skip_audit;\n\\echo 'Seed loaded.'\n")

# ------------------------------------------------------------------ MongoDB seed
def D(dt):
    return f"@@DATE:{dt.strftime('%Y-%m-%dT%H:%M:%S.000Z')}@@"

case_docs = []
for c in cases:
    if c["status"] == "DRAFT_INCOMPLETE":
        continue
    case_docs.append(dict(case_id=str(c["id"]), narrative=c["narrative"], symptoms=c["symptoms"], vitals=c["vitals"],
                          medical_history_flags=rng.sample(["none_reported", "seasonal_allergies", "family_history_noted", "previous_similar_episode"], k=1),
                          attachments=[], anonymised_summary=c["summary"], created_at=D(c["created"])))

# consultation notes: same deterministic ids as the SQL seed (rn -> appointment -> consultation)
verified_sorted = sorted(verified, key=lambda d: d["license"])
notes = []
for rn in range(1, N_PAST + 1):
    if past_status(rn) != "COMPLETED":
        continue
    appt = md5_uuid(f"appt:{rn}")
    cons = md5_uuid(f"consult:{appt}")
    doc = verified_sorted[(rn - 1) % 10]
    notes.append(dict(consultation_id=str(cons), specialization=doc["spec"],
                      observations="Symptoms reviewed with the patient as described in the submitted case (synthetic placeholder).",
                      assessment_by_doctor="Doctor assessment recorded here (synthetic placeholder text).",
                      advice_by_doctor="Follow-up as scheduled (synthetic placeholder text).",
                      custom_fields={"visit_type": "video", "duration_minutes": rng.choice([15, 20, 30])},
                      updated_at=D(REF - timedelta(days=rng.randint(1, 20)))))

NOTIF_TYPES = [("APPOINTMENT_BOOKED", "Your appointment has been booked."),
               ("APPOINTMENT_CONFIRMED", "Your appointment has been confirmed by the doctor."),
               ("APPOINTMENT_CANCELLED", "An appointment was cancelled and the slot released."),
               ("CASE_SUBMITTED", "Your medical case was submitted successfully."),
               ("CONSULTATION_COMPLETED", "Your consultation summary is available."),
               ("DOCTOR_VERIFIED", "Your doctor profile has been verified.")]
notifs = []
for i in range(40):
    u = users[1 + (i * 5) % (len(users) - 1)]
    t, m = NOTIF_TYPES[i % len(NOTIF_TYPES)]
    notifs.append(dict(user_id=str(u["id"]), type=t, message=m, is_read=(i % 3 == 0),
                       created_at=D(REF - timedelta(days=rng.randint(0, 30), hours=rng.randint(0, 23)))))


def js(docs):
    text = json.dumps(docs, indent=1)
    return re.sub(r'"@@DATE:(.*?)@@"', r'new Date("\1")', text)


(MONGO_SEED / "seed_all.js").write_text(
    "// seed_all.js  (SYNTHETIC. Generated by synthetic-data/generate_seed.py)\n"
    "// Run: mongosh \"mongodb://localhost:27017/mediconnect\" database/mongodb/seed/seed_all.js\n"
    "// Safe to re-run: it clears the three collections first.\n"
    "const dbm = db.getSiblingDB('mediconnect');\n"
    "dbm.case_details.deleteMany({});\ndbm.consultation_notes.deleteMany({});\ndbm.notifications.deleteMany({});\n"
    f"dbm.case_details.insertMany({js(case_docs)});\n"
    f"dbm.consultation_notes.insertMany({js(notes)});\n"
    f"dbm.notifications.insertMany({js(notifs)});\n"
    "print('case_details:', dbm.case_details.countDocuments(), ' consultation_notes:', dbm.consultation_notes.countDocuments(), ' notifications:', dbm.notifications.countDocuments());\n")

print(f"users={len(users)} patients={len(patients)} doctors={len(doctors)} rules={len(rules)} cases={len(cases)} "
      f"case_docs={len(case_docs)} notes={len(notes)} notifications={len(notifs)}")
