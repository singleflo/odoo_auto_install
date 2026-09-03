#!/bin/bash
################################################################################
# Script for installing Odoo on Ubuntu  (could be used for other version too)
# Author: Crottolo
# Updated for Odoo 18.0
################################################################################

OE_USER="odoo"
OE_HOME="/$OE_USER"
OE_HOME_EXT="/$OE_USER/${OE_USER}-server"
# The default port where this Odoo instance will run under (provided you use the command -c in the terminal)
# Set to true if you want to install it, false if you don't need it or have it already installed.
INSTALL_WKHTMLTOPDF="True"
# Set the default Odoo port (you still have to use -c /etc/odoo-server.conf for example to use this.)
OE_PORT="8069"
# Choose the Odoo version which you want to install. For example: 18.0, 17.0, 16.0 or 15.0. When using 'master' the master version will be installed.
# IMPORTANT! This script contains extra libraries that are specifically needed for Odoo 18.0
OE_VERSION="18.0"
# Set this to True if you want to install the Odoo enterprise version!
IS_ENTERPRISE="False"
# Installs postgreSQL V16 instead of defaults (e.g V16 for Ubuntu 24.04) - this improves performance
INSTALL_POSTGRESQL="True"
INSTALL_POSTGRESQL_SIXTEEN="True"
# Set this to True if you want to install Nginx!
INSTALL_NGINX="False"
# Set the superadmin password - if GENERATE_RANDOM_PASSWORD is set to "True" we will automatically generate a random password, otherwise we use this one
OE_SUPERADMIN="admin"
# Set to "True" to generate a random password, "False" to use the variable in OE_SUPERADMIN
GENERATE_RANDOM_PASSWORD="True"
OE_CONFIG="${OE_USER}-server"

# Set the default Odoo longpolling port (you still have to use -c /etc/odoo-server.conf for example to use this.)
LONGPOLLING_PORT="8072"
# Set to "True" to install certbot and have ssl enabled, "False" to use http
ENABLE_SSL="False"
# Set the website name if using Nginx
WEBSITE_NAME="example.com"

GIT_USERNAME="crottolo"
GIT_PASSWORD="you-password-of-github"

################################################################################
##
###  WKHTMLTOPDF download links
## === Ubuntu Trusty x64 & x32 === (for other distributions please replace these two links,
## in order to have correct version of wkhtmltopdf installed, for a danger note refer to
## https://github.com/odoo/odoo/wiki/Wkhtmltopdf ):
## https://www.odoo.com/documentation/18.0/administration/install.html

#--------------------------------------------------
# Update Server
#--------------------------------------------------
echo -e "\n---- Update Server ----"
# universe package is for Ubuntu 18.x
#sudo add-apt-repository universe
sudo apt update
sudo apt upgrade -y
sudo apt autoremove -y

# Install software-properties-common for adding repositories
sudo apt install software-properties-common -y

sudo apt update
sudo apt install libpq-dev git curl openssh-server -y

#--------------------------------------------------
# Install PostgreSQL Server
#--------------------------------------------------
echo -e "\n---- Install PostgreSQL Server ----"
if [ "$INSTALL_POSTGRESQL" = "True" ]; then
    if [ $INSTALL_POSTGRESQL_SIXTEEN = "True" ]; then
        echo -e "\n---- Installing postgreSQL V16 due to the user's choice ----"
        sudo curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc|sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/postgresql.gpg
        sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
        sudo apt update
        sudo apt install postgresql-16 -y
    else
        echo -e "\n---- Installing the default postgreSQL version based on Linux version ----"
        sudo apt install postgresql postgresql-server-dev-all -y
    fi
else
    echo -e "\n---- PostgreSQL NOT installed due to the choice of the user! ----"
fi

echo -e "\n---- Starting PostgreSQL service... ----"
sudo systemctl start postgresql
sudo systemctl enable postgresql

echo -e "\n---- Creating the ODOO PostgreSQL User  ----"
sudo su - postgres -c "createuser -s $OE_USER" 2> /dev/null || true

#--------------------------------------------------
# Install Dependencies
#--------------------------------------------------
echo -e "\n---- Installing required packages... ----"
sudo apt install -y git wget python3-minimal python3-dev python3-pip python3-wheel libxml2-dev libxslt1-dev zlib1g-dev libsasl2-dev libldap2-dev build-essential \
libssl-dev libffi-dev libmysqlclient-dev libjpeg-dev libpq-dev libjpeg8-dev liblcms2-dev libblas-dev libatlas-base-dev libzip-dev python3-setuptools node-less \
python3-venv python3-cffi gdebi zlib1g-dev curl cython3 python3-openssl pkg-config libcairo2-dev

