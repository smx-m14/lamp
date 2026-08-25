#!/bin/bash
# =====================================================================
#  instalar-n8n-server.sh
#  Instal·lador únic de n8n + ngrok per a Ubuntu Server 24.04
#  IOC / SMX - Cicle Formatiu
#
#  Versió adaptada per a servidor sense entorn gràfic: en lloc de
#  crear una icona d'escriptori, es creen dos serveis de systemd
#  (n8n.service i ngrok-n8n.service) que arrenquen automàticament
#  amb la màquina, es reinicien sols si fallen, i queden actius
#  encara que no hi hagi cap sessió d'usuari oberta.
# =====================================================================
set -e

APP_USER="$(whoami)"
APP_DIR="$HOME/n8n-servidor"
CONFIG_DIR="$HOME/.n8n-launcher"
CONFIG_FILE="$CONFIG_DIR/config"

echo "=================================================="
echo " Instal·lador de n8n + ngrok (Ubuntu Server)"
echo "=================================================="
echo ""

if [ "$EUID" -eq 0 ]; then
    echo "No executis aquest script com a root directament."
    echo "Executa'l com a usuari normal (farà servir sudo quan calgui)."
    exit 1
fi

mkdir -p "$APP_DIR"
mkdir -p "$CONFIG_DIR"

# ---------------------------------------------------------------
# 1. Actualitzar repositoris
# ---------------------------------------------------------------
echo "[1/8] Actualitzant la llista de paquets..."
sudo apt update

# ---------------------------------------------------------------
# 2. Instal·lar Node.js si no hi és
# ---------------------------------------------------------------
NODE_MAJOR_REQUIRED=22

if ! command -v node &> /dev/null; then
    echo ""
    echo "[2/8] Instal·lant Node.js ${NODE_MAJOR_REQUIRED}.x (LTS)..."
    curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR_REQUIRED}.x" | sudo -E bash -
    sudo apt install -y nodejs
else
    NODE_MAJOR_ACTUAL=$(node -v | sed 's/^v//' | cut -d. -f1)
    if [ "$NODE_MAJOR_ACTUAL" -lt "$NODE_MAJOR_REQUIRED" ]; then
        echo ""
        echo "[2/8] Node.js $(node -v) és massa antic per a n8n (calen >= v${NODE_MAJOR_REQUIRED})."
        echo "       Actualitzant a Node.js ${NODE_MAJOR_REQUIRED}.x..."
        curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR_REQUIRED}.x" | sudo -E bash -
        sudo apt install -y nodejs
    else
        echo ""
        echo "[2/8] Node.js ja està instal·lat ($(node -v))."
    fi
fi


# ---------------------------------------------------------------
# 4. Instal·lar n8n de forma global
# ---------------------------------------------------------------
echo ""
echo "[3/8] Instal·lant n8n (això pot trigar uns minuts)..."
sudo npm install -g n8n

# Si s'ha creat swap temporal només per a la instal·lació, es desactiva
# i s'esborra (a menys que ja hi hagués poca RAM permanentment, en
# aquest cas es recomana deixar-la activa; es demana confirmació).
if [ "$SWAP_TEMPORAL" = "si" ]; then
    echo ""
    read -rp "Vols deixar activada la swap de 2 GB de forma permanent? (recomanat en màquines amb poca RAM) [S/n]: " RESP
    RESP=$(echo "$RESP" | xargs | tr '[:upper:]' '[:lower:]')
    if [ "$RESP" = "n" ]; then
        sudo swapoff "$SWAPFILE"
        sudo rm -f "$SWAPFILE"
        echo "Swap temporal eliminada."
    else
        if ! grep -q "$SWAPFILE" /etc/fstab; then
            echo "$SWAPFILE none swap sw 0 0" | sudo tee -a /etc/fstab > /dev/null
        fi
        echo "Swap deixada activa de forma permanent (${SWAPFILE})."
    fi
fi

