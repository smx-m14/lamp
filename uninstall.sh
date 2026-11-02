#!/bin/bash

# purge_lamp.sh
# Desinstal·la i neteja completament tot allò instal·lat per install_local.sh / install_aws.sh
# perquè es pugui tornar a executar l'instal·lador sense conflictes.

# ATENCIÓ: aquest script ESBORRA dades (bases de dades MariaDB, fitxers de /var/www/html,
# certificats SSL locals/Let's Encrypt, usuari www-data reconfigurat, etc.).
# Fes una còpia de seguretat abans si hi ha res que et calgui conservar.

# Mode no interactiu: evita que debconf es quedi esperant respostes invisibles
export DEBIAN_FRONTEND=noninteractive

# Log en lloc de /dev/null, per poder diagnosticar si algo falla
LOG=/var/log/purge_lamp.log
echo "=== purge_lamp.sh $(date) ===" >> "$LOG"

if [ "$(id -u)" != "0" ]; then
echo "Aquest programa s'ha d'executar amb l'usuari root" 1>&2
exit 1
fi

read -p "Això esborrarà Apache, MariaDB, ProFTP, phpMyAdmin i les seves dades. Vols continuar? [s/N] " confirm
if [[ "$confirm" != "s" && "$confirm" != "S" ]]; then
echo "Cancel·lat."
exit 0
fi

echo "==> Responent per endavant les preguntes de purgat (debconf)..."
debconf-set-selections <<'EOF'
phpmyadmin phpmyadmin/dbconfig-remove boolean true
dbconfig-common dbconfig-common/dbconfig-remove boolean true
mariadb-server mariadb-server/postrm_remove_databases boolean true
EOF

echo "==> Purgant phpMyAdmin (amb MariaDB encara actiu, perquè dbconfig-common pugui esborrar la BD)..."
apt-get purge -y phpmyadmin >> "$LOG" 2>&1

echo "==> Aturant serveis..."
systemctl stop apache2 mariadb proftpd noip certbot.timer certbot-renew.service 2>/dev/null

echo "==> Deshabilitant serveis..."
systemctl disable apache2 mariadb proftpd noip certbot.timer certbot-renew.service 2>/dev/null

echo "==> Purgant paquets..."
apt-get purge -y apache2 'apache2-*' libapache2-mod-php \
mariadb-server mariadb-client mariadb-common \
proftpd-core proftpd-basic \
'php*' \
python3-certbot-apache certbot >> "$LOG" 2>&1
apt-get autoremove -y --purge >> "$LOG" 2>&1
apt-get autoclean >> "$LOG" 2>&1

echo "==> Esborrant dades i configuracions residuals..."
rm -rf /etc/apache2
rm -rf /etc/proftpd
rm -rf /etc/mysql
rm -rf /var/lib/mysql
rm -rf /etc/phpmyadmin
rm -rf /var/lib/phpmyadmin
rm -rf /etc/letsencrypt
rm -f /etc/ssl/private/apache-selfsigned.key
rm -f /etc/ssl/certs/apache-selfsigned.crt
rm -f /usr/local/bin/webserver
rm -f /etc/systemd/system/noip.service
rm -f /etc/systemd/system/certbot-renew.service
rm -rf /usr/local/src/noip-2.1.9-1
rm -f /usr/local/src/noip-duc-linux.tar.gz

echo "==> Restaurant l'usuari www-data als valors per defecte..."
usermod -d /var/www -s /usr/sbin/nologin www-data 2>/dev/null
passwd -l www-data 2>/dev/null

echo "==> Netejant configuracions de debconf (phpMyAdmin)..."
echo "PURGE" | debconf-communicate phpmyadmin > /dev/null 2>&1

echo "==> Advertència: /var/www/html NO s'ha esborrat automàticament."
echo " Si vols començar de zero també, executa manualment:"
echo " rm -rf /var/www/html && mkdir -p /var/www/html"

systemctl daemon-reload

echo ""
echo "Neteja completada. El sistema hauria de quedar en estat per tornar a executar l'instal·lador."
echo "Log complet del purgat: $LOG"
