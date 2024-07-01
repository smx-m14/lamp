#!/bin/bash

# Comprovació que estem amb root
if [ "$(id -u)" != "0" ]; then
   echo "Aquest programa s'ha d'executar amb l'usuari root" 1>&2;
   exit 1;
else
	echo "Espereu mentre descarreguem els paquets necessaris per iniciar la instal·lació"  1>&2;
fi


# Función para comprobar si un paquete está instalado
package_installed() {
    dpkg -s "$1" &> /dev/null
}

# Verificaciones previas
if package_installed apache2; then
    echo "El paquet Apache2 està instal·lat en aquest sistema. Instal·lació cancel·lada."
    exit 1
fi

if package_installed proftpd-core; then
    echo "El paquet ProFTP està instal·lat en aquest sistema. Instal·lació cancel·lada."
    exit 1
fi

if package_installed mariadb-server; then
    echo "El paquet MariaDB està instal·lat en aquest sistema. Instal·lació cancel·lada."
    exit 1
fi

if package_installed mysql-server; then
    echo "El paquet MySQL està instal·lat en aquest sistema. Instal·lació cancel·lada."
    exit 1
fi

# Comprovacions prèvies i paquets mínims
apt update > /dev/null 2> /dev/null;
apt install dialog unzip -y > /dev/null 2> /dev/null;

# Variables globals
userPass="";

# Contrasenya d'usuari -> preguntem mentre no s'indiqui dues vegades la mateixa
exitCode1=1;
while [[ $exitCode1 -ne 0 ]]
do
   userPass=$(dialog --title "Contrasenyes pel XAMPP" --insecure --clear --passwordbox "Indiqueu la contrasenya del vostre compte d'usuari" 10 50 3>&1- 1>&2- 2>&3- );
   exitCode1=$?;
   
   userPassC=$(dialog --title "Contrasenyes pel XAMPP" --insecure --clear --passwordbox "Confirmeu la contrasenya del vostre compte d'usuari" 10 50 3>&1- 1>&2- 2>&3- );
   exitCode2=$?;
   
   #Comprovar que no sigui buida i que coincideixin.
   if [ -z "$userPass" ]
   then
 	dialog --msgbox "La contrasenya no pot ser buida. Si us plau, introduïu una contrasenya vàlida." 7 50
 	exitCode1=1;   
   fi
   
   if [ "$userPass" != "$userPassC" ]
   then
 	dialog --msgbox "Les contrasenyes indicades no coincideixen. Si us plau, introduïu-les novament." 7 50
 	exitCode1=1;   
   fi
done

# Instal·lem tota la resta de paquets pel servidor
#apt install -y apache2 mysql-server libapache2-mod-php8.1 php8.1-intl php8.1-gmp php8.1-bcmath php-imagick  php8.1-sqlite3 dbconfig-common dbconfig-mysql default-mysql-client icc-profiles-free  javascript-common libjs-bootstrap4 libjs-codemirror libjs-jquery libjs-jquery-mousewheel libjs-jquery-timepicker libjs-jquery-ui libjs-popper.js libjs-sizzle libjs-sphinxdoc libjs-underscore libonig5 libzip4 mysql-client-8.0 mysql-client-core-8.0 mysql-common node-jquery php-bz2 php-cli php-common php-curl php-gd php-google-recaptcha php-json   php-mariadb-mysql-kbs php-mbstring php-mysql php-nikic-fast-route   php-phpmyadmin-motranslator php-phpmyadmin-shapefile php-phpmyadmin-sql-parser php-phpseclib php-psr-cache php-psr-container php-psr-log php-symfony-cache php-symfony-cache-contracts php-symfony-config php-symfony-dependency-injection php-symfony-deprecation-contracts php-symfony-expression-language php-symfony-filesystem php-symfony-polyfill-php80 php-symfony-polyfill-php81   php-symfony-service-contracts php-symfony-var-exporter php-tcpdf php-twig   php-twig-i18n-extension php-xml php-zip php8.1-bz2 php8.1-cli php8.1-common php8.1-curl php8.1-gd php8.1-mbstring php8.1-mysql php8.1-opcache php8.1-readline php8.1-xml php8.1-zip > /dev/null 2> /dev/null;

dialog --infobox "Instal·lant els paquets necessaris" 5 50

apt install -y sed apache2 mariadb-server php-mysql libapache2-mod-php php-cli php-mbstring php-intl php-soap php-sqlite3 php-imagick php-curl > /dev/null 2> /dev/null;

# Habilitem mòdul manualment
phpenmod mbstring > /dev/null 2> /dev/null;
phpenmod intl > /dev/null 2> /dev/null;
phpenmod soap > /dev/null 2> /dev/null;


dialog --infobox "Configurant SSL" 5 50
# Instalar OpenSSL
sudo apt install -y openssl > /dev/null 2> /dev/null;
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/ssl/private/apache-selfsigned.key -out /etc/ssl/certs/apache-selfsigned.crt -subj "/C=US/ST=State/L=City/O=Organization/OU=IT Department/CN=localhost" > /dev/null 2> /dev/null;
a2enmod ssl > /dev/null 2> /dev/null;
a2ensite default-ssl > /dev/null 2> /dev/null;


