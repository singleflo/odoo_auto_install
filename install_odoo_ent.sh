#!/bin/bash
################################################################################
# Script for installing Odoo on Ubuntu 16.04, 18.04, 20.04 and 22.04 (could be used for other version too)
# Author: Yenthe Van Ginneken
#-------------------------------------------------------------------------------
# This script will install Odoo on your Ubuntu server. It can install multiple Odoo instances
# in one Ubuntu because of the different xmlrpc_ports
#-------------------------------------------------------------------------------
# Make a new file:
# sudo nano odoo-install.sh
# Place this content in it and then make the file executable:
# sudo chmod +x odoo-install.sh
# Execute the script to install Odoo:
# ./odoo-install
################################################################################

OE_USER="odoo"
OE_HOME="/$OE_USER"
OE_HOME_EXT="/$OE_USER/${OE_USER}-server"
# The default port where this Odoo instance will run under (provided you use the command -c in the terminal)
# Set to true if you want to install it, false if you don't need it or have it already installed.
INSTALL_WKHTMLTOPDF="True"
# Set the default Odoo port (you still have to use -c /etc/odoo-server.conf for example to use this.)
OE_PORT="8069"
# Choose the Odoo version which you want to install. For example: 16.0, 15.0, 14.0 or saas-22. When using 'master' the master version will be installed.
# IMPORTANT! This script contains extra libraries that are specifically needed for Odoo 16.0
OE_VERSION="16.0"
# Set this to True if you want to install the Odoo enterprise version!
IS_ENTERPRISE="False"
# Installs postgreSQL V14 instead of defaults (e.g V12 for Ubuntu 20/22) - this improves performance
INSTALL_POSTGRESQL="True"
INSTALL_POSTGRESQL_FIFTEEN="True"
# Set this to True if you want to install Nginx!
# Set the superadmin password - if GENERATE_RANDOM_PASSWORD is set to "True" we will automatically generate a random password, otherwise we use this one
OE_SUPERADMIN="admin"
# Set to "True" to generate a random password, "False" to use the variable in OE_SUPERADMIN
GENERATE_RANDOM_PASSWORD="True"
OE_CONFIG="${OE_USER}-server"

# Set the default Odoo longpolling port (you still have to use -c /etc/odoo-server.conf for example to use this.)
LONGPOLLING_PORT="8072"
# Set to "True" to install certbot and have ssl enabled, "False" to use http

GIT_USERNAME="crottolo"
GIT_PASSWORD="you-password-of-github"

################################################################################
##
###  WKHTMLTOPDF download links
## === Ubuntu Trusty x64 & x32 === (for other distributions please replace these two links,
## in order to have correct version of wkhtmltopdf installed, for a danger note refer to
## https://github.com/odoo/odoo/wiki/Wkhtmltopdf ):
## https://www.odoo.com/documentation/16.0/administration/install.html

# Check if the operating system is Ubuntu 22.04
if [[ $(lsb_release -r -s) == "22.04" ]]; then
    WKHTMLTOX_X64="https://packages.ubuntu.com/jammy/wkhtmltopdf"
    WKHTMLTOX_X32="https://packages.ubuntu.com/jammy/wkhtmltopdf"
    #No Same link works for both 64 and 32-bit on Ubuntu 22.04
else
    # For older versions of Ubuntu
    WKHTMLTOX_X64="https://github.com/wkhtmltopdf/wkhtmltopdf/releases/download/0.12.5/wkhtmltox_0.12.5-1.$(lsb_release -c -s)_amd64.deb"
    WKHTMLTOX_X32="https://github.com/wkhtmltopdf/wkhtmltopdf/releases/download/0.12.5/wkhtmltox_0.12.5-1.$(lsb_release -c -s)_i386.deb"
fi

