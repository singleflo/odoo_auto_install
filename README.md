# odoo_auto_install - Script di Installazione Automatica per Odoo

## Compatibilità
✅ **Ubuntu 24.04 LTS** - Completamente supportato e ottimizzato 
✅ **Odoo 18.0** - Configurazione completa con tutte le dipendenze necessarie
✅ **PostgreSQL 16** - Installazione e configurazione ottimizzata per prestazioni migliori

Installazione di Odoo 18.0 con ambiente virtuale su Ubuntu 24.04

## Caratteristiche e Vantaggi

1. Ambiente virtuale Python
2. Odoo 18.0
3. PostgreSQL 16
4. Possibilità di installare più istanze di Odoo sullo stesso server
5. File di configurazione preimpostato
6. Supporto per Nginx e SSL con Certbot
7. Configurazione del firewall UFW

Configurazione semplice per installare Odoo 18.0 con ambiente virtuale su Ubuntu 24.04

Impostazioni principali:

```sh
################################################################################

OE_USER="odoo"
OE_HOME="/$OE_USER"
OE_HOME_EXT="/$OE_USER/${OE_USER}-server"
# Porta predefinita su cui questa istanza di Odoo verrà eseguita
INSTALL_WKHTMLTOPDF="True"
OE_PORT="8069"
# Versione di Odoo da installare
OE_VERSION="18.0"
# Impostare su True per installare la versione enterprise di Odoo
IS_ENTERPRISE="False"
# Installa PostgreSQL V16 invece della versione predefinita
INSTALL_POSTGRESQL="True"
INSTALL_POSTGRESQL_SIXTEEN="True"
# Impostare su True per installare Nginx
INSTALL_NGINX="False"
# Password superadmin - se GENERATE_RANDOM_PASSWORD è impostato su "True" verrà generata automaticamente
OE_SUPERADMIN="admin"
GENERATE_RANDOM_PASSWORD="True"
OE_CONFIG="${OE_USER}-server"
# Porta longpolling predefinita
LONGPOLLING_PORT="8072"
# Impostare su "True" per installare certbot e abilitare SSL
ENABLE_SSL="False"
# Nome del sito web se si utilizza Nginx
WEBSITE_NAME="example.com"

GIT_USERNAME="crottolo"
GIT_PASSWORD="your-password-of-github"
################################################################################
```

### Configurazione dei repository

È possibile configurare repository GitHub pubblici e privati:

```sh
## Configurazione di più repository GitHub

### Repository pubblici e privati

##### GIT_USERNAME è il tuo nome utente GitHub per repository privati
##### GIT_PASSWORD è la tua password GitHub per repository privati

# Esempio di clonazione di un repository privato
sudo git clone --depth 1 --branch 18.0 https://GIT_USERNAME:GIT_PASSWORD@github.com/crottolo/od_custom_app $OE_HOME/custom/od_custom_app

# Percorsi degli addons configurati nello script
sub_dirs=(
  "${OE_HOME}/custom/addons"
  "${OE_HOME_EXT}/addons"
  "${OE_HOME}/custom/free_addons"
  "${OE_HOME}/custom/design-themes"
  "${OE_HOME}/custom/web"
  "${OE_HOME}/custom/social"
  "${OE_HOME}/custom/website"
  "${OE_HOME}/custom/od_custom_app"
  "${OE_HOME}/custom/partner-contact"
)
```

---

## Installazione

### 1. Requisiti

- Ubuntu 24.04
- 2vCPU e 1GB RAM (minimo)
- 8GB di spazio su disco

Questo script funzionerà su Ubuntu 24.04, utilizza PostgreSQL come database, quindi è consigliabile eseguirlo su un server con almeno 1GB di memoria. Non è necessaria la swap. Installerà Odoo 18.0 con ambiente virtuale nella directory home dell'utente di sistema specificato.

### 2. Ottenere lo script e renderlo eseguibile

