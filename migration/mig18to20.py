# Odoo 18 (devsc) -> Odoo 20 (devsc20) data migration, run inside odoo-bin shell -d devsc20.
# Reads the 18 database directly (psycopg2), writes through the 20 ORM.
# Real data = records without an xmlid of an installed module (demo/module data is skipped,
# but pulled in lazily when a real record points to it).
import json
import os
import re
import sys
import time
import traceback
from collections import defaultdict

import psycopg2
import psycopg2.extras

T0 = time.time()
LOGF = open("/tmp/mig.log", "a")


def log(*a):
    msg = f"[{time.time() - T0:7.1f}s] " + " ".join(str(x) for x in a)
    print(msg, flush=True)
    LOGF.write(msg + "\n")
    LOGF.flush()


ERRORS = defaultdict(list)


def err(model, oid, exc):
    text = str(exc).strip().splitlines()[0][:300] if str(exc).strip() else repr(exc)
    ERRORS[model].append((oid, text))
    if len(ERRORS[model]) <= 5:
        log("  ERR", model, oid, text)


SRC = psycopg2.connect(dbname="devsc")
SRC.set_session(readonly=True)
S = SRC.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
SRC_FS = "/odoo/.local/share/Odoo/filestore/devsc"


def q(sql, args=None):
    S.execute(sql, args or ())
    return S.fetchall()


INSTALLED = {r["name"] for r in q("SELECT name FROM ir_module_module WHERE state='installed'")}
XMLIDS = defaultdict(lambda: defaultdict(list))
for r in q("SELECT module, name, model, res_id, noupdate FROM ir_model_data WHERE res_id IS NOT NULL"):
    XMLIDS[r["model"]][r["res_id"]].append((r["module"], r["name"], r["noupdate"]))
COLS = defaultdict(dict)
for r in q("SELECT table_name, column_name, data_type FROM information_schema.columns WHERE table_schema='public'"):
    COLS[r["table_name"]][r["column_name"]] = r["data_type"]
SRC_FIELDS = defaultdict(dict)
for r in q("SELECT model, name, ttype, relation, relation_table, column1, column2, store FROM ir_model_fields"):
    SRC_FIELDS[r["model"]][r["name"]] = r

CTX = dict(
    tracking_disable=True, mail_create_nolog=True, mail_notrack=True, mail_create_nosubscribe=True,
    mail_auto_subscribe_no_notify=True, no_vat_validation=True, no_reset_password=True,
    active_test=False, lang="it_IT", install_mode=True, sale_no_log_for_new_lines=True,
)
IDMAP = defaultdict(dict)
PLANNED, STARTED, IN_PROGRESS = set(), set(), set()
NOLAZY = {"ir.attachment", "mail.message", "mail.followers", "mail.activity", "res.users"}
FORCE_UPDATE = defaultdict(set)
META = {}
DEFERRED = []  # (model, new_id, kind, fname, comodel, old_value)
MAGIC = {"id", "create_uid", "create_date", "write_uid", "write_date", "display_name",
         "message_main_attachment_id", "access_token"}
SPEC_CACHE = {}
SEL_CACHE = {}
KEY_CACHE = {}


def is_module_data(model, oid):
    return any(m in INSTALLED for m, _n, _u in XMLIDS[model].get(oid, ()))


def table_of(model):
    return env[model]._table


def jsonval(v):
    if isinstance(v, dict):
        return v.get("it_IT") or v.get("en_US") or next(iter(v.values()), False)
    return v


# ---------------------------------------------------------------- resolution
def by_xmlid(comodel, oid):
    for module, name, _u in XMLIDS[comodel].get(oid, ()):
        rec = env.ref(f"{module}.{name}", raise_if_not_found=False)
        if rec and rec._name == comodel:
            return rec.id
        m = re.match(r"^(\d+)_(.+)$", name)
        if m and int(m.group(1)) in IDMAP["res.company"]:
            rec = env.ref(f"{module}.{IDMAP['res.company'][int(m.group(1))]}_{m.group(2)}", raise_if_not_found=False)
            if rec and rec._name == comodel:
                return rec.id
    return False