# NOTE: Do NOT upgrade system pip on Ubuntu 24.04 (managed by apt, RECORD file missing).
# pip/setuptools/wheel are installed fresh inside the Odoo venv (see below).

# Installing xfonts dependencies for wkhtmltopdf
echo -e "\n---- Installing xfonts for wkhtmltopdf... ----"
sudo apt -y install xfonts-75dpi xfonts-encodings xfonts-utils xfonts-base fontconfig

echo -e "\n---- Installing additional fonts... ----"
# Pre-accept EULA for Microsoft fonts
echo ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true | sudo debconf-set-selections
# Install MS fonts with auto-accepted EULA
sudo apt install ttf-mscorefonts-installer -y
# Download and execute Tahoma font script with automatic yes to prompts
yes | wget -q -O - https://gist.githubusercontent.com/Blastoise/b74e06f739610c4a867cf94b27637a56/raw/96926e732a38d3da860624114990121d71c08ea1/tahoma.sh | bash
# Download and execute MS Tahoma installer script with automatic yes to prompts
yes | wget https://gist.githubusercontent.com/maxwelleite/913b6775e4e408daa904566eb375b090/raw/ttf-ms-tahoma-installer.sh -q -O - | sudo bash

echo -e "\n---- Installing nodeJS NPM and rtlcss for LTR support ----"
sudo apt install nodejs npm -y
sudo ln -s /usr/bin/nodejs /usr/bin/node
sudo npm install -g less less-plugin-clean-css
sudo npm install -g rtlcss

#--------------------------------------------------
# Install Wkhtmltopdf if needed
#--------------------------------------------------
if [ $INSTALL_WKHTMLTOPDF = "True" ]; then
  echo -e "\n---- Install wkhtmltopdf and place shortcuts on correct place for ODOO 18 ----"
  sudo wget https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-2/wkhtmltox_0.12.6.1-2.jammy_amd64.deb
  sudo apt install ./wkhtmltox_0.12.6.1-2.jammy_amd64.deb
  sudo cp /usr/local/bin/wkhtmltoimage /usr/bin/wkhtmltoimage
  sudo cp /usr/local/bin/wkhtmltopdf /usr/bin/wkhtmltopdf
else
  echo "Wkhtmltopdf isn't installed due to the choice of the user!"
fi

echo -e "\n---- Create ODOO system user ----"
sudo adduser --system --quiet --shell=/bin/bash --home=$OE_HOME --gecos 'ODOO' --group $OE_USER
#The user should also be added to the sudo'ers group.
sudo adduser $OE_USER sudo

echo -e "\n---- Create Log directory ----"
sudo mkdir /var/log/$OE_USER
sudo chown $OE_USER:$OE_USER /var/log/$OE_USER

#--------------------------------------------------
# Install ODOO
#--------------------------------------------------
echo -e "\n==== Installing ODOO Server ===="
sudo git clone --depth 1 --branch $OE_VERSION https://www.github.com/odoo/odoo $OE_HOME_EXT/

echo -e "\n---- Create venv  ----"
sudo -u $OE_USER /bin/bash -c "python3 -m venv $OE_HOME/odoo-venv"
echo -e "\n---- Activate venv ----"
source $OE_HOME/odoo-venv/bin/activate
echo -e "\n---- Install python packages/requirements ----"
sudo -u $OE_USER /bin/bash -c "source $OE_HOME/odoo-venv/bin/activate && pip3 install -r $OE_HOME_EXT/requirements.txt"
sudo -u $OE_USER /bin/bash -c "source $OE_HOME/odoo-venv/bin/activate && pip3 install python-codicefiscale phonenumbers paramiko pdfminer.six fillpdf pdfplumber rlPyCairo evolutionapi"