```sh
# È richiesto l'utente root

wget https://raw.githubusercontent.com/crottolo/odoo_auto_install/main/install_odoo_ent.sh
chmod +x install_odoo_ent.sh
./install_odoo_ent.sh
```

Al termine dell'installazione, vedrai il seguente messaggio:

```sh
-----------------------------------------------------------
Done! The Odoo server is up and running. Specifications:
Port: 8069
User service: odoo
Configuraton file location: /etc/odoo-server.conf
Logfile location: /var/log/odoo
User PostgreSQL: odoo
Code location: /odoo
Addons folder: odoo/odoo-server/addons/
Password superadmin (database): dwer324fsdgdfgdg
Start Odoo service: sudo systemctl start odoo.service
Stop Odoo service: sudo systemctl stop odoo.service
Restart Odoo service: sudo systemctl restart odoo.service
-----------------------------------------------------------
```

Durante il processo viene creato un utente con privilegi sudo, ad esempio odoo, e la configurazione è separata dall'utente root.

### 3. Ambiente virtuale Python

Per visualizzare l'elenco dei pacchetti installati nell'ambiente virtuale:

```sh
sudo su - odoo
source /odoo/odoo-venv/bin/activate
pip list

# Per installare un nuovo pacchetto
pip install "nome-pacchetto-da-installare"

deactivate
```

#### Esempio

```sh
root@odoo_server:~# sudo su odoo
odoo@odoo_server:/root$ cd
odoo@odoo_server:~$ ls
custom  odoo-server  odoo-venv
odoo@odoo_server:~$ source odoo-venv/bin/activate
(odoo-venv) odoo@odoo_server:~$ pip install pandas
Collecting pandas
  Downloading pandas-2.1.1-cp310-cp310-manylinux_2_17_x86_64.manylinux2014_x86_64.whl (12.3 MB)
     ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ 12.3/12.3 MB 47.6 MB/s eta 0:00:00
Requirement already satisfied: pytz>=2020.1 in ./odoo-venv/lib/python3.10/site-packages (from pandas) (2023.3.post1)
Collecting tzdata>=2022.1
  Downloading tzdata-2023.3-py2.py3-none-any.whl (341 kB)
     ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ 341.8/341.8 KB 125.2 MB/s eta 0:00:00
Collecting numpy>=1.22.4
  Downloading numpy-1.26.0-cp310-cp310-manylinux_2_17_x86_64.manylinux2014_x86_64.whl (18.2 MB)
     ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ 18.2/18.2 MB 54.6 MB/s eta 0:00:00
Collecting python-dateutil>=2.8.2
  Downloading python_dateutil-2.8.2-py2.py3-none-any.whl (247 kB)
     ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ 247.7/247.7 KB 109.6 MB/s eta 0:00:00
Requirement already satisfied: six>=1.5 in ./odoo-venv/lib/python3.10/site-packages (from python-dateutil>=2.8.2->pandas) (1.16.0)
Installing collected packages: tzdata, python-dateutil, numpy, pandas
  Attempting uninstall: python-dateutil
    Found existing installation: python-dateutil 2.8.1
    Uninstalling python-dateutil-2.8.1:
      Successfully uninstalled python-dateutil-2.8.1
Successfully installed numpy-1.26.0 pandas-2.1.1 python-dateutil-2.8.2 tzdata-2023.3
(odoo-venv) odoo@odoo_server:~$ deactivate 
odoo@odoo_server:~$ 
```

È importante attivare l'ambiente virtuale prima di installare i pacchetti e poi disattivarlo.
Puoi vedere la conferma dell'attivazione dell'ambiente virtuale nel prompt:
***(odoo-venv) odoo@odoo_server:*** pip install pandas
e la disattivazione nel prompt:
***(odoo@odoo_server:~$)***

Dopo l'installazione del pacchetto, puoi disattivare l'ambiente virtuale:

```sh
(odoo-venv) odoo@odoo_server:~$ deactivate
odoo@odoo_server:~$ 
```

### 4. Verificare l'indirizzo IP del server

```sh
curl ifconfig.me
```