KEYS = {
    "res.country": ["code"], "res.country.state": ["code", "country_id"], "res.currency": ["name"],
    "uom.uom": ["name"], "res.lang": ["code"], "resource.calendar": ["name"],
    "account.payment.term": ["name"], "account.analytic.plan": ["name"], "ir.model": ["model"],
    "product.pricelist": ["name", "currency_id"], "mail.activity.type": ["name"],
    "account.journal": ["code", "company_id"], "stock.warehouse": ["code", "company_id"],
    "stock.location": ["complete_name"], "res.partner.title": ["name"], "hr.departure.reason": ["name"],
    "account.incoterms": ["code"], "product.removal": ["method"], "crm.stage": ["name"],
    "helpdesk.stage": ["name"], "project.task.type": ["name"], "mail.message.subtype": ["name", "res_model"],
    "res.groups": ["name"],
}


def by_key(comodel, oid):
    k = (comodel, oid)
    if k in KEY_CACHE:
        return KEY_CACHE[k]
    res = False
    try:
        if comodel == "account.account":
            row = q('SELECT code_store FROM account_account WHERE id=%s', [oid])
            if row and row[0]["code_store"]:
                for cid, code in row[0]["code_store"].items():
                    newc = IDMAP["res.company"].get(int(cid))
                    if newc:
                        acc = env["account.account"].with_company(newc).search([("code", "=", code)], limit=1)
                        if acc:
                            res = acc.id
                            break
        elif comodel == "account.tax":
            row = q("SELECT name, type_tax_use, amount, company_id FROM account_tax WHERE id=%s", [oid])
            if row:
                r = row[0]
                newc = IDMAP["res.company"].get(r["company_id"])
                names = list(r["name"].values()) if isinstance(r["name"], dict) else [r["name"]]
                if newc:
                    tax = env["account.tax"].search([("company_id", "=", newc), ("type_tax_use", "=", r["type_tax_use"]),
                                                     ("amount", "=", r["amount"]), ("name", "in", names)], limit=1)
                    if not tax:
                        tax = env["account.tax"].search([("company_id", "=", newc), ("type_tax_use", "=", r["type_tax_use"]),
                                                         ("amount", "=", r["amount"])], limit=1)
                    res = tax.id
        elif comodel in KEYS and COLS.get(comodel.replace(".", "_")):
            table = comodel.replace(".", "_")
            keys = [k2 for k2 in KEYS[comodel] if k2 in COLS[table]]
            row = q(f'SELECT {",".join(keys)} FROM "{table}" WHERE id=%s', [oid]) if keys else []
            if row:
                dom = []
                for k2 in keys:
                    v = row[0][k2]
                    f = env[comodel]._fields.get(k2)
                    if f is None:
                        dom = None
                        break
                    if f.type == "many2one":
                        if k2 == "company_id":
                            v = IDMAP["res.company"].get(v, False) if v else False
                        else:
                            v = resolve(f.comodel_name, v, lazy=False)
                            if not v:
                                dom = None
                                break
                    elif isinstance(v, dict):
                        vals = [x for x in v.values() if x]
                        dom.append((k2, "in", vals))
                        continue
                    dom.append((k2, "=", v))
                if dom:
                    rec = env[comodel].with_context(active_test=False).search(dom, limit=1)
                    res = rec.id
    except Exception as exc:  # noqa: BLE001
        log("  key-resolve failed", comodel, oid, exc)
    KEY_CACHE[k] = res
    return res


def resolve(comodel, oid, lazy=True):
    if not oid:
        return False
    m = IDMAP[comodel]
    if oid in m:
        return m[oid]
    new = by_xmlid(comodel, oid) or by_key(comodel, oid)
    if not new and lazy and comodel in STARTED and comodel not in NOLAZY and (comodel, oid) not in IN_PROGRESS:
        migrate_ids(comodel, [oid], lazy_note=True)
        new = m.get(oid)
    if new:
        m[oid] = new
    return new or False


# ---------------------------------------------------------------- field mapping
def source_spec(model, name, f):
    table = model.replace(".", "_")
    cols = COLS.get(table, {})
    tfields = env[model]._fields
    if f.type == "many2many":
        rel, c1, c2 = f.relation, f.column1, f.column2
        if rel in COLS and c1 in COLS[rel] and c2 in COLS[rel]:
            return ("m2m", rel, c1, c2)
        cands = [sf for sn, sf in SRC_FIELDS[model].items() if sf["ttype"] == "many2many"
                 and sf["relation"] == f.comodel_name and sn not in tfields and sf["relation_table"] in COLS]
        if len(cands) == 1:
            sf = cands[0]
            log("  rename", model, sf["name"], "->", name)
            return ("m2m", sf["relation_table"], sf["column1"], sf["column2"])
        return None
    if name in cols:
        return ("col", name)
    if f.type == "many2one":
        cands = [sn for sn, sf in SRC_FIELDS[model].items() if sf["ttype"] == "many2one" and sf["relation"] == f.comodel_name
                 and sn not in tfields and sn in cols]
        if len(cands) == 1:
            log("  rename", model, cands[0], "->", name)
            return ("col", cands[0])
    return None


