#!/usr/bin/env bash
# Redespliega la capa de base de datos (Integrante 1) en Minikube.
# Uso (desde la raiz del repo, en la EC2):  bash scripts/redeploy-db.sh
set -euo pipefail
NS=parcial2-app

echo ">> Borrando el despliegue anterior (Deployment + PVC dinamico)"
kubectl delete deployment postgres -n "$NS" --ignore-not-found
kubectl delete pvc postgres-pvc -n "$NS" --ignore-not-found --wait=true

echo ">> Aplicando manifiestos en orden (00 -> 04)"
kubectl apply -f k8s/00-namespace.yaml
kubectl apply -f k8s/01-db-secret.yaml
kubectl apply -f k8s/02-db-pv.yaml
kubectl apply -f k8s/03-db-pvc.yaml
kubectl apply -f k8s/04-postgres-deployment.yaml

echo ">> Esperando a que Postgres este listo"
kubectl rollout status deployment/postgres -n "$NS" --timeout=180s

kubectl get pv,pvc -n "$NS"
kubectl get pods,svc -n "$NS" -o wide
