#!/usr/bin/env bash
# ============================================================
# import-haxe.sh
# Convertit un dump SQL Alterconso (Haxe, PascalCase) en un dump
# d'import compatible avec le code Go (GORM, snake_case),
# en purgeant les tables transitoires inutiles.
#
# 100% autonome : utilise des assets SQL fournis à côté du script
# (gorm-schema.sql + migrate-haxe-to-gorm.sql), et peut spawner un
# MySQL temporaire dans Docker (--docker) pour ne dépendre de rien
# d'autre que Docker + le client mysql.
#
# Usage :
#   ./import-haxe.sh [--docker] <input.sql> [output.sql]
#   # défaut : output = <input>.gorm.sql
#
# --docker : démarre un container mysql:8 éphémère exposé sur DB_PORT,
#            détruit à la fin (même en cas d'erreur). Sinon, suppose
#            un MySQL accessible sur DB_HOST:DB_PORT.
#
# Variables d'environnement (avec valeurs par défaut) :
#   DB_HOST          127.0.0.1
#   DB_PORT          3308           (3308 pour ne pas se cogner avec un MySQL local)
#   DB_USER          alterconso
#   DB_PASSWORD      changeme
#   DB_ROOT_USER     root
#   DB_ROOT_PASSWORD root
#   TMP_DB           alterconso_haxe_import
#   DOCKER_IMAGE     mysql:8        (--docker uniquement)
#
# Étapes :
#   1. (--docker) démarrage container MySQL + attente readiness
#   2. filtrage du dump (Error, Session, BufferedMail, Cache)
#   3. drop/recréation de la base temporaire + grants
#   4. import du dump Haxe filtré
#   5. application de gorm-schema.sql (tables snake_case vides)
#   6. application de migrate-haxe-to-gorm.sql (copie + transformation)
#   7. suppression des tables Haxe résiduelles
#   8. mysqldump des tables GORM uniquement → output
#   9. drop base temporaire (+ stop container si --docker)
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GORM_SCHEMA="$SCRIPT_DIR/gorm-schema.sql"
MIGRATE_SQL="$SCRIPT_DIR/migrate-haxe-to-gorm.sql"

USE_DOCKER=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --docker) USE_DOCKER=1; shift ;;
    -h|--help)
      sed -n '2,30p' "$0" | sed 's/^# \?//'
      exit 0
      ;;
    --) shift; break ;;
    -*) echo "option inconnue : $1" >&2; exit 2 ;;
    *) break ;;
  esac
done

INPUT="${1:-}"
OUTPUT="${2:-}"

if [[ -z "$INPUT" || ! -f "$INPUT" ]]; then
  echo "Usage: $0 [--docker] <input.sql> [output.sql]" >&2
  exit 1
fi
if [[ -z "$OUTPUT" ]]; then
  OUTPUT="${INPUT%.sql}.gorm.sql"
fi

for f in "$GORM_SCHEMA" "$MIGRATE_SQL"; do
  [[ -f "$f" ]] || { echo "asset manquant : $f" >&2; exit 1; }
done

DB_HOST="${DB_HOST:-127.0.0.1}"
DB_PORT="${DB_PORT:-3308}"
DB_USER="${DB_USER:-alterconso}"
DB_PASSWORD="${DB_PASSWORD:-changeme}"
DB_ROOT_USER="${DB_ROOT_USER:-root}"
DB_ROOT_PASSWORD="${DB_ROOT_PASSWORD:-root}"
TMP_DB="${TMP_DB:-alterconso_haxe_import}"
DOCKER_IMAGE="${DOCKER_IMAGE:-mysql:8}"
DOCKER_NAME="alterconso-import-haxe-$$"

MYSQL_OPTS=(-u "$DB_USER" -p"$DB_PASSWORD" -h "$DB_HOST" -P "$DB_PORT")
MYSQL_ROOT_OPTS=(-u "$DB_ROOT_USER" -p"$DB_ROOT_PASSWORD" -h "$DB_HOST" -P "$DB_PORT")
MYSQLDUMP_OPTS=(-u "$DB_USER" -p"$DB_PASSWORD" -h "$DB_HOST" -P "$DB_PORT")

WORK_DIR="$(mktemp -d)"

log() { echo "[import-haxe] $*"; }