def specs_for(model, exclude=(), exclude_re=None):
    key = (model, tuple(exclude), exclude_re)
    if key in SPEC_CACHE:
        return SPEC_CACHE[key]
    out = []
    for name, f in env[model]._fields.items():
        if name in MAGIC or name in exclude or (exclude_re and re.match(exclude_re, name)):
            continue
        if not f.store or f.type in ("one2many", "properties", "properties_definition"):
            continue
        if (f.compute or f.related) and f.readonly and not f.inverse:
            continue
        if f.type == "binary" and f.attachment:
            continue
        spec = source_spec(model, name, f)
        if spec:
            out.append((name, f, spec))
    SPEC_CACHE[key] = out
    return out


def valid_selection(model, name, f, v):
    k = (model, name)
    if k not in SEL_CACHE:
        try:
            SEL_CACHE[k] = {x[0] for x in f._description_selection(env)}
        except Exception:  # noqa: BLE001
            SEL_CACHE[k] = None
    return SEL_CACHE[k] is None or v in SEL_CACHE[k]


def needs_defer(model, comodel):
    return comodel == model or (comodel in PLANNED and comodel not in STARTED)


def build_vals(model, row, specs, m2m):
    vals, deferred, cdvals, trans = {}, [], [], {}
    for name, f, spec in specs:
        if spec[0] == "m2m":
            olds = m2m[name].get(row["id"], [])
            news = []
            for o in olds:
                if needs_defer(model, f.comodel_name):
                    deferred.append(("m2m", name, f.comodel_name, o))
                    continue
                n = resolve(f.comodel_name, o)
                if n:
                    news.append(n)
            if news:
                vals[name] = [(6, 0, news)]
            continue
        v = row.get(spec[1])
        if v is None:
            continue
        if f.company_dependent and isinstance(v, dict):
            cdvals.append((name, f, v))
            continue
        if f.type == "many2one":
            if needs_defer(model, f.comodel_name):
                deferred.append(("m2o", name, f.comodel_name, v))
                continue
            if f.comodel_name == "res.company":
                n = IDMAP["res.company"].get(v, False)
            else:
                n = resolve(f.comodel_name, v)
            if n:
                vals[name] = n
            continue
        if f.type == "many2one_reference":
            target = row.get(f.model_field)
            if target and target in env:
                if needs_defer(model, target):
                    deferred.append(("ref", name, target, v))
                    continue
                n = resolve(target, v, lazy=False)
                if n:
                    vals[name] = n
            continue
        if f.type == "reference":
            if isinstance(v, str) and "," in v:
                rm, rid = v.split(",", 1)
                n = rid.isdigit() and rm in env and resolve(rm, int(rid), lazy=False)
                if n:
                    vals[name] = f"{rm},{n}"
            continue
        if isinstance(v, dict) and f.type in ("char", "text", "html"):
            if f.translate:
                trans[name] = v
            v = jsonval(v)
        if f.type == "selection" and not valid_selection(model, name, f, v):
            continue
        if f.type == "binary":
            v = bytes(v)
        if f.type == "json" and isinstance(v, str):
            v = json.loads(v)
        vals[name] = v
    return vals, deferred, cdvals, trans


def conv_cd(f, v):
    if f.type == "many2one":
        return resolve(f.comodel_name, v) if v else False
    return v


# ---------------------------------------------------------------- core migration
def real_ids(model, where=""):
    table = model.replace(".", "_")
    if table not in COLS:
        return []
    ids = [r["id"] for r in q(f'SELECT id FROM "{table}" {where} ORDER BY id')]
    return [i for i in ids if not is_module_data(model, i) and i not in IDMAP[model]] + \
           [i for i in ids if i in IDMAP[model] and i not in UPDATED[model]
            and (not is_module_data(model, i) or i in FORCE_UPDATE[model])]


