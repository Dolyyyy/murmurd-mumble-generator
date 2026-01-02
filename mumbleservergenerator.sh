#!/bin/bash
set -euo pipefail

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
BIN="/usr/bin/mumble-server"
CONFIG="/etc/$SERVICE.ini"
DB_DIR="/var/lib/$SERVICE"
DB_FILE="$DB_DIR/mumble-server.sqlite"
LOG_DIR="/var/log/mumble-server"
LOG_FILE="$LOG_DIR/$SERVICE.log"
UNIT="/etc/systemd/system/$SERVICE.service"

DB_ZIP_URL="https://github.com/Dolyyyy/murmurd-mumble-generator/raw/main/mumble-server.sqlite.zip"
TMP_ZIP="/tmp/$SERVICE-db.zip"

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

[[ -x "$BIN" ]] || die "Binaire mumble-server introuvable"

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
curl -fsSL "$DB_ZIP_URL" -o "$TMP_ZIP"

log "Décompression de la base de données"
unzip -o "$TMP_ZIP" -d "$DB_DIR"
rm -f "$TMP_ZIP"

[[ -f "$DB_FILE" ]] || die "DB introuvable après décompression"

chown mumble-server:mumble-server "$DB_FILE"
chmod 640 "$DB_FILE"

# --------------------------------------------------
# CONFIG
# --------------------------------------------------
log "Création du fichier de configuration"
cat > "$CONFIG" <<EOF
port=$PORT
host=0.0.0.0
database=$DB_FILE
logfile=$LOG_FILE
welcometext="Bienvenue sur $NAME"
EOF

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
echo " Logs    : $LOG_FILE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " Admin SuperUser :"
echo "   $BIN -ini $CONFIG -supw \"TON_MOT_DE_PASSE\""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