# ---------------------------------------------------------------
# 5. Instal·lar ngrok
# ---------------------------------------------------------------
if ! command -v ngrok &> /dev/null; then
    echo ""
    echo "[4/8] Instal·lant ngrok..."
    curl -sSL https://ngrok-agent.s3.amazonaws.com/ngrok.asc \
        | sudo tee /etc/apt/trusted.gpg.d/ngrok.asc >/dev/null
    echo "deb https://ngrok-agent.s3.amazonaws.com buster main" \
        | sudo tee /etc/apt/sources.list.d/ngrok.list >/dev/null
    sudo apt update
    sudo apt install -y ngrok
else
    echo ""
    echo "[4/8] ngrok ja està instal·lat."
fi

# ---------------------------------------------------------------
# 6. Demanar el token d'autenticació de ngrok
# ---------------------------------------------------------------
echo ""
echo "[5/8] Configuració del token de ngrok"
echo "------------------------------------------------"
echo "Cal un compte gratuït a https://ngrok.com"
echo "El token es troba a:"
echo "https://dashboard.ngrok.com/get-started/your-authtoken"
echo "------------------------------------------------"
echo ""

TOKEN=""
while [ -z "$TOKEN" ]; do
    read -rp "Introdueix el teu ngrok authtoken: " TOKEN_INPUT
    TOKEN=$(echo "$TOKEN_INPUT" | xargs)
    if [ -z "$TOKEN" ]; then
        echo "El token no pot estar buit. Torna-ho a provar."
    fi
done

ngrok config add-authtoken "$TOKEN"
echo "$TOKEN" > "$CONFIG_FILE"
chmod 600 "$CONFIG_FILE"

echo ""
echo "Token desat correctament."


# ---------------------------------------------------------------
# 7. Crear els scripts d'arrencada i d'ajuda
# ---------------------------------------------------------------
echo ""
echo "[6/8] Creant els scripts d'arrencada i d'ajuda..."

NGROK_BIN="$(command -v ngrok)"
N8N_BIN="$(command -v n8n)"

# --- iniciar-ngrok.sh: llança el túnel, amb domini fix si n'hi ha --
cat > "$APP_DIR/iniciar-ngrok.sh" <<EOF
#!/bin/bash
DOMAIN_FILE="$DOMAIN_FILE"
NGROK_BIN="$NGROK_BIN"
DOMINI=""
[ -f "\$DOMAIN_FILE" ] && DOMINI=\$(cat "\$DOMAIN_FILE")

if [ -n "\$DOMINI" ]; then
    exec "\$NGROK_BIN" http --domain="\$DOMINI" 5678 --log=stdout
else
    exec "\$NGROK_BIN" http 5678 --log=stdout
fi
EOF
chmod +x "$APP_DIR/iniciar-ngrok.sh"

# --- iniciar-n8n.sh: espera la URL pública i l'injecta a n8n -------
cat > "$APP_DIR/iniciar-n8n.sh" <<EOF
#!/bin/bash
DOMAIN_FILE="$DOMAIN_FILE"
N8N_BIN="$N8N_BIN"
DOMINI=""
[ -f "\$DOMAIN_FILE" ] && DOMINI=\$(cat "\$DOMAIN_FILE")

URL=""
if [ -n "\$DOMINI" ]; then
    URL="https://\$DOMINI"