UPDATED = defaultdict(set)
OPTS = {}


def migrate_ids(model, ids, lazy_note=False):
    opts = OPTS.get(model, {})
    table = model.replace(".", "_")
    specs = specs_for(model, opts.get("exclude", ()), opts.get("exclude_re"))
    cols = sorted({s[1] for _n, _f, s in specs if s[0] == "col"} |
                  ({"create_date", "write_date", "create_uid", "write_uid"} & set(COLS[table])) |
                  set(opts.get("extra_cols", ())) |
                  {f.model_field for _n, f, s in specs if f.type == "many2one_reference" and f.model_field in COLS[table]})
    Model = env[model].with_context(**CTX, **opts.get("ctx", {}))
    for start in range(0, len(ids), 500):
        chunk = [i for i in ids[start:start + 500] if (model, i) not in IN_PROGRESS]
        if not chunk:
            continue
        IN_PROGRESS.update((model, i) for i in chunk)
        rows = q(f'SELECT id, {",".join(f"{chr(34)}{c}{chr(34)}" for c in cols)} FROM "{table}" WHERE id = ANY(%s) ORDER BY id', [chunk])
        m2m = {}
        for name, f, spec in specs:
            if spec[0] == "m2m":
                d = defaultdict(list)
                for r in q(f'SELECT "{spec[2]}" a, "{spec[3]}" b FROM "{spec[1]}" WHERE "{spec[2]}" = ANY(%s)', [chunk]):
                    d[r["a"]].append(r["b"])
                m2m[name] = d
        built = []
        for row in rows:
            if opts.get("skip_row") and opts["skip_row"](row):
                continue
            if any(s[0] == "col" and f.type == "many2one" and f.required and f.ondelete == "cascade"
                   and f.comodel_name in PLANNED and row.get(s[1]) and row[s[1]] not in IDMAP[f.comodel_name]
                   and is_module_data(f.comodel_name, row[s[1]]) for _n, f, s in specs):
                continue
            vals, deferred, cdvals, trans = build_vals(model, row, specs, m2m)
            if opts.get("fix_vals"):
                opts["fix_vals"](row, vals)
            built.append((row, vals, deferred, cdvals, trans))
        creates = [b for b in built if b[0]["id"] not in IDMAP[model]]
        updates = [b for b in built if b[0]["id"] in IDMAP[model]]
        # creates: batch first, record by record on failure
        new_ids = []
        if creates:
            try:
                with env.cr.savepoint():
                    recs = Model.create([b[1] for b in creates])
                new_ids = recs.ids
            except Exception:  # noqa: BLE001
                new_ids = []
                for b in creates:
                    try:
                        with env.cr.savepoint():
                            new_ids.append(Model.create(b[1]).id)
                    except Exception as exc:  # noqa: BLE001
                        new_ids.append(None)
                        err(model, b[0]["id"], exc)
        for b, nid in zip(creates, new_ids):
            if nid:
                IDMAP[model][b[0]["id"]] = nid
        for b in updates:
            nid = IDMAP[model][b[0]["id"]]
            UPDATED[model].add(b[0]["id"])
            try:
                with env.cr.savepoint():
                    Model.browse(nid).write(b[1])
            except Exception as exc:  # noqa: BLE001
                err(model, b[0]["id"], exc)
        post_batch(model, built, opts)
        if opts.get("after_batch"):
            opts["after_batch"]([(b[0], IDMAP[model].get(b[0]["id"])) for b in built])
        if not lazy_note:
            log(f"  {model}: {min(start + 500, len(ids))}/{len(ids)}")


