#!/bin/bash
# =====================================================================
#  instalar-n8n.sh
#  Instal·lador únic de n8n + ngrok per a Lubuntu 24.04
#  IOC / SMX - Cicle Formatiu
#
#  Aquest fitxer, ell sol, instal·la tot el necessari (Node.js, n8n,
#  ngrok), demana el token de ngrok, i genera dins de
#  ~/n8n-servidor tots els scripts necessaris per arrencar el
#  servidor amb un simple doble clic des de l'escriptori.
# =====================================================================
set -e

APP_DIR="$HOME/n8n-servidor"
CONFIG_DIR="$HOME/.n8n-launcher"
CONFIG_FILE="$CONFIG_DIR/config"

echo "=================================================="
echo " Instal·lador de n8n + ngrok"
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
echo "[1/6] Actualitzant la llista de paquets..."
sudo apt update

# ---------------------------------------------------------------
# 2. Instal·lar Node.js si no hi és
# ---------------------------------------------------------------
if ! command -v node &> /dev/null; then
    echo ""
    echo "[2/6] Instal·lant Node.js (versió LTS)..."
    curl -fsSL https://deb.nodesource.com/setup_24.x | sudo -E bash -
    sudo apt install -y nodejs
else
    echo ""
    echo "[2/6] Node.js ja està instal·lat ($(node -v))."
fi

# ---------------------------------------------------------------
# 3. Instal·lar n8n de forma global
# ---------------------------------------------------------------
echo ""
echo "[3/6] Instal·lant n8n (això pot trigar uns minuts)..."
sudo npm install -g n8n

# ---------------------------------------------------------------
# 4. Instal·lar ngrok
# ---------------------------------------------------------------
if ! command -v ngrok &> /dev/null; then
    echo ""
    echo "[4/6] Instal·lant ngrok..."
    curl -sSL https://ngrok-agent.s3.amazonaws.com/ngrok.asc \
        | sudo tee /etc/apt/trusted.gpg.d/ngrok.asc >/dev/null
    echo "deb https://ngrok-agent.s3.amazonaws.com buster main" \
        | sudo tee /etc/apt/sources.list.d/ngrok.list >/dev/null
    sudo apt update
    sudo apt install -y ngrok
else
    echo ""
    echo "[4/6] ngrok ja està instal·lat."
fi

# ---------------------------------------------------------------
# 5. Demanar el token d'autenticació de ngrok
# ---------------------------------------------------------------
echo ""
echo "[5/6] Configuració del token de ngrok"
echo "------------------------------------------------"
echo "Cal un compte gratuït a https://ngrok.com"
echo "El token es troba a:"
echo "https://dashboard.ngrok.com/get-started/your-authtoken"
echo "------------------------------------------------"
echo ""

TOKEN=""
while [ -z "$TOKEN" ]; do
    read -rp "Introdueix el teu ngrok authtoken: " TOKEN_INPUT
    # Elimina espais en blanc davant i darrere (xargs "recorta" el text)
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
# 6. Generar els scripts d'arrencada dins de ~/n8n-servidor
# ---------------------------------------------------------------
echo ""
echo "[6/6] Generant els fitxers d'arrencada i la icona d'escriptori..."

# --- iniciar-servidor.sh --------------------------------------------
cat > "$APP_DIR/iniciar-servidor.sh" <<'INICIAR_EOF'
#!/bin/bash
# ==================================================
#  Arrenca n8n + túnel ngrok i mostra l'adreça pública
# ==================================================

CONFIG_DIR="$HOME/.n8n-launcher"
CONFIG_FILE="$CONFIG_DIR/config"

clear
echo "=================================================="
echo " Arrencant el servidor n8n..."
echo "=================================================="

if [ ! -f "$CONFIG_FILE" ]; then
    echo ""
    echo "No s'ha trobat cap configuració."
    echo "Cal executar primer l'instal·lador (instalar-n8n.sh)."
    echo ""
    read -rp "Prem Enter per tancar..."
    exit 1
fi

# Neteja de processos previs, per si havien quedat oberts
pkill -f "n8n start" 2>/dev/null
pkill -f "ngrok http 5678" 2>/dev/null
sleep 1

# Atura n8n i ngrok en tancar la finestra o prémer Ctrl+C
netejar() {
    echo ""
    echo "Aturant n8n i ngrok..."
    [ -n "$N8N_PID" ] && kill "$N8N_PID" 2>/dev/null
    [ -n "$NGROK_PID" ] && kill "$NGROK_PID" 2>/dev/null
    exit 0
}
trap netejar SIGINT SIGTERM

# --------------------------------------------------
# 1. Obrir el túnel amb ngrok
# --------------------------------------------------
echo ""
echo "Obrint túnel públic amb ngrok..."
nohup ngrok http 5678 --log=stdout > "$CONFIG_DIR/ngrok.log" 2>&1 &
NGROK_PID=$!

