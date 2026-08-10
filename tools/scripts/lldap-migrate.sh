#!/usr/bin/env bash
#
# lldap-migrate.sh
#
# Migre la base lldap d'un cluster vers un autre.
#
#   ./lldap-migrate.sh extract <cluster-source> <fichier.db>
#   ./lldap-migrate.sh restore <cluster-cible>  <fichier.db>
#
# lldap stocke tout dans un unique SQLite (/data/users.db) : utilisateurs,
# groupes, appartenances, hachages de mots de passe. Il n'y a pas de commande
# d'export — on déplace le fichier.
#
# ─────────────────────────────────────────────────────────────────────────────
# LE PRÉREQUIS QUI DÉCIDE DE TOUT : LLDAP_KEY_SEED
#
# La clé privée du serveur est dérivée de LLDAP_KEY_SEED, et les mots de passe
# sont stockés en OPAQUE, liés à cette clé. Restaurer la base sur une instance
# dont le seed diffère donne un cluster où PLUS AUCUN mot de passe ne fonctionne
# — sans le moindre message d'erreur, juste des authentifications refusées.
#
# Le script refuse de restaurer si les seeds ne correspondent pas.
#
# Ici les deux clusters partagent le même `lldap-secrets` (chiffré SOPS dans
# flux-fleet), donc la condition est remplie par construction.
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

NS=controller-directory
DEPLOY=lldap
PVC=lldap-data
KUSTOMIZATION=infrastructure-directory-lldap

usage() { sed -n '3,20p' "$0" | sed 's/^# \?//'; exit 1; }

[ $# -eq 3 ] || usage
ACTION=$1; CLUSTER=$2; FILE=$3
K="kubectl --context admin@${CLUSTER} -n ${NS}"

seed_fingerprint() {
  kubectl --context "admin@$1" -n "${NS}" get secret lldap-secrets \
    -o jsonpath='{.data.LLDAP_KEY_SEED}' | sha256sum | cut -c1-16
}

inspect() {
  python3 - "$1" <<'PY'
import sqlite3, sys
db = sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True)
print("   integrity_check :", db.execute("PRAGMA integrity_check").fetchone()[0])
for t in ("users", "groups", "memberships"):
    print(f"   {t:<12}: {db.execute(f'SELECT count(*) FROM {t}').fetchone()[0]}")
PY
}

case "${ACTION}" in

  # ───────────────────────────────────────────────────────────────────────────
  # EXTRACT — lecture seule, aucune interruption de service
  #
  # tar plutôt que `kubectl cp` : cp passe par tar de toute façon mais réécrit
  # les métadonnées ; ici on veut des octets identiques, vérifiables au md5.
  #
  # Copier un SQLite à chaud n'est sûr que sans écriture concurrente. Le script
  # compare l'empreinte avant et après : si elle bouge, la copie est rejetée.
  # ───────────────────────────────────────────────────────────────────────────
  extract)
    POD=$(${K} get pods -o name | grep "${DEPLOY}" | head -1 | sed 's|pod/||')
    [ -n "${POD}" ] || { echo "!! aucun pod lldap sur ${CLUSTER}" >&2; exit 1; }

    BEFORE=$(${K} exec "${POD}" -- md5sum /data/users.db | awk '{print $1}')
    echo ">> ${CLUSTER}/${POD} : users.db md5=${BEFORE}"

    ${K} exec "${POD}" -- tar cf - -C /data users.db | tar xf - -O > "${FILE}"

    AFTER=$(${K} exec "${POD}" -- md5sum /data/users.db | awk '{print $1}')
    LOCAL=$(md5sum "${FILE}" | awk '{print $1}')

    if [ "${BEFORE}" != "${AFTER}" ]; then
      echo "!! la base a été écrite pendant la copie (${BEFORE} -> ${AFTER})." >&2
      echo "   Relance, ou mets lldap à l'arrêt le temps de l'extraction." >&2
      exit 1
    fi
    [ "${LOCAL}" = "${BEFORE}" ] || { echo "!! copie corrompue (md5 ${LOCAL})" >&2; exit 1; }

    echo ">> Extrait vers ${FILE} — copie conforme."
    inspect "${FILE}"
    ;;

  # ───────────────────────────────────────────────────────────────────────────
  # RESTORE — destructif, avec interruption de service
  # ───────────────────────────────────────────────────────────────────────────
  restore)
    [ -f "${FILE}" ] || { echo "!! ${FILE} introuvable" >&2; exit 1; }

    echo ">> Contenu à restaurer :"
    inspect "${FILE}"

    SRC_SEED=${SOURCE_CLUSTER:+$(seed_fingerprint "${SOURCE_CLUSTER}")}
    DST_SEED=$(seed_fingerprint "${CLUSTER}")
    if [ -n "${SRC_SEED}" ] && [ "${SRC_SEED}" != "${DST_SEED}" ]; then
      echo "!! LLDAP_KEY_SEED différent (${SRC_SEED} vs ${DST_SEED})." >&2
      echo "   Restaurer maintenant invaliderait TOUS les mots de passe." >&2
      exit 1
    fi
    echo ">> LLDAP_KEY_SEED cible = ${DST_SEED}${SRC_SEED:+ (identique à la source)}"

    if [ "${ASSUME_YES:-false}" != "true" ]; then
      printf "Écraser la base lldap de %s ? [tape OUI] : " "${CLUSTER}"
      read -r a; [ "$a" = "OUI" ] || { echo "Abandon."; exit 1; }
    fi

    # Flux corrigerait la mise à l'arrêt : on le suspend d'abord.
    #
    # Le trap remet TOUT en état quoi qu'il arrive : pod utilitaire supprimé,
    # lldap redémarré, Flux réactivé. Ne réactiver que Flux ne suffit pas — un
    # échec en cours de route laisserait lldap à 0 réplique, donc toute la fleet
    # sans annuaire, jusqu'à la prochaine réconciliation (1h).
    cleanup() {
      echo ">> Remise en état"
      ${K} delete pod lldap-restore --ignore-not-found --wait=false >/dev/null 2>&1 || true
      ${K} scale deploy "${DEPLOY}" --replicas=1 >/dev/null 2>&1 || true
      kubectl --context "admin@${CLUSTER}" -n flux-system patch kustomization "${KUSTOMIZATION}" \
        --type=merge -p '{"spec":{"suspend":false}}' >/dev/null 2>&1 || true
    }
    trap cleanup EXIT

    echo ">> Suspension de ${KUSTOMIZATION}"
    kubectl --context "admin@${CLUSTER}" -n flux-system patch kustomization "${KUSTOMIZATION}" \
      --type=merge -p '{"spec":{"suspend":true}}' >/dev/null

    echo ">> Arrêt de lldap"
    ${K} scale deploy "${DEPLOY}" --replicas=0
    ${K} wait --for=delete pod -l "app.kubernetes.io/name=${DEPLOY}" --timeout=120s 2>/dev/null || sleep 10

    # Le PVC est ReadWriteOnce : impossible de le monter tant que lldap tourne,
    # d'où l'arrêt préalable. Ce pod éphémère sert uniquement de point d'entrée
    # vers le volume.
    #
    # Le securityContext n'est pas décoratif : le namespace applique
    # PodSecurity `restricted`, qui refuse tout pod ne le déclarant pas.
    # runAsUser 1000 = l'UID de lldap (voir UID/GID dans les values), ce qui
    # donne au fichier écrit le bon propriétaire sans chown — impossible de
    # toute façon puisque le conteneur ne tourne pas en root.
    echo ">> Pod utilitaire pour accéder au volume"
    ${K} delete pod lldap-restore --ignore-not-found --wait=true >/dev/null 2>&1 || true
    ${K} apply -f - >/dev/null <<POD