def post_batch(model, built, opts):
    table = env[model]._table
    tcols = set(env[model]._fields)
    users = IDMAP["res.users"]
    for row, vals, deferred, cdvals, trans in built:
        nid = IDMAP[model].get(row["id"])
        if not nid:
            continue
        for kind, fname, comodel, old in deferred:
            DEFERRED.append((model, nid, kind, fname, comodel, old))
        for fname, v in trans.items():
            env.cr.execute(f'UPDATE "{table}" SET "{fname}" = %s::jsonb WHERE id = %s', [json.dumps(v), nid])
        if cdvals:
            rec = env[model].with_context(**CTX).browse(nid)
            for fname, f, d in cdvals:
                for cid, v in d.items():
                    newc = IDMAP["res.company"].get(int(cid))
                    if newc and v not in (None, False):
                        try:
                            with env.cr.savepoint():
                                rec.with_company(newc).write({fname: conv_cd(f, v)})
                        except Exception as exc:  # noqa: BLE001
                            err(model + "." + fname, row["id"], exc)
        meta = {}
        for c in ("create_date", "write_date"):
            if row.get(c) and c in tcols:
                meta[c] = row[c]
        for c in ("create_uid", "write_uid"):
            if row.get(c) and c in tcols:
                meta[c] = users.get(row[c]) or resolve("res.users", row[c], lazy=False) or 1
        if meta:
            META[(model, nid)] = meta
            env.cr.execute(f'UPDATE "{table}" SET {", ".join(f"{chr(34)}{k}{chr(34)} = %s" for k in meta)} WHERE id = %s',
                           [*meta.values(), nid])
        for module, name, noupdate in XMLIDS[model].get(row["id"], ()):
            if module not in INSTALLED and not env.ref(f"{module}.{name}", raise_if_not_found=False):
                env["ir.model.data"].create({"module": module, "name": name, "model": model, "res_id": nid,
                                             "noupdate": True})
    env.invalidate_all()


def run_model(model, ids=None, **opts):
    if model not in env:
        log("SKIP model not in 20:", model)
        return
    OPTS[model] = opts
    STARTED.add(model)
    ids = ids if ids is not None else real_ids(model, opts.get("where", ""))
    log(f"== {model}: {len(ids)} records")
    migrate_ids(model, ids)
    env.cr.commit()


def flush_deferred():
    log(f"== deferred relations: {len(DEFERRED)}")
    grouped = defaultdict(lambda: defaultdict(dict))
    for model, nid, kind, fname, comodel, old in DEFERRED:
        n = resolve(comodel, old) if kind != "ref" else resolve(comodel, old, lazy=False)
        if not n:
            continue
        cur = grouped[model][nid]
        if kind == "m2m":
            cur.setdefault(fname, []).append((4, n))
        else:
            cur[fname] = n
    for model, recs in grouped.items():
        M = env[model].with_context(**CTX)
        for nid, vals in recs.items():
            try:
                with env.cr.savepoint():
                    M.browse(nid).write(vals)
            except Exception as exc:  # noqa: BLE001
                err(model + ".deferred", nid, exc)
        log(f"  deferred {model}: {len(recs)}")
        env.cr.commit()
    DEFERRED.clear()


# ================================================================ PLAN
PLAN_MODELS = [
    "res.users", "res.partner.category", "res.partner.industry", "crm.team", "res.partner", "res.partner.bank",
    "product.category", "product.tag", "product.attribute", "product.attribute.value", "product.template",
    "product.template.attribute.line", "product.product", "product.supplierinfo", "product.pricelist",
    "product.pricelist.item", "mrp.bom", "mrp.bom.line",
    "helpdesk.stage", "helpdesk.team", "helpdesk.tag", "helpdesk.sla", "helpdesk.ticket",
    "project.tags", "project.task.type", "project.project", "project.milestone", "project.task",
    "hr.department", "hr.job", "hr.employee.category", "hr.employee", "hr.skill.type", "hr.skill.level", "hr.skill",
    "hr.employee.skill", "hr.resume.line.type", "hr.resume.line",
    "planning.role", "planning.slot.template", "planning.slot",
    "crm.stage", "crm.tag", "crm.lost.reason", "crm.lead",
    "sale.order.template", "sale.order.template.line", "sale.order.template.option", "sale.order", "sale.order.line",
    "purchase.order", "purchase.order.line", "sc.adhoc.sync.run", "calendar.event.type", "calendar.event",
    "mail.activity", "ir.attachment", "mail.message", "mail.followers",
]
PLANNED.update(PLAN_MODELS)
RU = env["res.users"].with_context(**CTX)
IT = env.ref("base.it")
EUR = env.ref("base.EUR")

