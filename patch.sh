#!/bin/bash

APACHE_DIR="/etc/apache2/sites-available"

for file in "$APACHE_DIR"/*.conf; do
    if ! grep -q "<Directory /var/www/html>" "$file"; then
        echo "Afegint bloc a $file"
        sed -i '/<\/VirtualHost>/i \
<Directory /var/www/html>\
    AllowOverride All\
    Require all granted\
</Directory>' "$file"
    else
        echo "Ja existeix el bloc a $file, no es modifica"
    fi
done

# Reiniciar Apache
echo "Reiniciant Apache..."
sudo systemctl restart apache2

echo "Tots els fitxers revisats i Apache reiniciat."
