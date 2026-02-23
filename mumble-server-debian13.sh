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
    -d) MODE="delete"; NAME="$2"; shift 2 ;;
    -p) PORT_BASE="$2"; shift 2 ;;
    -l|--list) MODE="list"; shift ;;
    *) NAME="$1"; shift ;;
  esac
done

# Si on n'est pas en mode list et qu'on n'a pas mis de nom, on affiche l'aide
if [[ "$MODE" != "list" && -z "${NAME:-}" ]]; then
  echo "Usage :"
  echo "  Création    : bash mumbleserver3.sh [-p port] <nom>"
  echo "  Suppression : bash mumbleserver3.sh -d <nom>"
  echo "  Liste       : bash mumbleserver3.sh -l"
  exit 1
fi

# --------------------------------------------------
# LISTE DES SERVEURS
# --------------------------------------------------
if [[ "$MODE" == "list" ]]; then
  log "LISTE DES SERVEURS MUMBLE"
  echo -e "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  printf "%-15s | %-10s | %-15s\n" "NOM" "PORT" "STATUT"
  echo -e "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  shopt -s nullglob
  fichiers=(/etc/mumble-server-*.ini)

  if [ ${#fichiers[@]} -eq 0 ]; then
    echo "Aucun serveur Mumble trouvé sur cette machine."
  else
    for conf in "${fichiers[@]}"; do
      BASENAME=$(basename "$conf")
      # Extraction du nom (on enlève le préfixe et l'extension)
      TMP_NAME=${BASENAME#mumble-server-}
      NAME_CLEAN=${TMP_NAME%.ini}

      # Récupération du port dans le fichier
      PORT_USED=$(grep "^port=" "$conf" | cut -d= -f2 || echo "N/A")

      # Récupération du statut systemd
      STATUS=$(systemctl is-active "mumble-server-$NAME_CLEAN" 2>/dev/null || echo "inconnu")

      if [[ "$STATUS" == "active" ]]; then
        STATUS_COLOR="\e[32mEn ligne\e[0m"
      else
        STATUS_COLOR="\e[31m$STATUS\e[0m"
      fi

      printf "%-15s | %-10s | %b\n" "$NAME_CLEAN" "$PORT_USED" "$STATUS_COLOR"
    done
  fi
  echo -e "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  exit 0
fi

# --------------------------------------------------
# VARIABLES (Création / Suppression)
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
  log "Serveur $NAME supprimé COMPLÈTEMENT ✅"
  exit 0
fi

# --------------------------------------------------
# INSTALLATION (Mode CREATE)
# --------------------------------------------------
log "Préparation du système..."
useradd -r -s /bin/false mumble-server 2>/dev/null || true
apt-get update -y >/dev/null
apt-get install -y iproute2 curl unzip bzip2 >/dev/null

log "Désactivation de toute version Debian parasite"
systemctl stop mumble-server 2>/dev/null || true
systemctl disable mumble-server 2>/dev/null || true

log "Téléchargement de Murmur 1.3.4 Statique (Spécial FiveM)"
if [ ! -f "/opt/murmur-1.3.4/murmur.x86" ]; then
  mkdir -p /opt/murmur-1.3.4
  curl -fsSL https://github.com/mumble-voip/mumble/releases/download/1.3.4/murmur-static_x86-1.3.4.tar.bz2 | tar -xj -C /opt
  mv /opt/murmur-static_x86-1.3.4/* /opt/murmur-1.3.4/ 2>/dev/null || true
fi
BIN="/opt/murmur-1.3.4/murmur.x86"

[[ -x "$BIN" ]] || die "Binaire introuvable, erreur de téléchargement."

log "Recherche port disponible (base $PORT_BASE)"
PORT="$PORT_BASE"
while ss -lntu | grep -q ":$PORT "; do
  PORT=$((PORT+1))
done
echo "➡️ Port utilisé : $PORT"

log "Création des dossiers et Base de données..."
mkdir -p "$DB_DIR" "$LOG_DIR"
chown -R mumble-server:mumble-server "$DB_DIR" "$LOG_DIR"
chmod 750 "$DB_DIR"

curl -fsSL "$DB_ZIP_URL" -o "$TMP_DB_ZIP"
unzip -o "$TMP_DB_ZIP" -d "$DB_DIR" >/dev/null
rm -f "$TMP_DB_ZIP"
chown mumble-server:mumble-server "$DB_FILE"
chmod 640 "$DB_FILE"

log "Application des patchs permissifs FiveM..."
curl -fsSL "$CONFIG_URL" -o "$CONFIG"
sed -i "s|^port=.*|port=$PORT|" "$CONFIG"
sed -i "s|^host=.*|host=0.0.0.0|" "$CONFIG"
sed -i "s|^database=.*|database=$DB_FILE|" "$CONFIG"
sed -i "s|^logfile=.*|logfile=$LOG_FILE|" "$CONFIG"
sed -i 's|^username=.*|username=.*|' "$CONFIG"
grep -q '^username=' "$CONFIG" || echo 'username=.*' >> "$CONFIG"
sed -i 's|^;*certrequired=.*|certrequired=false|' "$CONFIG"
sed -i 's|^;*allowhtml=.*|allowhtml=true|' "$CONFIG"
sed -i 's|^;*allowping=.*|allowping=true|' "$CONFIG"
chown root:mumble-server "$CONFIG"
chmod 640 "$CONFIG"

log "Création du service systemd..."
cat > "$UNIT" <<EOF
[Unit]
Description=Mumble Server 1.3.4 ($NAME)
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

log "Démarrage du serveur..."
systemctl daemon-reload
systemctl enable --now "$SERVICE"

IP=$(curl -fsSL https://api.ipify.org || echo "UNKNOWN")

log "SERVEUR MUMBLE EXTERNE 1.3.4 PRÊT ✅"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " Nom     : $NAME"
echo " IP      : $IP"
echo " Port    : $PORT"
echo " Logs    : journalctl -u $SERVICE -f"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