# ---------------------------------------------------------------- 1. companies + charts
log("== companies")
comp_rows = {r["id"]: r for r in q("SELECT id, name, partner_id FROM res_company")}
main = env.company
IDMAP["res.company"][1] = main.id
IDMAP["res.partner"][comp_rows[1]["partner_id"]] = main.partner_id.id
FORCE_UPDATE["res.partner"].add(comp_rows[1]["partner_id"])
main.write({"name": comp_rows[1]["name"], "country_id": IT.id, "currency_id": EUR.id})
for cid, r in comp_rows.items():
    if cid != 1 and not is_module_data("res.company", cid):
        c = env["res.company"].search([("name", "=", r["name"])], limit=1) or \
            env["res.company"].create({"name": r["name"], "country_id": IT.id, "currency_id": EUR.id})
        IDMAP["res.company"][cid] = c.id
        IDMAP["res.partner"][r["partner_id"]] = c.partner_id.id
        FORCE_UPDATE["res.partner"].add(r["partner_id"])
for cid, ncid in IDMAP["res.company"].items():
    c = env["res.company"].browse(ncid)
    if c.chart_template != "it":
        try:
            env["account.chart.template"].try_loading("it", company=c, install_demo=False)
            log("  chart it loaded for", c.name)
        except Exception as exc:  # noqa: BLE001
            log("  chart load FAILED for", c.name, exc)
env.cr.commit()
STARTED.add("res.company")
OPTS["res.company"] = {"exclude_re": r"^(account_|chart_template|income_|expense_|transfer_|default_cash|.*journal|.*_account_id|.*tax|currency_exchange|fiscalyear|period_lock|tax_lock|hard_lock|sale_lock|purchase_lock|parent_|resource_calendar_id|partner_id$)"}
migrate_ids("res.company", sorted(IDMAP["res.company"]))
env.cr.commit()

# ---------------------------------------------------------------- 2. users
def user_after(pairs):
    for row, nid in pairs:
        if not nid:
            continue
        u = env["res.users"].browse(nid)
        IDMAP["res.partner"][row["partner_id"]] = u.partner_id.id
        if row.get("password"):
            env.cr.execute("UPDATE res_users SET password=%s WHERE id=%s", [row["password"], nid])


PORTAL = env.ref("base.group_portal").id


def user_vals(row, vals):
    p = q("SELECT name, email FROM res_partner WHERE id=%s", [row["partner_id"]])[0]
    vals.update(name=jsonval(p["name"]), email=p["email"])
    if vals.get("share"):
        vals["group_ids"] = [(6, 0, [PORTAL])]


run_model("res.users", fix_vals=user_vals, exclude=("partner_id", "password"), extra_cols=("partner_id", "password"), after_batch=user_after,
          where="WHERE login IS NOT NULL")
for r in q("SELECT id, partner_id FROM res_users"):  # admin/root partner mapping for demo-xmlid users
    if r["id"] in IDMAP["res.users"] or resolve("res.users", r["id"], lazy=False):
        IDMAP["res.partner"].setdefault(r["partner_id"], env["res.users"].browse(IDMAP["res.users"][r["id"]]).partner_id.id)

# ---------------------------------------------------------------- 3. partners
run_model("res.partner.category")
run_model("res.partner.industry")
run_model("crm.team", exclude=("alias_id",))
run_model("res.partner", exclude=("commercial_partner_id", "user_ids"),
          where="WHERE company_id IS NULL OR company_id NOT IN (2, 3)")
run_model("res.partner.bank")

# ---------------------------------------------------------------- 4. products
run_model("product.category")
run_model("product.tag")
run_model("product.attribute")
run_model("product.attribute.value")
SELECTABLE_ROUTES = set(env["stock.route"].with_context(active_test=False).search([("product_selectable", "=", True)]).ids)


def tmpl_vals(row, vals):
    if "route_ids" in vals:
        vals["route_ids"] = [(6, 0, [r for r in vals["route_ids"][0][2] if r in SELECTABLE_ROUTES])]


run_model("product.template", fix_vals=tmpl_vals, exclude=("product_variant_ids",), ctx={"create_product_product": True})
run_model("product.template.attribute.line")

# variants: created with their template; map them, then copy their own fields
log("== product.product mapping")
STARTED.add("product.product")
ptav_names = {}
for r in q("""SELECT pp.id, pp.product_tmpl_id,
                     array_remove(array_agg(pav.name->>'en_US' ORDER BY pav.name->>'en_US'), NULL) vals
                FROM product_product pp
           LEFT JOIN product_variant_combination c ON c.product_product_id = pp.id
           LEFT JOIN product_template_attribute_value ptav ON ptav.id = c.product_template_attribute_value_id
           LEFT JOIN product_attribute_value pav ON pav.id = ptav.product_attribute_value_id
            GROUP BY pp.id, pp.product_tmpl_id"""):
    ptav_names[r["id"]] = (r["product_tmpl_id"], tuple(r["vals"] or ()))