cleanup() {
  rm -rf "$WORK_DIR"
  if [[ "$USE_DOCKER" == "1" ]] && docker ps -q --filter "name=^${DOCKER_NAME}$" | grep -q .; then
    log "→ arrêt du container MySQL temporaire ($DOCKER_NAME)..."
    docker stop "$DOCKER_NAME" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

# ============================================================
# Étape 1 : (optionnel) MySQL temporaire via Docker
# ============================================================
if [[ "$USE_DOCKER" == "1" ]]; then
  log "1/9 — démarrage MySQL temporaire (Docker, $DOCKER_IMAGE) sur ${DB_HOST}:${DB_PORT}..."
  docker run --rm -d \
    --name "$DOCKER_NAME" \
    -e MYSQL_ROOT_PASSWORD="$DB_ROOT_PASSWORD" \
    -e MYSQL_USER="$DB_USER" \
    -e MYSQL_PASSWORD="$DB_PASSWORD" \
    -p "${DB_PORT}:3306" \
    "$DOCKER_IMAGE" \
    --character-set-server=utf8mb4 \
    --collation-server=utf8mb4_unicode_ci >/dev/null

  log "    attente que MySQL réponde..."
  for i in $(seq 1 60); do
    if mysqladmin "${MYSQL_ROOT_OPTS[@]}" ping --silent >/dev/null 2>&1; then
      log "    prêt (après ${i}s)"
      break
    fi
    sleep 1
    if [[ "$i" == "60" ]]; then
      log "✗ MySQL n'a pas démarré dans les temps"
      exit 1
    fi
  done
else
  log "1/9 — MySQL externe attendu sur ${DB_HOST}:${DB_PORT} (passe --docker pour le spawner)"
  mysqladmin "${MYSQL_ROOT_OPTS[@]}" ping --silent >/dev/null 2>&1 || {
    log "✗ pas de réponse sur ${DB_HOST}:${DB_PORT}"
    exit 1
  }
fi

FILTERED_SQL="$WORK_DIR/filtered.sql"

# ============================================================
# Étape 2 : filtrage du dump
# ============================================================
log "2/9 — filtrage des tables transitoires (Error, Session, BufferedMail, Cache)..."
awk '
BEGIN { skip = 0 }
/^-- (Table structure|Dumping data) for table `[^`]+`/ {
  match($0, /`[^`]+`/)
  tbl = substr($0, RSTART+1, RLENGTH-2)
  if (tbl == "Error" || tbl == "Session" || tbl == "BufferedMail" || tbl == "Cache") {
    skip = 1
  } else {
    skip = 0
  }
}
!skip
' "$INPUT" > "$FILTERED_SQL"

ORIG_SIZE=$(stat -c%s "$INPUT")
FILT_SIZE=$(stat -c%s "$FILTERED_SQL")
log "    $(numfmt --to=iec-i --suffix=B "$ORIG_SIZE") -> $(numfmt --to=iec-i --suffix=B "$FILT_SIZE")"

# ============================================================
# Étape 3 : recréation de la base temporaire
# ============================================================
log "3/9 — drop/recréation de la base $TMP_DB..."
mysql "${MYSQL_ROOT_OPTS[@]}" -e "
  DROP DATABASE IF EXISTS \`$TMP_DB\`;
  CREATE DATABASE \`$TMP_DB\` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
  GRANT ALL PRIVILEGES ON \`$TMP_DB\`.* TO '$DB_USER'@'%';
  FLUSH PRIVILEGES;
" 2>&1 | grep -v "Warning" || true

# ============================================================
# Étape 4 : import du dump filtré
# ============================================================
log "4/9 — import du dump Haxe filtré..."
mysql "${MYSQL_OPTS[@]}" "$TMP_DB" < "$FILTERED_SQL" 2>&1 | grep -v "Warning" || true

# ============================================================
# Étape 5 : application du schéma GORM (snake_case, tables vides)
# ============================================================
log "5/9 — application de gorm-schema.sql..."
mysql "${MYSQL_OPTS[@]}" "$TMP_DB" < "$GORM_SCHEMA" 2>&1 | grep -v "Warning" || true

# ============================================================
# Étape 6 : transformation Haxe -> GORM
# ============================================================
log "6/9 — application de migrate-haxe-to-gorm.sql..."
mysql "${MYSQL_OPTS[@]}" "$TMP_DB" < "$MIGRATE_SQL" 2>&1 | grep -v "Warning" | tail -20 || true

# ============================================================
# Étape 7 : suppression des tables Haxe résiduelles
# ============================================================
log "7/9 — suppression des tables Haxe (PascalCase) sauf File..."
# File a le même nom (PascalCase) côté GORM — on le garde.
HAXE_TABLES=$(mysql "${MYSQL_OPTS[@]}" -N -e "
  SELECT GROUP_CONCAT(TABLE_NAME SEPARATOR '\`,\`')
  FROM information_schema.TABLES
  WHERE TABLE_SCHEMA = '$TMP_DB'
    AND TABLE_NAME NOT REGEXP '^[a-z]'
    AND TABLE_NAME <> 'File'
" "$TMP_DB" 2>&1 | grep -v "Warning" | tail -1)

if [[ -n "$HAXE_TABLES" && "$HAXE_TABLES" != "NULL" ]]; then
  mysql "${MYSQL_OPTS[@]}" "$TMP_DB" -e "
    SET FOREIGN_KEY_CHECKS=0;
    DROP TABLE IF EXISTS \`$HAXE_TABLES\`;
    SET FOREIGN_KEY_CHECKS=1;
  " 2>&1 | grep -v "Warning" || true
fi

# ============================================================
# Étape 8 : mysqldump propre
# ============================================================
log "8/9 — mysqldump vers $OUTPUT..."
mysqldump "${MYSQLDUMP_OPTS[@]}" \
  --no-tablespaces \
  --skip-comments \
  --single-transaction \
  --default-character-set=utf8mb4 \
  --hex-blob \
  "$TMP_DB" > "$OUTPUT" 2>/dev/null

OUT_SIZE=$(stat -c%s "$OUTPUT")
log "    dump généré : $(numfmt --to=iec-i --suffix=B "$OUT_SIZE")"

# ============================================================
# Étape 9 : nettoyage base
# ============================================================
log "9/9 — drop de la base temporaire $TMP_DB..."
mysql "${MYSQL_ROOT_OPTS[@]}" -e "DROP DATABASE \`$TMP_DB\`;" 2>&1 | grep -v "Warning" || true

log ""
log "✓ terminé : $OUTPUT"
