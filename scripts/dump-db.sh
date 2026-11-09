#!/usr/bin/env bash
# Genera el respaldo (dump) de la BD que el Integrante 2 sube al S3 de Floci.
set -euo pipefail
OUT=${1:-parcialdb_dump.sql}
kubectl exec -n parcial2-app deploy/postgres -- pg_dump -U postgres -d parcialdb > "$OUT"
echo "Dump generado: $OUT ($(wc -c < "$OUT") bytes)"