#--------------------------------------------------
# Update Server
#--------------------------------------------------
echo -e "\n---- Update Server ----"
# universe package is for Ubuntu 18.x
#sudo add-apt-repository universe
# libpng12-0 dependency for wkhtmltopdf for older Ubuntu versions
sudo apt-get update
sudo apt install software-properties-common -y
sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 3B4FE6ACC0B21F32
sudo add-apt-repository "deb http://mirrors.kernel.org/ubuntu/ xenial main" -y
sudo apt-get update
sudo apt-get upgrade -y
sudo apt-get install libpq-dev git curl -y

#--------------------------------------------------
# Install PostgreSQL Server
#--------------------------------------------------
echo -e "\n---- Install PostgreSQL Server ----"
if [ "$INSTALL_POSTGRESQL" = "True" ]; then
    if [ $INSTALL_POSTGRESQL_FIFTEEN = "True" ]; then
        echo -e "\n---- Installing postgreSQL V15 due to the user it's choise ----"
        sudo curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc|sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/postgresql.gpg
        sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
        sudo apt-get update
        sudo apt-get install postgresql-15 -y
    else
        echo -e "\n---- Installing the default postgreSQL version based on Linux version ----"
        sudo apt-get install postgresql postgresql-server-dev-all -y
    fi
else
    echo -e "\n---- PostgreSQL NOT installed due to the choice of the user! ----"
fi


echo -e "\n---- Creating the ODOO PostgreSQL User  ----"
sudo su - postgres -c "createuser -s $OE_USER" 2> /dev/null || true

#--------------------------------------------------
# Install Dependencies
#--------------------------------------------------
echo -e "\n--- Installing Python 3.11 + pip3 --"
# Add deadsnakes PPA to get Python 3.11
sudo add-apt-repository ppa:deadsnakes/ppa -y
sudo apt-get update
sudo apt-get install python3.11 python3.11-dev python3.11-venv -y

# Create symbolic link to make python3.11 the default python3
sudo update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 1

# Install pip for Python 3.11
curl -sS https://bootstrap.pypa.io/get-pip.py | sudo python3.11

# Install other dependencies
sudo apt-get install git build-essential wget libxslt-dev libzip-dev libldap2-dev libsasl2-dev node-less libpng-dev libjpeg-dev gdebi -y

# echo -e "\n---- Install python packages/requirements ----"
# sudo -H pip3 install -r https://github.com/odoo/odoo/raw/${OE_VERSION}/requirements.txt

echo -e "\n---- Installing nodeJS NPM and rtlcss for LTR support ----"
sudo apt-get install nodejs npm -y
sudo npm install -g rtlcss

#--------------------------------------------------
# Install Wkhtmltopdf if needed
#--------------------------------------------------
if [ $INSTALL_WKHTMLTOPDF = "True" ]; then
  echo -e "\n---- Install wkhtml and place shortcuts on correct place for ODOO 13 ----"
  wget https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-3/wkhtmltox_0.12.6.1-3.jammy_amd64.deb
  dpkg -i wkhtmltox_0.12.6.1-3.jammy_amd64.deb
  apt-get install -f -y
  ln -s /usr/local/bin/wkhtmltopdf /usr/bin
  ln -s /usr/local/bin/wkhtmltoimage /usr/bin
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
sudo -u $OE_USER /bin/bash -c "source $OE_HOME/odoo-venv/bin/activate && pip3 install python-codicefiscale phonenumbers"
echo -e "\n---- Deactivate venv ----"
deactivate

# sudo -H pip3 install -r $OE_HOME_EXT/requirements.txt


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
    sudo -u $OE_USER /bin/bash -c "source $OE_HOME/odoo-venv/bin/activate && pip3 install paramiko"
    sudo -u $OE_USER /bin/bash -c "source $OE_HOME/odoo-venv/bin/activate && pip3  uninstall -y pyopenssl"
    sudo -u $OE_USER /bin/bash -c "source $OE_HOME/odoo-venv/bin/activate && pip3 install pyopenssl==22.0.0"
    sudo -u $OE_USER /bin/bash -c "source $OE_HOME/odoo-venv/bin/activate && pip3  uninstall -y cryptography"
    sudo -u $OE_USER /bin/bash -c "source $OE_HOME/odoo-venv/bin/activate && pip3 install cryptography==37.0.0"
    deactivate
    sudo npm install -g less
    sudo npm install -g less-plugin-clean-css