else
    # Sense domini fix: cal esperar que ngrok obri el túnel i
    # llegir l'URL aleatòria des de la seva API local.
    INTENTS=0
    while [ -z "\$URL" ] && [ "\$INTENTS" -lt 30 ]; do
        URL=\$(curl -s http://127.0.0.1:4040/api/tunnels 2>/dev/null | python3 -c "
import sys, json
try:
    print(json.load(sys.stdin)['tunnels'][0]['public_url'])
except Exception:
    pass
" 2>/dev/null)
        [ -z "\$URL" ] && sleep 1
        INTENTS=\$((INTENTS+1))
    done
fi

if [ -n "\$URL" ]; then
    export WEBHOOK_URL="\${URL}/"
fi

exec "\$N8N_BIN" start
EOF
chmod +x "$APP_DIR/iniciar-n8n.sh"

# --- veure-url.sh: mostra l'URL pública actual ----------------------
cat > "$APP_DIR/veure-url.sh" <<'URL_EOF'
#!/bin/bash
# Mostra l'adreça pública actual del túnel ngrok (si està en marxa)
URL=$(curl -s http://127.0.0.1:4040/api/tunnels 2>/dev/null | python3 -c "
import sys, json
try:
    dades = json.load(sys.stdin)
    print(dades['tunnels'][0]['public_url'])
except Exception:
    print('')
" 2>/dev/null)

if [ -z "$URL" ]; then
    echo "No s'ha trobat cap túnel actiu. Comprova l'estat amb:"
    echo "  systemctl status n8n.service ngrok-n8n.service"
else
    echo "Adreça pública: $URL"
    echo "Adreça local  : http://localhost:5678"
fi
URL_EOF
chmod +x "$APP_DIR/veure-url.sh"

# --- cambiar-token.sh: canvia el token i reinicia tot ---------------
cat > "$APP_DIR/cambiar-token.sh" <<'TOKEN_EOF'
#!/bin/bash
# Canvia el token d'autenticació de ngrok i reinicia el túnel
set -e

CONFIG_DIR="$HOME/.n8n-launcher"
CONFIG_FILE="$CONFIG_DIR/config"

echo "=================================================="
echo " Canviar el token de ngrok"
echo "=================================================="
echo ""
echo "Pots trobar el teu token a:"
echo "https://dashboard.ngrok.com/get-started/your-authtoken"
echo ""

TOKEN=""
while [ -z "$TOKEN" ]; do
    read -rp "Introdueix el nou ngrok authtoken: " TOKEN_INPUT
    TOKEN=$(echo "$TOKEN_INPUT" | xargs)
    if [ -z "$TOKEN" ]; then
        echo "El token no pot estar buit. Torna-ho a provar."
    fi
done

ngrok config add-authtoken "$TOKEN"
echo "$TOKEN" > "$CONFIG_FILE"
chmod 600 "$CONFIG_FILE"

echo ""
echo "Token actualitzat. Reiniciant ngrok i n8n..."
sudo systemctl restart ngrok-n8n.service
sleep 2
sudo systemctl restart n8n.service

echo -n "Esperant que n8n torni a estar a punt"
INTENTS=0
until curl -s http://localhost:5678 > /dev/null || [ "$INTENTS" -ge 60 ]; do
    echo -n "."
    sleep 1
    INTENTS=$((INTENTS+1))
done
echo ""

echo ""
echo "Fet! Nova adreça pública:"
"$(dirname "$0")/veure-url.sh"
TOKEN_EOF
chmod +x "$APP_DIR/cambiar-token.sh"

# --- cambiar-domini.sh: fixa/canvia/treu el domini estàtic ----------
cat > "$APP_DIR/cambiar-domini.sh" <<'DOMINI_EOF'
#!/bin/bash
# Fixa, canvia o elimina el domini estàtic de ngrok
set -e

CONFIG_DIR="$HOME/.n8n-launcher"
DOMAIN_FILE="$CONFIG_DIR/domini"

echo "=================================================="
echo " Domini estàtic de ngrok"
echo "=================================================="
echo ""
echo "Reserva'n un de franc a: https://dashboard.ngrok.com/domains"
echo ""
read -rp "Nou domini (deixa en blanc per treure'l): " DOMINI_INPUT
DOMINI=$(echo "$DOMINI_INPUT" | xargs)
echo "$DOMINI" > "$DOMAIN_FILE"

if [ -n "$DOMINI" ]; then
    echo "Domini desat: $DOMINI"
else
    echo "Domini eliminat: es farà servir una URL aleatòria."
fi

echo ""
echo "Reiniciant ngrok i n8n..."
sudo systemctl restart ngrok-n8n.service
sleep 2
sudo systemctl restart n8n.service

echo -n "Esperant que n8n torni a estar a punt"
INTENTS=0
until curl -s http://localhost:5678 > /dev/null || [ "$INTENTS" -ge 60 ]; do
    echo -n "."
    sleep 1
    INTENTS=$((INTENTS+1))
done
echo ""

echo ""
echo "Fet! Nova adreça pública:"
"$(dirname "$0")/veure-url.sh"
DOMINI_EOF
chmod +x "$APP_DIR/cambiar-domini.sh"

# ---------------------------------------------------------------
# 8. Crear i activar els serveis de systemd
# ---------------------------------------------------------------
# Ordre important: primer ngrok (obre el túnel), després n8n
# (que espera l'URL pública i l'hi injecta com a WEBHOOK_URL abans
# d'arrencar, perquè els webhooks es generin amb l'adreça correcta
# en lloc de "localhost").
echo ""
echo "[7/8] Creant els serveis de systemd..."

sudo tee /etc/systemd/system/ngrok-n8n.service > /dev/null <<EOF
[Unit]
Description=Túnel ngrok per a n8n
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${APP_USER}
WorkingDirectory=${HOME}
ExecStart=${APP_DIR}/iniciar-ngrok.sh
Restart=on-failure
RestartSec=5
StandardOutput=append:${CONFIG_DIR}/ngrok.log
StandardError=append:${CONFIG_DIR}/ngrok.log

[Install]
WantedBy=multi-user.target
EOF

sudo tee /etc/systemd/system/n8n.service > /dev/null <<EOF
[Unit]
Description=Servidor n8n
After=ngrok-n8n.service network-online.target
Requires=ngrok-n8n.service
Wants=network-online.target

[Service]
Type=simple
User=${APP_USER}
WorkingDirectory=${HOME}
ExecStart=${APP_DIR}/iniciar-n8n.sh
Restart=on-failure
RestartSec=5
StandardOutput=append:${CONFIG_DIR}/n8n.log
StandardError=append:${CONFIG_DIR}/n8n.log

[Install]
WantedBy=multi-user.target
EOF

echo ""
echo "[8/8] Activant i arrencant els serveis..."
sudo systemctl daemon-reload
sudo systemctl enable ngrok-n8n.service
sudo systemctl enable n8n.service
sudo systemctl restart ngrok-n8n.service
sleep 3
sudo systemctl restart n8n.service

echo -n "Esperant que n8n estigui a punt"
INTENTS=0
until curl -s http://localhost:5678 > /dev/null || [ "$INTENTS" -ge 60 ]; do
    echo -n "."
    sleep 1
    INTENTS=$((INTENTS+1))
done
echo ""

echo ""
echo "=================================================="
echo " Instal·lació completada correctament!"
echo ""
echo " Els serveis s'arrencaran automàticament en cada"
echo " reinici de la màquina. No cal fer res més."
echo ""
echo " Comandes útils:"
echo "   Veure l'URL públic actual :  $APP_DIR/veure-url.sh"
echo "   Canviar el token de ngrok :  $APP_DIR/cambiar-token.sh"
echo "   Fixar/canviar el domini   :  $APP_DIR/cambiar-domini.sh"
echo "   Estat dels serveis        :  systemctl status n8n.service ngrok-n8n.service"
echo "   Registres de n8n          :  journalctl -u n8n.service -f"
echo "   Registres de ngrok        :  journalctl -u ngrok-n8n.service -f"
echo "   Aturar-los                :  sudo systemctl stop n8n.service ngrok-n8n.service"
echo "   Reiniciar-los             :  sudo systemctl restart n8n.service ngrok-n8n.service"
echo "=================================================="
echo ""
"$APP_DIR/veure-url.sh"