echo -n "Esperant l'adreça pública"
URL=""
INTENTS=0
while [ -z "$URL" ] && [ "$INTENTS" -lt 30 ]; do
    sleep 1
    URL=$(curl -s http://127.0.0.1:4040/api/tunnels 2>/dev/null | python3 -c "
import sys, json
try:
    dades = json.load(sys.stdin)
    print(dades['tunnels'][0]['public_url'])
except Exception:
    pass
" 2>/dev/null)
    echo -n "."
    INTENTS=$((INTENTS+1))
done
echo ""

if [ -z "$URL" ]; then
    echo ""
    echo "No s'ha pogut obtenir l'adreça pública de ngrok."
    echo "Revisa el fitxer: $CONFIG_DIR/ngrok.log"
    echo "S'arrencarà n8n igualment, sense adreça pública."
else
    export WEBHOOK_URL="${URL}/"
    export GENERIC_TIMEZONE="Europe/Madrid"
fi

# --------------------------------------------------
# 2. Arrencar n8n en segon pla (ja amb la WEBHOOK_URL)
# --------------------------------------------------
echo ""
echo "Iniciant n8n en segon pla..."
nohup n8n start > "$CONFIG_DIR/n8n.log" 2>&1 &
N8N_PID=$!

echo -n "Esperant que n8n estigui a punt"
INTENTS=0
until curl -s http://localhost:5678 > /dev/null || [ "$INTENTS" -ge 60 ]; do
    echo -n "."
    sleep 1
    INTENTS=$((INTENTS+1))
done
echo ""

if ! curl -s http://localhost:5678 > /dev/null; then
    echo ""
    echo "n8n no ha arrencat correctament."
    echo "Revisa el fitxer: $CONFIG_DIR/n8n.log"
    read -rp "Prem Enter per tancar..."
    exit 1
fi

echo ""
echo "=================================================="
echo " El teu servidor n8n ja està en marxa!"
echo ""
if [ -n "$URL" ]; then
    echo "   Adreça pública : $URL"
else
    echo "   Adreça pública : no disponible"
fi
echo "   Adreça local   : http://localhost:5678"
echo "=================================================="

echo ""
echo "Deixa aquesta finestra oberta mentre estiguis fent"
echo "servir n8n. Per aturar el servidor, prem Ctrl+C."
echo ""

wait
INICIAR_EOF

# --- llancar-escriptori.sh -------------------------------------------
cat > "$APP_DIR/llancar-escriptori.sh" <<'LLANCAR_EOF'
#!/bin/bash
# Aquest script el crida la icona de l'escriptori.
# Localitza la carpeta on es troba i executa iniciar-servidor.sh

DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
cd "$DIR"
./iniciar-servidor.sh

echo ""
read -rp "Prem Enter per tancar aquesta finestra..."
LLANCAR_EOF

chmod +x "$APP_DIR/iniciar-servidor.sh" "$APP_DIR/llancar-escriptori.sh"

# --- canviar-token.sh --------------------------------------------------
cat > "$APP_DIR/canviar-token.sh" <<'TOKEN_EOF'
#!/bin/bash
# Canvia el token d'autenticació de ngrok i reinicia el servidor
set -e

APP_DIR="$HOME/n8n-servidor"
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
echo "Token actualitzat. Aturant el servidor actual (si n'hi ha)..."
pkill -f "n8n start" 2>/dev/null || true
pkill -f "ngrok http 5678" 2>/dev/null || true
sleep 1

echo "Tornant a arrencar el servidor en una nova finestra..."
x-terminal-emulator -e "$APP_DIR/llancar-escriptori.sh" &

sleep 1
echo ""
echo "Fet! Revisa la nova finestra per veure l'adreça pública."
read -rp "Prem Enter per tancar aquesta finestra..."
TOKEN_EOF

chmod +x "$APP_DIR/canviar-token.sh"

# --- Icona d'escriptori ------------------------------------------------
# El nom de la carpeta de l'escriptori depèn de l'idioma del sistema
# (Desktop, Escriptori, Escritorio...), així que fem servir xdg-user-dir
# per obtenir la ruta real en lloc de suposar-ne el nom.
if ! command -v xdg-user-dir &> /dev/null; then
    sudo apt install -y xdg-user-dirs >/dev/null 2>&1 || true
fi

if command -v xdg-user-dir &> /dev/null; then
    DESKTOP_DIR="$(xdg-user-dir DESKTOP 2>/dev/null)"
fi

# Si per algun motiu no s'ha pogut determinar, es fa servir $HOME com a reserva
if [ -z "$DESKTOP_DIR" ] || [ "$DESKTOP_DIR" = "$HOME" ]; then
    DESKTOP_DIR="$HOME/Desktop"
fi

mkdir -p "$DESKTOP_DIR"
DESKTOP_FILE="$DESKTOP_DIR/Iniciar-n8n.desktop"
echo "Carpeta d'escriptori detectada: $DESKTOP_DIR"

cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Iniciar servidor n8n
Comment=Arrenca n8n i obre un túnel públic amb ngrok
Exec=x-terminal-emulator -e "$APP_DIR/llancar-escriptori.sh"
Icon=utilities-terminal
Terminal=false
Categories=Development;
EOF

chmod +x "$DESKTOP_FILE"
# Marca el llançador com de confiança perquè el gestor de fitxers
# permeti executar-lo amb un doble clic (Nautilus/PCManFM/etc.)
gio set "$DESKTOP_FILE" metadata::trusted true 2>/dev/null || true

echo ""
echo "=================================================="
echo " Instal·lació completada correctament!"
echo ""
echo " S'ha creat la carpeta: $APP_DIR"
echo ""
echo " A partir d'ara, per arrencar el servidor només cal"
echo " fer doble clic a la icona 'Iniciar servidor n8n'"
echo " que trobaràs a: $DESKTOP_DIR"
echo ""
echo " Si vols canviar el token de ngrok:"
echo "   $APP_DIR/canviar-token.sh"
echo "=================================================="
echo ""
read -rp "Prem Enter per tancar..."
