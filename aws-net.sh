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
    echo "El podeu desinstal·lar amb apt purge apache2."
    exit 1
fi

if package_installed proftpd-core; then
    echo "El paquet ProFTP està instal·lat en aquest sistema. Instal·lació cancel·lada."
    echo "El podeu desinstal·lar amb apt purge proftpd-core."
    exit 1
fi

if package_installed mariadb-server; then
    echo "El paquet MariaDB està instal·lat en aquest sistema. Instal·lació cancel·lada."
    echo "El podeu desinstal·lar amb apt purge mariadb-server."
    exit 1
fi

if package_installed mysql-server; then
    echo "El paquet MySQL està instal·lat en aquest sistema. Instal·lació cancel·lada."
    echo "El podeu desinstal·lar amb apt purge mysql-server."
    exit 1
fi

# Comprovacions prèvies i paquets mínims
apt update > /dev/null 2> /dev/null;
apt install dialog unzip gcc make -y > /dev/null 2> /dev/null;

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
dialog --infobox "Instal·lant els paquets necessaris" 5 50

apt install -y sed apache2 mariadb-server php-mysql libapache2-mod-php php-cli php-mbstring php-intl php-soap php-sqlite3 php-imagick php-curl > /dev/null 2> /dev/null;

# Habilitem mòdul manualment
phpenmod mbstring > /dev/null 2> /dev/null;
phpenmod intl > /dev/null 2> /dev/null;
phpenmod soap > /dev/null 2> /dev/null;


dialog --infobox "Configurant SSL" 5 50
# Instalar OpenSSL
sudo apt install -y openssl > /dev/null 2> /dev/null;
sudo openssl req -x509 -nodes -days 3650 -newkey rsa:2048 -keyout /etc/ssl/private/apache-selfsigned.key -out /etc/ssl/certs/apache-selfsigned.crt -subj "/C=US/ST=State/L=City/O=Organization/OU=IT Department/CN=localhost" > /dev/null 2> /dev/null;
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
for ini in /etc/php/*/apache2/php.ini; do
    sed -i 's/^;*max_input_vars *=.*/max_input_vars = 10000/' "$ini"
    sed -i 's/^;*upload_max_filesize *=.*/upload_max_filesize = 1G/' "$ini"
    sed -i 's/^;*post_max_size *=.*/post_max_size = 1G/' "$ini"
    sed -i 's/^;*memory_limit *=.*/memory_limit = 1G/' "$ini"
    sed -i 's/^;*max_execution_time *=.*/max_execution_time = 600/' "$ini"
done
# Només a AWS
sed -i 's/# PassivePorts 49152 65534/PassivePorts 30000 30100/' /etc/proftpd/proftpd.conf;

# Redirecció de tot el trànsit HTTP a HTTPS
echo "<VirtualHost *:80>
    ServerAdmin webmaster@localhost
    DocumentRoot /var/www/html
    Redirect / https://localhost/
</VirtualHost>" > /etc/apache2/sites-available/000-default.conf

# Habilitem i arrenquem tots els serveis (només a AWS)
sudo systemctl enable proftpd > /dev/null 2> /dev/null;
sudo systemctl enable apache2 > /dev/null 2> /dev/null;
sudo systemctl enable mariadb > /dev/null 2> /dev/null;
dialog --infobox "Reiniciant els serveis" 5 50
sudo systemctl restart proftpd > /dev/null 2> /dev/null;
sudo systemctl restart apache2 > /dev/null 2> /dev/null;
sudo systemctl restart mariadb > /dev/null 2> /dev/null;

#sudo systemctl disable proftpd > /dev/null 2> /dev/null;
#sudo systemctl disable apache2 > /dev/null 2> /dev/null;
#sudo systemctl disable mariadb > /dev/null 2> /dev/null;


# Instal·lació NO-IP
dialog --title "NO-IP" --msgbox "Ara configurarem el servei NO-IP en el servidor. Tingueu en compte que necessiteu tenir creat el compte a https://www.noip.com/ i un domini per poder-lo configurar.\n\nContesteu les preguntes del script de configuració a continuació:\n  * Correu\n  * Contrasenya\n\nLa resta de preguntes es poden contestar amb Enter." 17 50 
clear;
cd /usr/local/src/;
wget http://www.noip.com/client/linux/noip-duc-linux.tar.gz  > /dev/null 2> /dev/null;
tar xf noip-duc-linux.tar.gz  > /dev/null 2> /dev/null;
cd noip-2.1.9-1/  > /dev/null 2> /dev/null;

# Servei NO IP --> repetim mentre la configuració no sigui correcta
lines=0;
while [ $lines -ne 1 ]
do
   make install 2>&1 | tee /tmp/noip.txt;
   lines=`cat /tmp/noip.txt | grep "It will be used" | wc -l`;
   
   if [ $lines -ne 1 ]
   then
        dialog --title "NO-IP" --msgbox "La configuració de NO-IP no s'ha pogut completar correctament. Si us plau, reviseu tots els paràmetres de configuració." 8 50     
   fi
done

# Configurem inici automàtic NO IP
echo "[Unit]
Description=NOIP

[Service]
Type=forking
ExecStart=/usr/local/bin/noip2
Restart=always

[Install]
WantedBy=multi-user.target" > /etc/systemd/system/noip.service

systemctl enable noip 2> /dev/null > /dev/null;
systemctl start noip 2> /dev/null > /dev/null;


dialog --title "Configuració finalitzada" --msgbox "El vostre servidor web ha estat correctament configurat. Espereu uns minuts per accedir-hi per primera vegada" 8 50

# Netegem pantalla
clear;
history -c;