for oid, (otmpl, vals) in ptav_names.items():
    ntmpl = IDMAP["product.template"].get(otmpl)
    if not ntmpl:
        continue
    variants = env["product.product"].with_context(active_test=False).search([("product_tmpl_id", "=", ntmpl)])
    if len(variants) == 1:
        IDMAP["product.product"][oid] = variants.id
        continue
    for v in variants:
        names = tuple(sorted(v.product_template_attribute_value_ids.product_attribute_value_id.with_context(lang="en_US").mapped("name")))
        if names == tuple(sorted(vals)):
            IDMAP["product.product"][oid] = v.id
            break
log("  variants mapped:", len(IDMAP["product.product"]))
OPTS["product.product"] = {"exclude": ("product_tmpl_id", "product_template_attribute_value_ids", "combination_indices")}
migrate_ids("product.product", sorted(IDMAP["product.product"]))
env.cr.commit()
run_model("product.supplierinfo")
run_model("product.pricelist")
run_model("product.pricelist.item")
run_model("mrp.bom")
run_model("mrp.bom.line")

# ---------------------------------------------------------------- 5. helpdesk / project / hr / planning / crm / sale
run_model("helpdesk.stage")
run_model("helpdesk.team", exclude=("alias_id",))
run_model("helpdesk.tag")
run_model("helpdesk.sla")
run_model("helpdesk.ticket", exclude=("sla_ids", "sla_status_ids"))
run_model("project.tags")
run_model("project.task.type")
run_model("project.project", exclude=("alias_id", "account_id"))
run_model("project.milestone")
run_model("project.task")
run_model("hr.department")
run_model("hr.job")
run_model("hr.employee.category")


def emp_after(pairs):
    for row, nid in pairs:
        if nid and row.get("resource_id"):
            IDMAP["resource.resource"][row["resource_id"]] = env["hr.employee"].browse(nid).resource_id.id


run_model("hr.employee", exclude=("resource_id",), extra_cols=("resource_id",), after_batch=emp_after)
for m in ("hr.skill.type", "hr.skill.level", "hr.skill", "hr.employee.skill", "hr.resume.line.type", "hr.resume.line",
          "planning.role", "planning.slot.template", "planning.slot", "crm.stage", "crm.tag", "crm.lost.reason", "crm.lead",
          "sale.order.template", "sale.order.template.line", "sale.order.template.option", "sale.order", "sale.order.line",
          "purchase.order", "purchase.order.line", "sc.adhoc.sync.run", "calendar.event.type", "calendar.event"):
    run_model(m)
flush_deferred()

# ---------------------------------------------------------------- 6. activities, attachments, chatter, followers
mapped_models = [m for m in IDMAP if IDMAP[m] and m in env]
act_ids = [r["id"] for r in q("SELECT id, res_model, res_id FROM mail_activity") if IDMAP[r["res_model"]].get(r["res_id"])]
run_model("mail.activity", ids=act_ids)

log("== ir.attachment")
STARTED.add("ir.attachment")
n_att = 0
for r in q("""SELECT id, name, res_model, res_field, res_id, store_fname, db_datas, mimetype, description, public, type, url,
                     company_id, create_date, create_uid FROM ir_attachment
               WHERE res_model IS NOT NULL AND res_id IS NOT NULL AND res_id <> 0 ORDER BY id"""):
    nres = IDMAP[r["res_model"]].get(r["res_id"])
    if not nres:
        continue
    if r["res_model"] == "res.company" and r["res_field"]:
        pass
    vals = {"name": r["name"], "res_model": r["res_model"], "res_field": r["res_field"], "res_id": nres,
            "mimetype": r["mimetype"], "description": r["description"], "public": r["public"], "type": r["type"],
            "company_id": IDMAP["res.company"].get(r["company_id"], False)}
    if r["type"] == "url":
        vals["url"] = r["url"]
    else:
        try:
            if r["store_fname"]:
                with open(os.path.join(SRC_FS, r["store_fname"]), "rb") as fh:
                    vals["raw"] = fh.read()
            elif r["db_datas"] is not None:
                vals["raw"] = bytes(r["db_datas"])
        except OSError as exc:
            err("ir.attachment", r["id"], exc)
            continue
    try:
        with env.cr.savepoint():
            if r["res_field"]:
                env["ir.attachment"].sudo().search([("res_model", "=", r["res_model"]), ("res_field", "=", r["res_field"]),
                                                    ("res_id", "=", nres)]).unlink()
            a = env["ir.attachment"].sudo().with_context(**CTX).create(vals)
        IDMAP["ir.attachment"][r["id"]] = a.id
        env.cr.execute("UPDATE ir_attachment SET create_date=%s, create_uid=%s WHERE id=%s",
                       [r["create_date"], IDMAP["res.users"].get(r["create_uid"], 1), a.id])
        n_att += 1
    except Exception as exc:  # noqa: BLE001
        err("ir.attachment", r["id"], exc)
    if n_att % 500 == 0:
        env.cr.commit()
