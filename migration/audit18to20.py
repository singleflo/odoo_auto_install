# Read-only audit after mig18to20.py: for every migrated model, compare per column how many
# migrated records have a value in 18 vs in 20 (via /tmp/mig_idmap.json).
# Lists columns that lost values or that do not exist in 20 at all.
#   python3 audit18to20.py   (as the odoo user, same PostgreSQL server)
import json
import sys

import psycopg2

SRC_DB, DST_DB = "devsc", (sys.argv[1] if len(sys.argv) > 1 else "devsc20")
SKIP = {"id", "create_uid", "write_uid", "create_date", "write_date", "message_main_attachment_id"}
IDMAP = json.load(open("/tmp/mig_idmap.json"))
src, dst = psycopg2.connect(dbname=SRC_DB).cursor(), psycopg2.connect(dbname=DST_DB).cursor()


def columns(cr, table):
    cr.execute("SELECT column_name, data_type FROM information_schema.columns WHERE table_name=%s", [table])
    return dict(cr.fetchall())


def filled(cr, table, col, dtype, ids):
    cond = f'"{col}" IS NOT NULL'
    if dtype == "boolean":
        cond += f' AND "{col}"'
    elif dtype in ("character varying", "text"):
        cond += f" AND \"{col}\" <> ''"
    elif dtype == "jsonb":
        cond += f""" AND "{col}"::text NOT IN ('{{}}', 'null', '""')"""
    cr.execute(f'SELECT count(*) FROM "{table}" WHERE id = ANY(%s) AND {cond}', [ids])
    return cr.fetchone()[0]


report = []
for model, mapping in sorted(IDMAP.items()):
    if not mapping:
        continue
    table = model.replace(".", "_")
    scols, dcols = columns(src, table), columns(dst, table)
    if not scols or not dcols:
        continue
    old_ids = [int(k) for k in mapping]
    new_ids = list(mapping.values())
    for col, dtype in sorted(scols.items()):
        if col in SKIP:
            continue
        n_src = filled(src, table, col, dtype, old_ids)
        if not n_src:
            continue
        if col not in dcols:
            report.append((n_src, model, col, n_src, None, "MANCA NELLA 20"))
            continue
        n_dst = filled(dst, table, col, dcols[col], new_ids)
        if n_dst < n_src:
            report.append((n_src - n_dst, model, col, n_src, n_dst, "valori persi"))

print("AUDIT_START")
for lost, model, col, n_src, n_dst, kind in sorted(report, key=lambda r: (r[1], -r[0])):
    print(f"{model}.{col}: 18={n_src} 20={n_dst if n_dst is not None else '-'} ({kind})")
print("AUDIT_END")
