#!/usr/bin/env bash
# Evidencia de balanceo de carga y tolerancia a fallos (Seccion 5).
# Requisito previo: correr "minikube tunnel" en otra terminal (pide sudo)
# para que api-service tenga EXTERNAL-IP asignada.
# Uso: bash scripts/test-tolerancia.sh   (tomar captura de toda la salida)
set -euo pipefail
NS=parcial2-app

echo "== 1. Service LoadBalancer =="
kubectl get svc -n "$NS" api-service -o wide

IP=$(kubectl get svc -n "$NS" api-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
if [ -z "$IP" ]; then
  echo "EXTERNAL-IP vacia: falta 'minikube tunnel' corriendo en otra terminal." >&2
  exit 1
fi
echo "EXTERNAL-IP detectada: $IP"

echo "== 2. Replicas activas antes de la prueba =="
kubectl get pods -n "$NS" -l app=parcial2-api -o wide

echo "== 3. 10 peticiones antes de eliminar una replica (columna = Pod que respondio) =="
for i in $(seq 1 10); do
  curl -s -o /dev/null -w "%{http_code} " "http://$IP/health"
  curl -s -D - -o /dev/null "http://$IP/health" | grep -i X-Pod-Name
done

echo "== 4. Eliminando una replica en caliente (kubectl delete pod) =="
POD_ELIMINADO=$(kubectl get pods -n "$NS" -l app=parcial2-api -o jsonpath='{.items[0].metadata.name}')
echo "Pod eliminado: $POD_ELIMINADO"
kubectl delete pod -n "$NS" "$POD_ELIMINADO" --wait=false

echo "== 5. 20 peticiones continuas durante la caida/reemplazo del Pod =="
for i in $(seq 1 20); do
  CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://$IP/health")
  POD=$(curl -s -D - -o /dev/null "http://$IP/health" | grep -i X-Pod-Name | tr -d '\r')
  echo "req $i -> http $CODE | $POD"
  sleep 1
done

echo "== 6. Estado final: Kubernetes ya reemplazo el Pod eliminado =="
kubectl get pods -n "$NS" -l app=parcial2-api -o wide

echo "== 7. Prueba de CRUD a traves del LoadBalancer (equivalente a Postman) =="
curl -s -i -X POST "http://$IP/estudiantes" \
  -H "Content-Type: application/json" \
  -d '{"nombre":"Prueba Tolerancia","email":"tolerancia@correounivalle.edu.co"}'
echo
curl -s -i "http://$IP/estudiantes"