# --- Object storage S3 (installato di default; l'ATTIVAZIONE e' solo configurazione:
# sezione [fs_storage.<code>] nel conf via server_environment, credenziali OVH, Autovacuum GC.
# Versioni pinnate: aiobotocore impone botocore<1.43.57 -> boto3/botocore allineati. ---
sudo -u $OE_USER /bin/bash -c "source $OE_HOME/odoo-venv/bin/activate && pip3 install packaging==24.2 'fsspec[s3]>=2025.3.0' fsspec==2026.7.0 s3fs==2026.7.0 aiobotocore==3.9.0 boto3==1.43.56 botocore==1.43.56 python-slugify==8.0.4"
echo -e "\n---- Deactivate venv ----"
deactivate

if [ $IS_ENTERPRISE = "True" ]; then
    # Odoo Enterprise install!
    sudo -u $OE_USER /bin/bash -c "source $OE_HOME/odoo-venv/bin/activate && pip3 install psycopg2-binary pdfminer.six fillpdf"
    echo -e "\n--- Create symlink for node"
    sudo ln -s /usr/bin/nodejs /usr/bin/node
    sudo su $OE_USER -c "mkdir $OE_HOME/enterprise"
    sudo su $OE_USER -c "mkdir $OE_HOME/enterprise/addons"

    GITHUB_RESPONSE=$(sudo git clone --depth 1 --branch $OE_VERSION https://$GIT_USERNAME:$GIT_PASSWORD@github.com/odoo/enterprise "$OE_HOME/enterprise/addons" 2>&1)
    while [[ $GITHUB_RESPONSE == *"Authentication"* ]]; do
        echo "------------------------WARNING------------------------------"
        echo "Your authentication with Github has failed! Please try again."
        printf "In order to clone and install the Odoo enterprise version you \nneed to be an offical Odoo partner and you need access to\nhttp://github.com/odoo/enterprise.\n"
        echo "TIP: Press ctrl+c to stop this script."
        echo "-------------------------------------------------------------"
        echo " "
        GITHUB_RESPONSE=$(sudo git clone --depth 1 --branch $OE_VERSION https://$GIT_USERNAME:$GIT_PASSWORD@github.com/odoo/enterprise "$OE_HOME/enterprise/addons" 2>&1)
    done

    echo -e "\n---- Added Enterprise code under $OE_HOME/enterprise/addons ----"
    echo -e "\n---- Installing Enterprise specific libraries ----"
    sudo -u $OE_USER /bin/bash -c "source $OE_HOME/odoo-venv/bin/activate && pip3 install num2words ofxparse dbfread ebaysdk firebase_admin pyOpenSSL"
    deactivate
    sudo npm install -g less
    sudo npm install -g less-plugin-clean-css
fi

echo -e "\n---- Create custom module directory ----"
sudo su $OE_USER -c "mkdir $OE_HOME/custom"
sudo su $OE_USER -c "mkdir $OE_HOME/custom/addons"

echo -e "\n---- Setting permissions on home folder ----"
sudo chown -R $OE_USER:$OE_USER $OE_HOME/*

# ============================================================================
# REPOSITORY CONFIGURATION
# ============================================================================
# Formato: "nome_locale|url_repo"
# Per aggiungere una repo basta inserire UNA riga qui sotto: il loop sotto
# si occupa sia del clone in $OE_HOME/custom/<nome> sia dell'inserimento
# automatico nell'addons_path del conf file.
# ----------------------------------------------------------------------------
REPOS=(
  # --- Public OCA + community ---
  "free_addons_odoo|https://github.com/singleflo/free_addons_odoo"
  "design-themes|https://github.com/odoo/design-themes"
  "web|https://github.com/OCA/web"
  "social|https://github.com/OCA/social"
  "website|https://github.com/OCA/website"
  "partner-contact|https://github.com/OCA/partner-contact"
  "mail|https://github.com/OCA/mail"
  # --- Object storage S3 (installato di default; si ATTIVA solo via conf [fs_storage] ---
  "storage-backend|https://github.com/OCA/storage-backend"
  "server-env|https://github.com/OCA/server-env"
  # --- Singleflo platform baseline (PRIVATE: richiede GIT_USERNAME:GIT_PASSWORD) ---
  "commons_odoo|https://${GIT_USERNAME}:${GIT_PASSWORD}@github.com/singleflo/commons_odoo"
  "web_widgets_odoo|https://${GIT_USERNAME}:${GIT_PASSWORD}@github.com/singleflo/web_widgets_odoo"
  "crm_odoo|https://${GIT_USERNAME}:${GIT_PASSWORD}@github.com/singleflo/crm_odoo"
  "finance_odoo|https://${GIT_USERNAME}:${GIT_PASSWORD}@github.com/singleflo/finance_odoo"
)

# Costruisci sub_dirs con le path base + clona ogni repo + accoda la sua path
sub_dirs=(
  "${OE_HOME_EXT}/addons"
  "${OE_HOME}/custom/addons"
)
if [ "$IS_ENTERPRISE" = "True" ]; then
  sub_dirs+=("${OE_HOME}/enterprise/addons")
fi

for entry in "${REPOS[@]}"; do
  name="${entry%%|*}"
  url="${entry#*|}"
  sudo git clone --depth 1 --branch "$OE_VERSION" "$url" "$OE_HOME/custom/$name"
  sub_dirs+=("${OE_HOME}/custom/${name}")
done

# Costruisci la stringa addons_path da sub_dirs (single source of truth)
addons_path="addons_path=${sub_dirs[0]}"
for dir in "${sub_dirs[@]:1}"; do
  addons_path+=",\n\t${dir}"
done

echo -e "* Create server config file"
sudo touch /etc/${OE_CONFIG}.conf
echo -e "* Creating server config file"

# Generate admin password
if [ $GENERATE_RANDOM_PASSWORD = "True" ]; then
    echo -e "* Generating random admin password"
    OE_SUPERADMIN=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 20 | head -n 1)
fi

sudo cat <<EOF > /etc/${OE_CONFIG}.conf
[options]
admin_passwd = ${OE_SUPERADMIN}
db_host = False
db_port = False
db_user = $OE_USER
db_password = False
http_port = ${OE_PORT}
logfile = /var/log/${OE_USER}/${OE_CONFIG}.log
gevent_port = ${LONGPOLLING_PORT}
xmlrpcs_interfaces = 0.0.0.0
workers = 2
max_cron_threads = 1
proxy_mode = True
logrotate = True
list_db = True
EOF

# Ora scrivi addons_path nel file di configurazione
sudo su root -c "echo -e '$addons_path' >> /etc/${OE_CONFIG}.conf"

sudo chown $OE_USER:$OE_USER /etc/${OE_CONFIG}.conf
sudo chmod 640 /etc/${OE_CONFIG}.conf

echo -e "* Create startup file"
sudo su root -c "echo '#!/bin/sh' >> $OE_HOME_EXT/start.sh"
sudo su root -c "echo \"source '$OE_HOME/odoo-venv/bin/activate'\" >> $OE_HOME_EXT/start.sh"
sudo su root -c "echo 'sudo -u $OE_USER $OE_HOME/odoo-venv/bin/python3 $OE_HOME_EXT/odoo-bin --config=/etc/${OE_CONFIG}.conf' >> $OE_HOME_EXT/start.sh"
sudo chmod 755 $OE_HOME_EXT/start.sh

#--------------------------------------------------
# Creating systemd service file for Odoo
#--------------------------------------------------
echo "=== Creating systemd service file... ==="
sudo cat <<EOF > /lib/systemd/system/$OE_USER.service
[Unit]
Description=Odoo Open Source ERP and CRM
After=network.target

[Service]
Type=simple
User=$OE_USER
Group=$OE_USER
ExecStart=$OE_HOME/odoo-venv/bin/python3 $OE_HOME_EXT/odoo-bin --config /etc/${OE_CONFIG}.conf --logfile /var/log/${OE_USER}/${OE_CONFIG}.log
KillMode=mixed

[Install]
WantedBy=multi-user.target
EOF

sudo chmod 755 /lib/systemd/system/$OE_USER.service
sudo chown root: /lib/systemd/system/$OE_USER.service

# Reload systemd and start Odoo service
echo "=== Reloading systemd daemon ... ==="
sudo systemctl daemon-reload
sudo systemctl enable --now $OE_USER.service

#--------------------------------------------------
# Install Nginx if needed
#--------------------------------------------------
if [ $INSTALL_NGINX = "True" ]; then
  echo "==== Installing nginx ... ===="
  sudo apt install -y nginx
  sudo systemctl enable nginx

  echo "==== Configuring nginx ... ===="
  cat <<EOF > /etc/nginx/sites-available/$OE_USER
# odoo server
upstream $OE_USER {
  server 127.0.0.1:$OE_PORT;
}

upstream ${OE_USER}chat {
  server 127.0.0.1:$LONGPOLLING_PORT;
}

server {
   listen 80;
   server_name $WEBSITE_NAME;

   # Specifies the maximum accepted body size of a client request,
   # as indicated by the request header Content-Length.
   client_max_body_size 500M;

   # log
   access_log /var/log/nginx/$OE_USER-access.log;
   error_log /var/log/nginx/$OE_USER-error.log;

   # add ssl specific settings
   keepalive_timeout 90;

   # increase proxy buffer to handle some Odoo web requests
   proxy_buffers 16 64k;
   proxy_buffer_size 128k;

   proxy_read_timeout 720s;
   proxy_connect_timeout 720s;
   proxy_send_timeout 720s;

   # Add Headers for odoo proxy mode
   proxy_set_header Host \$host;
   proxy_set_header X-Forwarded-Host \$host;
   proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
   proxy_set_header X-Forwarded-Proto \$scheme;
   proxy_set_header X-Real-IP \$remote_addr;

   # Redirect requests to odoo backend server
   location / {
     proxy_redirect off;
     proxy_pass http://$OE_USER;
   }

   # Redirect longpoll requests to odoo longpolling port
   location /longpolling {
       proxy_pass http://${OE_USER}chat;
   }

   # cache some static data in memory for 90mins
   # under heavy load this should relieve stress on the Odoo web interface a bit.
   location ~* /web/static/ {
       proxy_cache_valid 200 90m;
       proxy_buffering on;
       expires 864000;
       proxy_pass http://$OE_USER;
  }

  # common gzip
  gzip_types text/css text/less text/plain text/xml application/xml application/json application/javascript;
  gzip on;
}
EOF

  sudo mv /etc/nginx/sites-available/$OE_USER /etc/nginx/sites-available/$OE_USER
  sudo ln -s /etc/nginx/sites-available/$OE_USER /etc/nginx/sites-enabled/$OE_USER
  sudo rm /etc/nginx/sites-enabled/default
  sudo rm /etc/nginx/sites-available/default

  sudo systemctl reload nginx
  echo "Done! The Nginx server is up and running. Configuration can be found at /etc/nginx/sites-available/$OE_USER"

  #--------------------------------------------------
  # Enable ssl with certbot
  #--------------------------------------------------
  if [ $ENABLE_SSL = "True" ] && [ $WEBSITE_NAME != "example.com" ]; then
    echo "==== Installing certbot certificate ... ===="
    sudo apt-get remove certbot
    sudo snap install core
    sudo snap refresh core
    sudo snap install --classic certbot
    sudo ln -s /snap/bin/certbot /usr/bin/certbot
    sudo certbot --nginx -d $WEBSITE_NAME
    sudo systemctl reload nginx
    echo "============ SSL/HTTPS is enabled! ==========="
  else
    echo "==== SSL/HTTPS isn't enabled due to choice of the user or because of a misconfiguration! ======"
  fi
else
  echo "===== Nginx isn't installed due to choice of the user! ========"
fi

#--------------------------------------------------
# UFW Firewall
#--------------------------------------------------
echo "=== Installation of UFW firewall ... ==="
sudo apt install -y ufw

if [ $INSTALL_NGINX = "True" ]; then
  sudo ufw allow 'Nginx Full'
  sudo ufw allow 'Nginx HTTP'
  sudo ufw allow 'Nginx HTTPS'
fi

sudo ufw allow 22/tcp
sudo ufw allow $OE_PORT/tcp
sudo ufw allow $LONGPOLLING_PORT/tcp
sudo ufw enable

echo -e "* Starting Odoo Service"
sudo systemctl start $OE_USER.service
echo "-----------------------------------------------------------"
echo "Done! The Odoo server is up and running. Specifications:"
echo "Port: $OE_PORT"
echo "User service: $OE_USER"
echo "Configuraton file location: /etc/${OE_CONFIG}.conf"
echo "Logfile location: /var/log/$OE_USER"
echo "User PostgreSQL: $OE_USER"
echo "Code location: $OE_USER"
echo "Addons folder: $OE_USER/$OE_CONFIG/addons/"
echo "Password superadmin (database): $OE_SUPERADMIN"
echo "Start Odoo service: sudo systemctl start $OE_USER.service"
echo "Stop Odoo service: sudo systemctl stop $OE_USER.service"
echo "Restart Odoo service: sudo systemctl restart $OE_USER.service"
echo "-----------------------------------------------------------"
