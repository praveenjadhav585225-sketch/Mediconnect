"""Generates docs/05-data-dictionary.md from the LIVE PostgreSQL schema (so it can never drift from the code).
   python database/scripts/generate_data_dictionary.py        (uses PG_ADMIN_* from .env)"""
from pathlib import Path
import psycopg
from _env import pg_kwargs

out = Path(__file__).resolve().parents[2] / "docs" / "05-data-dictionary.md"
with psycopg.connect(**pg_kwargs(admin=True)) as con:
    cur = con.cursor()
    cur.execute("select table_name from information_schema.tables where table_schema='public' and table_type='BASE TABLE' order by table_name")
    tables = [r[0] for r in cur.fetchall()]
    lines = ["# MediConnect Data Dictionary (PostgreSQL)", "",
             "Generated from the live schema by `database/scripts/generate_data_dictionary.py`.", ""]
    for t in tables:
        lines += [f"## {t}", "", "| Column | Type | Null? | Default |", "|---|---|---|---|"]
        cur.execute("""select a.attname, format_type(a.atttypid, a.atttypmod), not a.attnotnull,
                              coalesce(pg_get_expr(d.adbin, d.adrelid), '') , a.attgenerated <> ''
                       from pg_attribute a left join pg_attrdef d on d.adrelid=a.attrelid and d.adnum=a.attnum
                       where a.attrelid = %s::regclass and a.attnum > 0 and not a.attisdropped order by a.attnum""", (f"public.{t}",))
        for name, typ, nullable, default, generated in cur.fetchall():
            default = "(generated)" if generated else default.replace("|", "\\|")[:60]
            lines.append(f"| {name} | {typ} | {'YES' if nullable else 'NO'} | {default} |")
        cur.execute("""select conname, case contype when 'p' then 'PRIMARY KEY' when 'f' then 'FOREIGN KEY' when 'u' then 'UNIQUE'
                              when 'c' then 'CHECK' when 'x' then 'EXCLUDE' end, pg_get_constraintdef(oid)
                       from pg_constraint where conrelid = %s::regclass order by contype, conname""", (f"public.{t}",))
        lines += ["", "**Constraints**", "", "| Name | Kind | Definition |", "|---|---|---|"]
        for n, k, d in cur.fetchall():
            lines.append(f"| {n} | {k} | `{d.replace('|', chr(92)+'|')}` |")
        lines.append("")
out.write_text("\n".join(lines))
print(f"wrote {out} ({len(tables)} tables)")
