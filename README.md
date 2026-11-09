# Parcial II: Orquestación con Kubernetes y Simulación de AWS (Floci)
**Curso:** Infraestructuras Paralelas y Distribuidas (750023C)  
**Periodo:** 2026-2  
**Profesor:** Manuel Alejandro Pastrana Pardo, PhD  

---

## Estructura del Repositorio

- `k8s/`: Manifiestos YAML de Kubernetes, numerados en orden de aplicación (`00-namespace` → `04-postgres-deployment`). Los de la API se agregan a continuación (`05-...`).
- `scripts/`: Scripts de despliegue y de evidencia (`deploy-db.sh`, `test-persistencia.sh`, `dump-db.sh`).
- `api/`: Código fuente de la API REST, Dockerfile y endpoint de salud (`/health`).
- `floci-aws/`: Scripts de emulación AWS con Floci (IAM, S3, EKS y ECR).
- `docs-and-tests/`: Colección de Postman, evidencias e informe final.

---

## Fase 1 - Integrante 1: Infraestructura base y almacenamiento persistente

### 1. Instancia EC2
| Parámetro | Valor |
| :--- | :--- |
| AMI | Ubuntu Server 24.04 LTS |
| Tipo | t3.medium o superior (Minikube exige mínimo 2 vCPU y 2 GB RAM; con Floci en la misma máquina, t3.large) |
| Disco | 20 GB gp3 o más |
| Security Group | SSH (22) desde la IP del grupo |

### 2. Instalación de Docker, kubectl y Minikube
```bash
# Docker
sudo apt-get update && sudo apt-get install -y docker.io conntrack
sudo usermod -aG docker $USER && newgrp docker

# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Minikube
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube

# Versiones (evidencia)
docker --version && kubectl version --client && minikube version
```

### 3. Iniciar el clúster
```bash
minikube start --driver=docker
minikube status
kubectl get nodes
```

### 4. Desplegar la capa de base de datos
```bash
git clone https://github.com/CarlossVillamil/parcial2-infra-paralelas-distri.git
cd parcial2-infra-paralelas-distri
bash scripts/deploy-db.sh
```
El script aplica, en orden:

| Archivo | Recurso | Propósito |
| :--- | :--- | :--- |
| `00-namespace.yaml` | Namespace `parcial2-app` | Aislar todos los recursos del parcial |
| `01-db-secret.yaml` | Secret `db-credentials` | Credenciales fuera del Deployment |
| `02-db-pv.yaml` | PersistentVolume `postgres-pv` (1Gi, hostPath `/data/postgres-pv`, Retain) | **Punto extra 1** |
| `03-db-pvc.yaml` | PersistentVolumeClaim `postgres-pvc` | **Punto extra 1** (reemplaza `emptyDir`) |
| `04-postgres-deployment.yaml` | Deployment `postgres` + Service ClusterIP `postgres-service` | PostgreSQL 15 con probes `pg_isready` y estrategia `Recreate` |

### 5. Evidencia de persistencia (Punto Extra 1)
```bash
bash scripts/test-persistencia.sh
```
Inserta un registro, borra el Pod, espera a que Kubernetes lo recree y vuelve a consultar: el registro sigue ahí porque vive en el PV y no en el contenedor.

> El PV es `hostPath` dentro del nodo de Minikube: los datos sobreviven a reinicios y borrados del Pod, y a `minikube stop/start`, pero **no** a `minikube delete`. En AWS real se usaría un volumen EBS con el driver CSI.

### 6. Respaldo para S3 (insumo del Integrante 2)
```bash
bash scripts/dump-db.sh parcialdb_dump.sql
```

---

## Parámetros de conexión interna (para los Integrantes 2 y 3)

| Parámetro | Valor |
| :--- | :--- |
| **Namespace** | `parcial2-app` |
| **DNS interno** | `postgres-service.parcial2-app.svc.cluster.local:5432` |
| **Base de datos** | `parcialdb` |
| **Secret** | `db-credentials` (`POSTGRES_USER` / `POSTGRES_PASSWORD`) |
| **Volumen** | PV `postgres-pv` ← PVC `postgres-pvc`, montado en `/var/lib/postgresql/data` |

---

## Comandos útiles

```bash
# Conectar un cliente SQL local a PostgreSQL
kubectl port-forward svc/postgres-service 5432:5432 -n parcial2-app

# Monitorear pods en tiempo real
kubectl get pods -n parcial2-app -w

# Logs de la BD
kubectl logs -l app=postgres -n parcial2-app

# Estado del almacenamiento
kubectl get pv,pvc -n parcial2-app
```
