#!/usr/bin/env bash
# Despliega (o actualiza) la capa de base de datos en Minikube. Idempotente:
# no borra nada, asi que los datos del PV se conservan.
# Uso (desde la raiz del repo):  bash scripts/deploy-db.sh
set -euo pipefail
NS=parcial2-app

kubectl apply -f k8s/00-namespace.yaml
kubectl apply -f k8s/01-db-secret.yaml
kubectl apply -f k8s/02-db-pv.yaml
kubectl apply -f k8s/03-db-pvc.yaml
kubectl apply -f k8s/04-postgres-deployment.yaml

kubectl rollout status deployment/postgres -n "$NS" --timeout=180s
kubectl get pv,pvc -n "$NS"
kubectl get pods,svc -n "$NS" -o wide
