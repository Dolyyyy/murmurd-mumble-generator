#!/bin/bash
set -euo pipefail

# PATH robuste
export PATH="/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

log(){ echo -e "\n🔹 $1"; }
die(){ echo -e "\n❌ $1"; exit 1; }

# --------------------------------------------------
# ARGUMENTS
# --------------------------------------------------
MODE="create"
PORT_BASE=64738

while [[ $# -gt 0 ]]; do
  case "$1" in
    -d)
      MODE="delete"
      NAME="$2"
      shift 2
      ;;
    -p)
      PORT_BASE="$2"
      shift 2
      ;;
    *)
      NAME="$1"
      shift
      ;;
  esac
done

[[ -z "${NAME:-}" ]] && {
  echo "Usage :"
  echo "  Création    : bash mumbleserver.sh [-p port] <nom>"
  echo "  Suppression : bash mumbleserver.sh -d <nom>"
  exit 1
}

# --------------------------------------------------
# VARIABLES
# --------------------------------------------------
SERVICE="mumble-server-$NAME"
CONFIG="/etc/$SERVICE.ini"
DB_DIR="/var/lib/$SERVICE"
DB_FILE="$DB_DIR/mumble-server.sqlite"
LOG_DIR="/var/log/mumble-server"
LOG_FILE="$LOG_DIR/$SERVICE.log"
UNIT="/etc/systemd/system/$SERVICE.service"

CONFIG_URL="https://raw.githubusercontent.com/Dolyyyy/murmurd-mumble-generator/main/mumble-server.ini"
DB_ZIP_URL="https://github.com/Dolyyyy/murmurd-mumble-generator/raw/main/mumble-server.sqlite.zip"
TMP_DB_ZIP="/tmp/$SERVICE-db.zip"

# --------------------------------------------------
# SUPPRESSION
# --------------------------------------------------
if [[ "$MODE" == "delete" ]]; then
  log "SUPPRESSION COMPLÈTE $NAME"

  systemctl stop "$SERVICE" 2>/dev/null || true
  systemctl disable "$SERVICE" 2>/dev/null || true

  rm -f "$UNIT" "$CONFIG"
  rm -rf "$DB_DIR"
  rm -f "$LOG_FILE"

  systemctl daemon-reload
  systemctl reset-failed "$SERVICE" 2>/dev/null || true

  log "Serveur $NAME supprimé COMPLÈTEMENT ✅"
  exit 0
fi

# --------------------------------------------------
# INSTALLATION
# --------------------------------------------------
log "Installation des dépendances"
apt-get update -y
apt-get install -y mumble-server iproute2 curl unzip

log "Désactivation du service Debian par défaut"
systemctl stop mumble-server 2>/dev/null || true
systemctl disable mumble-server 2>/dev/null || true
systemctl mask mumble-server 2>/dev/null || true

# --------------------------------------------------
# DÉTECTION DU BINAIRE
# --------------------------------------------------
log "Détection du binaire Murmur"

BIN=""
if command -v murmurd >/dev/null 2>&1; then
  BIN="$(command -v murmurd)"
elif [[ -x /usr/sbin/murmurd ]]; then
  BIN="/usr/sbin/murmurd"
elif [[ -x /usr/bin/murmurd ]]; then
  BIN="/usr/bin/murmurd"
fi

[[ -x "$BIN" ]] || die "Binaire Murmur introuvable"

echo "➡️ Binaire détecté : $BIN"

# --------------------------------------------------
# PORT
# --------------------------------------------------
log "Recherche port disponible (base $PORT_BASE)"
PORT="$PORT_BASE"
while ss -lntu | grep -q ":$PORT "; do
  PORT=$((PORT+1))
done
echo "➡️ Port utilisé : $PORT"

# --------------------------------------------------
# DOSSIERS
# --------------------------------------------------
log "Création des dossiers"
mkdir -p "$DB_DIR" "$LOG_DIR"
chown -R mumble-server:mumble-server "$DB_DIR" "$LOG_DIR"
chmod 750 "$DB_DIR"

# --------------------------------------------------
# BASE DE DONNÉES
# --------------------------------------------------
log "Téléchargement de la base de données"
curl -fsSL "$DB_ZIP_URL" -o "$TMP_DB_ZIP"

log "Décompression de la base de données"
unzip -o "$TMP_DB_ZIP" -d "$DB_DIR"
rm -f "$TMP_DB_ZIP"

[[ -f "$DB_FILE" ]] || die "Base de données introuvable"

chown mumble-server:mumble-server "$DB_FILE"
chmod 640 "$DB_FILE"

# --------------------------------------------------
# CONFIGURATION (BASÉE SUR TON GIT)
# --------------------------------------------------
log "Téléchargement de la configuration officielle"
curl -fsSL "$CONFIG_URL" -o "$CONFIG"

# --- PATCH CONFIG (RÈGLES SERVEUR) ---
log "Application des règles serveur permissives"

# Port / host / DB / logs
sed -i "s|^port=.*|port=$PORT|" "$CONFIG"
sed -i "s|^host=.*|host=0.0.0.0|" "$CONFIG"
sed -i "s|^database=.*|database=$DB_FILE|" "$CONFIG"
sed -i "s|^logfile=.*|logfile=$LOG_FILE|" "$CONFIG"

# Autoriser TOUS les pseudos (FiveM / bots / CitizenFX)
sed -i 's|^username=.*|username=.*|' "$CONFIG"
grep -q '^username=' "$CONFIG" || echo 'username=.*' >> "$CONFIG"

# Sécurité / compat
sed -i 's|^;*certrequired=.*|certrequired=false|' "$CONFIG"
sed -i 's|^;*allowhtml=.*|allowhtml=true|' "$CONFIG"
sed -i 's|^;*allowping=.*|allowping=true|' "$CONFIG"
sed -i 's|^;*suggestVersion=.*|suggestVersion=|' "$CONFIG"

chown root:mumble-server "$CONFIG"
chmod 640 "$CONFIG"

# --------------------------------------------------
# SYSTEMD
# --------------------------------------------------
log "Création du service systemd"
cat > "$UNIT" <<EOF
[Unit]
Description=Mumble Server ($NAME)
After=network.target

[Service]
User=mumble-server
Group=mumble-server
ExecStart=$BIN -ini $CONFIG -fg
Restart=on-failure
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF

# --------------------------------------------------
# START
# --------------------------------------------------
log "Activation et démarrage du serveur"
systemctl daemon-reload
systemctl enable --now "$SERVICE"

IP=$(curl -fsSL https://api.ipify.org || echo "UNKNOWN")

# --------------------------------------------------
# RÉCAP
# --------------------------------------------------
log "SERVEUR MUMBLE PRÊT ✅"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " Nom     : $NAME"
echo " IP      : $IP"
echo " Port    : $PORT"
echo " DB      : $DB_FILE"
echo " Logs    : journalctl -u $SERVICE -f"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " Admin SuperUser :"
echo "   $BIN -ini $CONFIG -supw \"TON_MOT_DE_PASSE\""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
