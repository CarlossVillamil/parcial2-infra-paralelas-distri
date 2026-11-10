#!/usr/bin/env bash
# 6.3 S3: sube los manifiestos de la Fase 1 y un dump fresco de la BD, con el operador.
# Uso (desde la raiz del repo):  bash floci-aws/03-s3.sh
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$DIR/.." && pwd)"
source "$DIR/env.sh"
usar_operador
BUCKET=parcial2-backups
DUMP="$REPO/parcialdb_dump.sql"

paso "Comprobando que kubectl apunta a Minikube (el dump sale del Pod de la Fase 1)"
CTX=$(kubectl config current-context)
echo "Contexto actual: $CTX"
if [ "$CTX" != "minikube" ]; then
  echo "ERROR: el contexto no es 'minikube'. No sigo para no tocar otro cluster." >&2
  exit 1
fi

paso "Generando el dump desde el Pod de PostgreSQL"
bash "$REPO/scripts/dump-db.sh" "$DUMP"
head -n 15 "$DUMP"

paso "Bucket s3://$BUCKET"
aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null \
  && echo "Ya existe" || aws s3 mb "s3://$BUCKET"

paso "Subiendo manifiestos YAML (k8s/) y el dump"
aws s3 cp "$REPO/k8s/" "s3://$BUCKET/manifests/" --recursive
aws s3 cp "$DUMP" "s3://$BUCKET/backups/parcialdb_dump.sql"

paso "CAPTURA 5: contenido del bucket"
aws s3 ls "s3://$BUCKET" --recursive --human-readable --summarize

paso "Verificacion: el dump se puede descargar (s3:GetObject permitido)"
aws s3 cp "s3://$BUCKET/backups/parcialdb_dump.sql" - | head -n 5

paso "CAPTURA 6: el operador NO puede borrar respaldos (s3:DeleteObject no esta en la politica)"
if aws s3 rm "s3://$BUCKET/backups/parcialdb_dump.sql" 2>&1; then
  echo ">>> PERMITIDO: Floci no aplico la politica (documentar como limitacion)"
else
  echo ">>> DENEGADO: los respaldos quedan protegidos contra borrado"
fi