dialog --infobox "Configurant permisos" 5 50
# Permisos per la carpeta www-data
pkill www-data
usermod -m -d /var/www/html/ www-data  > /dev/null 2> /dev/null;
usermod -s /bin/bash www-data  > /dev/null 2> /dev/null;
echo "www-data:$userPass" | chpasswd;

# Reiniciem MariaDB
sudo systemctl restart apache2 > /dev/null 2> /dev/null;
sudo systemctl restart mariadb > /dev/null 2> /dev/null;

dialog --infobox "Configurant phpmyadmin" 5 50
# Preconfigurar phpMyAdmin para una instalación no interactiva
sudo debconf-set-selections <<< 'phpmyadmin phpmyadmin/dbconfig-install boolean true'  > /dev/null 2> /dev/null;
sudo debconf-set-selections <<< 'phpmyadmin phpmyadmin/app-password-confirm password $userPass'  > /dev/null 2> /dev/null;
sudo debconf-set-selections <<< 'phpmyadmin phpmyadmin/mysql/admin-pass password $userPass'  > /dev/null 2> /dev/null;
sudo debconf-set-selections <<< 'phpmyadmin phpmyadmin/mysql/app-pass password $userPass'  > /dev/null 2> /dev/null;
sudo debconf-set-selections <<< 'phpmyadmin phpmyadmin/reconfigure-webserver multiselect apache2'  > /dev/null 2> /dev/null;

# Instalar phpMyAdmin
sudo apt install -y phpmyadmin > /dev/null 2> /dev/null;

# Configuracions MYSQL
sudo mysql --execute="DELETE FROM mysql.user WHERE User='';"
sudo mysql --execute="DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
sudo mysql --execute="DROP DATABASE IF EXISTS test;"
sudo mysql --execute="DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"
sudo mysql --execute="FLUSH PRIVILEGES;"
sudo mysql --execute="ALTER USER 'root'@'localhost' IDENTIFIED BY '${userPass}';"

dialog --infobox "Configurant servidor web i unzipper" 5 50
# Descarreguem i instal·lem unzipper
cd /var/www/html
rm index.html > /dev/null 2> /dev/null;
wget https://raw.githubusercontent.com/smx-m14/lamp/main/index.html > /dev/null 2> /dev/null;
wget https://raw.githubusercontent.com/smx-m14/lamp/main/unzipper.php > /dev/null 2> /dev/null;

wget https://raw.githubusercontent.com/smx-m14/lamp/main/webserver > /dev/null 2> /dev/null;
mv webserver /usr/local/bin/webserver > /dev/null 2> /dev/null;
chmod +x /usr/local/bin/webserver > /dev/null 2> /dev/null;

# Instal·lem i configurem FTP
dialog --infobox "Configurant FTP" 5 50
apt install -y proftpd-core > /dev/null 2> /dev/null;
chown -R www-data:www-data /var/www/ > /dev/null 2> /dev/null;
sed -i "73 i\DefaultRoot /var/www/html" /etc/proftpd/proftpd.conf;
sed -i 's/User proftpd/User www-data/' /etc/proftpd/proftpd.conf;
sed -i 's/Group nogroup/Group www-data/' /etc/proftpd/proftpd.conf;
echo -e "<Directory /var/www/html>\n	Umask 022 022\n 	AllowOverwrite on\n	<Limit ALL>\n		AllowUser www-data\n		DenyAll\n	</Limit>\n</Directory>" >> /etc/proftpd/proftpd.conf;

#configuració php??
dialog --infobox "Configurant php" 5 50
sudo sed -i 's/;max_input_vars = 1000/max_input_vars = 10000/' /etc/php/*/apache2/php.ini
# Només a AWS
#sed -i 's/# PassivePorts 49152 65534/PassivePorts 30000 30100/' /etc/proftpd/proftpd.conf;

# Habilitem i arrenquem tots els serveis
#sudo systemctl enable proftpd > /dev/null 2> /dev/null;
#sudo systemctl enable apache2 > /dev/null 2> /dev/null;
dialog --infobox "Reiniciant els serveis" 5 50
sudo systemctl restart proftpd > /dev/null 2> /dev/null;
sudo systemctl restart apache2 > /dev/null 2> /dev/null;
sudo systemctl restart mariadb > /dev/null 2> /dev/null;

sudo systemctl disable proftpd > /dev/null 2> /dev/null;
sudo systemctl disable apache2 > /dev/null 2> /dev/null;
sudo systemctl disable mariadb > /dev/null 2> /dev/null;

dialog --title "Configuració finalitzada" --msgbox "El vostre servidor web ha estat correctament configurat. Espereu uns minuts per accedir-hi per primera vegada" 8 50

# Netegem pantalla
clear;
history -c;