fi

echo -e "\n---- Create custom module directory ----"
sudo su $OE_USER -c "mkdir $OE_HOME/custom"
sudo su $OE_USER -c "mkdir $OE_HOME/custom/addons"


echo -e "\n---- Setting permissions on home folder ----"
sudo chown -R $OE_USER:$OE_USER $OE_HOME/*
sudo git clone --depth 1 --branch $OE_VERSION https://github.com/crottolo/free_addons $OE_HOME/custom/free_addons
sudo git clone --depth 1 --branch $OE_VERSION https://github.com/odoo/design-themes $OE_HOME/custom/design-themes
sudo git clone --depth 1 --branch $OE_VERSION https://github.com/OCA/web $OE_HOME/custom/web
sudo git clone --depth 1 --branch $OE_VERSION https://github.com/OCA/social $OE_HOME/custom/social
sudo git clone --depth 1 --branch $OE_VERSION https://github.com/OCA/website $OE_HOME/custom/website
sudo git clone --depth 1 --branch $OE_VERSION https://$GIT_USERNAME:$GIT_PASSWORD@github.com/crottolo/od_custom_app $OE_HOME/custom/od_custom_app
sudo git clone --depth 1 --branch $OE_VERSION https://github.com/OCA/partner-contact $OE_HOME/custom/partner-contact


# Definisci un array con tutte le sottodirectory che vuoi aggiungere
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

# Inizia a costruire la stringa con la directory che deve sempre essere inclusa
addons_path="addons_path=${OE_HOME_EXT}/addons,"

# Se IS_ENTERPRISE è True, aggiungi la directory enterprise
if [ "$IS_ENTERPRISE" = "True" ]; then
  addons_path+="\n\t${OE_HOME}/enterprise/addons,"
fi

# Aggiungi ogni sottodirectory all'addons_path
for dir in "${sub_dirs[@]}"; do
  addons_path+="\n\t${dir},"
done

# Rimuovi l'ultima virgola
addons_path=${addons_path%,}

echo -e "* Create server config file"


sudo touch /etc/${OE_CONFIG}.conf
echo -e "* Creating server config file"
sudo su root -c "printf '[options] \n; This is the password that allows database operations:\n' >> /etc/${OE_CONFIG}.conf"
if [ $GENERATE_RANDOM_PASSWORD = "True" ]; then
    echo -e "* Generating random admin password"
    OE_SUPERADMIN=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)
fi
sudo su root -c "printf 'admin_passwd = ${OE_SUPERADMIN}\n' >> /etc/${OE_CONFIG}.conf"
if [ $OE_VERSION > "11.0" ];then
    sudo su root -c "printf 'http_port = ${OE_PORT}\n' >> /etc/${OE_CONFIG}.conf"
    sudo su root -c "printf 'longpolling_port = False\n' >> /etc/${OE_CONFIG}.conf"
    sudo su root -c "printf 'gevent_port = ${LONGPOLLING_PORT}\n' >> /etc/${OE_CONFIG}.conf"
    sudo su root -c "printf 'xmlrpcs_interfaces = 0.0.0.0\n' >> /etc/${OE_CONFIG}.conf"
    sudo su root -c "printf 'workers = 2\n' >> /etc/${OE_CONFIG}.conf"
    sudo su root -c "printf 'max_cron_threads = 1\n' >> /etc/${OE_CONFIG}.conf"
    sudo su root -c "printf 'proxy_mode = True\n' >> /etc/${OE_CONFIG}.conf"
    sudo su root -c "printf 'logrotate = True\n' >> /etc/${OE_CONFIG}.conf"

else
    sudo su root -c "printf 'xmlrpc_port = ${OE_PORT}\n' >> /etc/${OE_CONFIG}.conf"
fi
sudo su root -c "printf 'logfile = /var/log/${OE_USER}/${OE_CONFIG}.log\n' >> /etc/${OE_CONFIG}.conf"


# Ora scrivi addons_path nel file di configurazione
sudo su root -c "echo -e '$addons_path' >> /etc/${OE_CONFIG}.conf"

sudo chown $OE_USER:$OE_USER /etc/${OE_CONFIG}.conf
sudo chmod 640 /etc/${OE_CONFIG}.conf

echo -e "* Create startup file"
sudo su root -c "echo '#!/bin/sh' >> $OE_HOME_EXT/start.sh"
sudo su root -c "echo \"source '$OE_HOME/odoo-venv/bin/activate'\" >> $OE_HOME_EXT/start.sh"
sudo su root -c "echo 'sudo -u  $OE_USER $OE_HOME/odoo-venv/bin/python3 $OE_HOME_EXT/odoo-bin --config=/etc/${OE_CONFIG}.conf' >> $OE_HOME_EXT/start.sh"

sudo chmod 755 $OE_HOME_EXT/start.sh



#--------------------------------------------------
# Adding ODOO as a deamon (initscript)
#--------------------------------------------------

echo -e "* Create init file"
cat <<EOF > ~/$OE_CONFIG
#!/bin/sh
### BEGIN INIT INFO
# Provides: $OE_CONFIG
# Required-Start: \$remote_fs \$syslog
# Required-Stop: \$remote_fs \$syslog
# Should-Start: \$network
# Should-Stop: \$network
# Default-Start: 2 3 4 5
# Default-Stop: 0 1 6
# Short-Description: Enterprise Business Applications
# Description: ODOO Business Applications
### END INIT INFO
PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/bin
DAEMON=$OE_HOME_EXT/odoo-bin
NAME=$OE_CONFIG
DESC=$OE_CONFIG
# Specify the user name (Default: odoo).
USER=$OE_USER
# Specify an alternate config file (Default: /etc/openerp-server.conf).
#CONFIGFILE="/etc/${OE_CONFIG}.conf"
# pidfile
PIDFILE=/var/run/$OE_USER-server.pid

. /lib/lsb/init-functions

RUN_AS=
CMD=$OE_HOME_EXT/start.sh
OPTS=

do_start() {
    start-stop-daemon --start --background --user \$USER --pidfile \$PIDFILE --chuid \$USER --startas \$CMD -- \$OPTS
}

do_stop() {
    start-stop-daemon --stop --user \$USER
}

case "\$1" in
start)
    log_action_msg "Starting \$NAME"
    do_start
        ;;
stop)
    log_action_msg "Stopping \$NAME"
    do_stop
    ;;
restart)
    log_action_msg "Restarting \$NAME"
    do_stop
    do_start
    ;;
*)
    log_action_msg "Usage: /etc/init.d/$OE_USER-server {start|stop|restart}"
    exit 2
    ;;
esac
exit 0

EOF

echo -e "* Security Init File"
sudo mv ~/$OE_CONFIG /etc/init.d/$OE_CONFIG
sudo chmod 755 /etc/init.d/$OE_CONFIG
sudo chown root: /etc/init.d/$OE_CONFIG

echo -e "* Start ODOO on Startup"
sudo update-rc.d $OE_CONFIG defaults





echo -e "* Starting Odoo Service"
sudo su root -c "/etc/init.d/$OE_CONFIG start"
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
echo "Start Odoo service: sudo service $OE_CONFIG start"
echo "Stop Odoo service: sudo service $OE_CONFIG stop"
echo "Restart Odoo service: sudo service $OE_CONFIG restart"
echo "-----------------------------------------------------------"