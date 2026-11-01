# Migrazione dati Odoo 18 -> 20 (senza upgrade.odoo.com)

`mig18to20.py` copia i dati reali (non demo) da un DB Odoo 18 a un DB Odoo 20 nuovo, sullo stesso server PostgreSQL.

```bash
sudo -u odoo /odoo/v20/odoo-venv/bin/python3 /odoo/v20/odoo-server/odoo-bin shell \
    -c /etc/odoo-server-20.conf -d <db20> --no-http < migration/mig18to20.py
```

- Sorgente: DB `devsc` (costante `SRC` in testa allo script), filestore in `SRC_FS`.
- Log in `/tmp/mig.log`, mappa id vecchi -> nuovi in `/tmp/mig_idmap.json`.
- Fare uno snapshot del DB 20 prima (`createdb -T <db20> <db20>_clean`) per poter ripetere.