apiVersion: v1
kind: Pod
metadata:
  name: lldap-restore
spec:
  restartPolicy: Never
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    runAsGroup: 1000
    fsGroup: 1000
    seccompProfile:
      type: RuntimeDefault
  containers:
    - name: shell
      image: busybox:1.36
      command: ["sleep", "3600"]
      securityContext:
        allowPrivilegeEscalation: false
        capabilities:
          drop: ["ALL"]
      volumeMounts:
        - name: data
          mountPath: /data
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: ${PVC}
POD
    ${K} wait --for=condition=Ready pod/lldap-restore --timeout=120s

    STAMP=$(${K} exec lldap-restore -- date +%Y%m%d-%H%M%S)
    echo ">> Sauvegarde de l'ancienne base en users.db.bak-${STAMP}"
    ${K} exec lldap-restore -- sh -c "cp -a /data/users.db /data/users.db.bak-${STAMP} 2>/dev/null || true"

    # `kubectl exec -i -- sh -c 'cat > fichier'` n'est PAS fiable pour du
    # binaire : le flux peut se fermer en cours ("websocket: close sent") en
    # laissant un fichier tronqué — voire vide — sans code de retour non nul.
    # `kubectl cp` passe par tar et gère correctement le binaire.
    echo ">> Injection de la nouvelle base"
    ${K} cp "${FILE}" "lldap-restore:/data/users.db"

    # Vérification obligatoire, pas décorative : c'est le seul garde-fou contre
    # une injection silencieusement tronquée. lldap démarrant sur une base vide
    # se réinitialise sans broncher, et la perte ne se voit qu'à la connexion.
    EXPECTED=$(md5sum "${FILE}" | awk '{print $1}')
    ACTUAL=$(${K} exec lldap-restore -- md5sum /data/users.db | awk '{print $1}')
    ${K} exec lldap-restore -- ls -l /data/users.db
    if [ "${EXPECTED}" != "${ACTUAL}" ]; then
      echo "!! injection corrompue : attendu ${EXPECTED}, obtenu ${ACTUAL}" >&2
      echo "   L'ancienne base reste dans /data/users.db.bak-${STAMP}" >&2
      exit 1
    fi
    echo "   md5 conforme (${ACTUAL})"

    ${K} delete pod lldap-restore --wait=true >/dev/null

    echo ">> Redémarrage de lldap"
    ${K} scale deploy "${DEPLOY}" --replicas=1
    ${K} rollout status deploy/"${DEPLOY}" --timeout=180s

    echo ">> Restauration terminée. Vérifie une authentification réelle avant de"
    echo "   considérer la migration acquise : l'intégrité du fichier ne dit rien"
    echo "   de la validité des mots de passe."
    ;;

  *) usage ;;
esac