### 5. Creare un database all'indirizzo IP del server

```sh
http://indirizzo-ip:8069/web/database/manager
```

### 6. Configurazione Nginx

Lo script supporta l'installazione e la configurazione automatica di Nginx. Se hai impostato `INSTALL_NGINX="True"`, il server web Nginx verrà installato e configurato per funzionare con Odoo.

Se hai anche impostato `ENABLE_SSL="True"` e fornito un nome di dominio valido in `WEBSITE_NAME`, verrà installato Certbot per configurare automaticamente SSL/HTTPS.

#### Configurazione manuale di Nginx Proxy Manager

Se preferisci utilizzare Nginx Proxy Manager su un server separato, ecco alcune configurazioni consigliate:

***Forward hostname / ip:*** indirizzo IP del server interno

***Forward port:*** 8069

***Websockets Support:*** true

#### Configurazione per Odoo 18.0

***Custom locations: "/"***

```sh
proxy_read_timeout 720s;
proxy_connect_timeout 720s;
proxy_send_timeout 720s;
# Add Headers for odoo proxy mode
proxy_set_header X-Forwarded-Host $host;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto $scheme;
proxy_set_header X-Real-IP $remote_addr;
proxy_redirect off;
```

***Custom locations: "/websocket"***

```sh
proxy_read_timeout 720s;
proxy_connect_timeout 720s;
proxy_send_timeout 720s;
# Add Headers for odoo proxy mode
proxy_set_header X-Forwarded-Host $host;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto $scheme;
proxy_set_header X-Real-IP $remote_addr;
```

***Advanced: "Custom nginx configuration"***

```sh
# common gzip
gzip_types text/css text/less text/plain text/xml application/xml application/json application/javascript;
gzip on;
client_body_in_file_only clean;
client_body_buffer_size 32K;
client_max_body_size 500M;
sendfile on;
send_timeout 600s;
keepalive_timeout 300;
```

### 7. Installazione di font aggiuntivi

Per migliorare la generazione di PDF con wkhtmltopdf, puoi installare font aggiuntivi:

```sh
apt install ttf-mscorefonts-installer
wget -q -O - https://gist.githubusercontent.com/Blastoise/b74e06f739610c4a867cf94b27637a56/raw/96926e732a38d3da860624114990121d71c08ea1/tahoma.sh | bash
wget https://gist.githubusercontent.com/maxwelleite/913b6775e4e408daa904566eb375b090/raw/ttf-ms-tahoma-installer.sh -q -O - | sudo bash
```

### 8. Novità nella versione 18.0

La versione aggiornata dello script per Odoo 18.0 include diverse migliorie:

1. **Supporto per Ubuntu 24.04** - Ottimizzato per l'ultima versione LTS di Ubuntu
2. **PostgreSQL 16** - Supporto per la versione più recente di PostgreSQL
3. **Systemd invece di init.d** - Utilizzo del sistema moderno di gestione dei servizi
4. **Configurazione UFW** - Configurazione automatica del firewall
5. **Semplificazione delle dipendenze** - Non è più necessario forzare versioni specifiche di pyopenssl e cryptography
6. **Miglioramenti alla configurazione** - File di configurazione più completo e ottimizzato

### 9. Conclusione

Hai installato con successo Odoo 18.0 con un ambiente virtuale Python su Ubuntu 24.04. Questa configurazione ti permette di eseguire più istanze sullo stesso server e offre una configurazione pronta all'uso per una rapida implementazione.

Se hai trovato utile questo script, considera di dargli un "like" sul suo repository GitHub. Per altri contenuti come questo, iscriviti e metti "mi piace" al canale YouTube CrottoCode.

- **Repository GitHub**: [odoo_auto_install](https://github.com/crottolo/odoo_auto_install)
- **Canale YouTube**: [CrottoCode](https://youtube.com/@CrottoCode?si=JQqVblSkvNBBdC5S)

Il tuo supporto aiuta a creare altri contenuti utili. Grazie!
