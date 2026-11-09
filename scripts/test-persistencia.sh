#!/usr/bin/env bash
# Evidencia del Punto Extra 1: los datos sobreviven al borrado del Pod.
# Uso: bash scripts/test-persistencia.sh   (tomar captura de toda la salida)
set -euo pipefail
NS=parcial2-app
PSQL="psql -U postgres -d parcialdb -c"

echo "== 1. Pod actual =="
kubectl get pods -n "$NS" -l app=postgres -o wide

echo "== 2. Insertando datos de prueba =="
kubectl exec -n "$NS" deploy/postgres -- $PSQL \
  "CREATE TABLE IF NOT EXISTS prueba_persistencia(id serial PRIMARY KEY, nota text, creado timestamp DEFAULT now());
   INSERT INTO prueba_persistencia(nota) VALUES ('dato antes de borrar el pod');
   SELECT * FROM prueba_persistencia;"

echo "== 3. Borrando el Pod de Postgres =="
kubectl delete pod -n "$NS" -l app=postgres --wait=true

echo "== 4. Kubernetes recrea el Pod =="
kubectl rollout status deployment/postgres -n "$NS" --timeout=180s
kubectl get pods -n "$NS" -l app=postgres -o wide

echo "== 5. Los datos siguen ahi =="
kubectl exec -n "$NS" deploy/postgres -- $PSQL "SELECT * FROM prueba_persistencia;"
