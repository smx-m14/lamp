#!/bin/bash

# Comprovació que estem amb root
if [ "$(id -u)" != "0" ]; then
   echo "Aquest programa s'ha d'executar amb l'usuari root" 1>&2;
   exit 1;
else
   echo "Espereu mentre descarreguem els paquets necessaris per iniciar la instal·lació"  1>&2;
fi

# Función per comprovar si un paquet està instal·lat
package_installed() {
    dpkg -s "$1" &> /dev/null
}

# Verificacions prèvies
for pkg in apache2 proftpd-core mariadb-server mysql-server; do
    if package_installed "$pkg"; then
        echo "El paquet $pkg està instal·lat. Instal·lació cancel·lada."
        echo "El podeu desinstal·lar amb apt purge $pkg."
        exit 1
    fi
done

# Comprovacions prèvies i paquets mínims
apt update > /dev/null 2> /dev/null;
apt install -y dialog unzip > /dev/null 2> /dev/null;

# Variables globals
userPass="";

# Contrasenya d'usuari
exitCode1=1;
while [[ $exitCode1 -ne 0 ]]; do
   userPass=$(dialog --title "Contrasenyes pel XAMPP" --insecure --clear --passwordbox "Indiqueu la contrasenya del vostre compte d'usuari" 10 50 3>&1- 1>&2- 2>&3- );
   exitCode1=$?;
   userPassC=$(dialog --title "Contrasenyes pel XAMPP" --insecure --clear --passwordbox "Confirmeu la contrasenya del vostre compte d'usuari" 10 50 3>&1- 1>&2- 2>&3- );
   if [ -z "$userPass" ] || [ "$userPass" != "$userPassC" ]; then
       dialog --msgbox "La contrasenya no pot ser buida o no coincideix. Torneu-ho a provar." 7 50
       exitCode1=1
   fi
done

# Instal·lació dels paquets del servidor
dialog --infobox "Instal·lant els paquets necessaris" 5 50
apt install -y sed apache2 mariadb-server php-mysql libapache2-mod-php php-cli php-mbstring php-intl php-soap php-sqlite3 php-imagick php-curl > /dev/null 2> /dev/null;

# Habilitar mòduls PHP
phpenmod mbstring intl soap > /dev/null 2> /dev/null;

# Configuració SSL amb mkcert
dialog --infobox "Configurant SSL amb mkcert" 5 50
apt install -y libnss3-tools curl > /dev/null 2>&1
if ! command -v mkcert &> /dev/null; then
    cd /tmp
    curl -JLO https://dl.filippo.io/mkcert/latest?for=linux/amd64 > /dev/null 2>&1
    chmod +x mkcert-v*-linux-amd64
    mv mkcert-v*-linux-amd64 /usr/local/bin/mkcert
fi
mkcert -install > /dev/null 2>&1
mkcert -key-file /etc/ssl/private/apache-local.key -cert-file /etc/ssl/certs/apache-local.crt localhost 127.0.0.1 ::1 > /dev/null 2>&1

a2enmod ssl > /dev/null 2>&1
a2ensite default-ssl > /dev/null 2>&1
sed -i 's|SSLCertificateFile.*|SSLCertificateFile /etc/ssl/certs/apache-local.crt|' /etc/apache2/sites-available/default-ssl.conf
sed -i 's|SSLCertificateKeyFile.*|SSLCertificateKeyFile /etc/ssl/private/apache-local.key|' /etc/apache2/sites-available/default-ssl.conf

# Permisos per www-data
dialog --infobox "Configurant permisos" 5 50
pkill www-data
usermod -m -d /var/www/html/ www-data  > /dev/null 2> /dev/null;
usermod -s /bin/bash www-data  > /dev/null 2> /dev/null;
echo "www-data:$userPass" | chpasswd;

# Reinici serveis base
systemctl restart apache2 > /dev/null 2> /dev/null;
systemctl restart mariadb > /dev/null 2> /dev/null;

# Instal·lació phpMyAdmin
dialog --infobox "Configurant phpmyadmin" 5 50
debconf-set-selections <<< "phpmyadmin phpmyadmin/dbconfig-install boolean true"
debconf-set-selections <<< "phpmyadmin phpmyadmin/app-password-confirm password $userPass"
debconf-set-selections <<< "phpmyadmin phpmyadmin/mysql/admin-pass password $userPass"
debconf-set-selections <<< "phpmyadmin phpmyadmin/mysql/app-pass password $userPass"
debconf-set-selections <<< "phpmyadmin phpmyadmin/reconfigure-webserver multiselect apache2"
apt install -y phpmyadmin > /dev/null 2> /dev/null;

# Configuració segura de MySQL
mysql <<EOF
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\_%';
FLUSH PRIVILEGES;
ALTER USER 'root'@'localhost' IDENTIFIED BY '${userPass}';
EOF

# Instal·lar Unzipper i webserver script
dialog --infobox "Configurant servidor web i unzipper" 5 50
cd /var/www/html
rm index.html > /dev/null 2> /dev/null;
wget https://raw.githubusercontent.com/smx-m14/lamp/main/index.html > /dev/null 2> /dev/null;
wget https://raw.githubusercontent.com/smx-m14/lamp/main/unzipper.php > /dev/null 2> /dev/null;
wget https://raw.githubusercontent.com/smx-m14/lamp/main/webserver > /dev/null 2> /dev/null;
mv webserver /usr/local/bin/webserver
chmod +x /usr/local/bin/webserver

# Instal·lar i configurar FTP
dialog --infobox "Configurant FTP" 5 50
apt install -y proftpd-core > /dev/null 2> /dev/null;
chown -R www-data:www-data /var/www/ > /dev/null 2> /dev/null;
sed -i "73 i\DefaultRoot /var/www/html" /etc/proftpd/proftpd.conf;
sed -i 's/User proftpd/User www-data/' /etc/proftpd/proftpd.conf;
sed -i 's/Group nogroup/Group www-data/' /etc/proftpd/proftpd.conf;
echo -e "<Directory /var/www/html>\n\tUmask 022 022\n \tAllowOverwrite on\n\t<Limit ALL>\n\t\tAllowUser www-data\n\t\tDenyAll\n\t</Limit>\n</Directory>" >> /etc/proftpd/proftpd.conf;

# Configuració PHP
dialog --infobox "Configurant php" 5 50
sed -i 's/;max_input_vars = 1000/max_input_vars = 10000/' /etc/php/*/apache2/php.ini

# Redirecció HTTP -> HTTPS
echo "<VirtualHost *:80>
    ServerAdmin webmaster@localhost
    DocumentRoot /var/www/html
    Redirect / https://localhost/
</VirtualHost>" > /etc/apache2/sites-available/000-default.conf

# Reiniciar serveis
dialog --infobox "Reiniciant serveis" 5 50
systemctl restart proftpd apache2 mariadb > /dev/null 2>&1
systemctl disable proftpd apache2 mariadb > /dev/null 2>&1

# Missatge final
dialog --title "Configuració finalitzada" --msgbox "El vostre servidor web ha estat correctament configurat. Espereu uns minuts per accedir-hi per primera vegada." 8 50

# Neteja
clear;
history -c;