env.cr.commit()
log("  attachments:", n_att)

msg_ids = [r["id"] for r in q("SELECT id, model, res_id FROM mail_message WHERE model IS NOT NULL ORDER BY id")
           if r["model"] in env and IDMAP[r["model"]].get(r["res_id"])]
run_model("mail.message", ids=msg_ids, exclude=("tracking_value_ids", "notification_ids", "reaction_ids"))
fol_ids = [r["id"] for r in q("SELECT id, res_model, res_id FROM mail_followers ORDER BY id")
           if r["res_model"] in env and IDMAP[r["res_model"]].get(r["res_id"])]
run_model("mail.followers", ids=fol_ids)
flush_deferred()

# ---------------------------------------------------------------- 7. parameters, stock, sequences
log("== config parameters")
for r in q("SELECT key, value FROM ir_config_parameter WHERE key LIKE 'sc_adhoc_sync.%%'"):
    env["ir.config_parameter"].sudo().set_str(r["key"], r["value"])

log("== stock quantities")
quants = q("""SELECT q.product_id, q.quantity, l.complete_name loc, q.company_id FROM stock_quant q
                JOIN stock_location l ON l.id = q.location_id WHERE l.usage = 'internal' AND q.quantity <> 0""")
n_q = 0
for r in quants:
    prod = IDMAP["product.product"].get(r["product_id"])
    loc = env["stock.location"].search([("complete_name", "=", r["loc"])], limit=1)
    if not prod or not loc:
        continue
    try:
        with env.cr.savepoint():
            env["stock.quant"].with_context(inventory_mode=True).create(
                {"product_id": prod, "location_id": loc.id, "inventory_quantity": r["quantity"]}).action_apply_inventory()
        n_q += 1
    except Exception as exc:  # noqa: BLE001
        err("stock.quant", r["product_id"], exc)
log("  quants applied:", n_q, "of", len(quants))

log("== sequences")
for r in q("SELECT id, code, company_id, implementation, number_next FROM ir_sequence WHERE code IS NOT NULL"):
    nxt = r["number_next"]
    if r["implementation"] == "standard":
        try:
            row = q(f"SELECT last_value, is_called FROM ir_sequence_{r['id']:03d}")[0]
            nxt = row["last_value"] + (1 if row["is_called"] else 0)
        except Exception:  # noqa: BLE001
            SRC.rollback()
    comp = IDMAP["res.company"].get(r["company_id"], False) if r["company_id"] else False
    for s in env["ir.sequence"].search([("code", "=", r["code"]), ("company_id", "in", [comp, False])]):
        if s.number_next_actual < nxt:
            s.number_next = nxt
env.cr.commit()

log("== re-apply create/write dates")
for (model, nid), meta in META.items():
    env.cr.execute(f'UPDATE "{env[model]._table}" SET {", ".join(f"{chr(34)}{k}{chr(34)} = %s" for k in meta)} WHERE id = %s',
                   [*meta.values(), nid])
env.cr.commit()

# ---------------------------------------------------------------- report
log("== DONE")
for m in sorted(IDMAP):
    if IDMAP[m]:
        log(f"  mapped {m}: {len(IDMAP[m])}")
for m, errs in sorted(ERRORS.items()):
    log(f"  errors {m}: {len(errs)}")
    for oid, text in errs[:3]:
        log(f"     {oid}: {text}")
json.dump({m: {str(k): v for k, v in d.items()} for m, d in IDMAP.items()}, open("/tmp/mig_idmap.json", "w"))
