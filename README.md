# Parcial II: Orquestación con Kubernetes y Simulación de AWS (Floci)
**Curso:** Infraestructuras Paralelas y Distribuidas (750023C)  
**Periodo:** 2026-2  
**Profesor:** Manuel Alejandro Pastrana Pardo, PhD  

---

## Estructura del Repositorio

- `k8s/`: Manifiestos YAML de Kubernetes para la base de datos (Secret, PVC, Deployment, Service) y el despliegue de la API.
- `api/`: Código fuente de la API REST, Dockerfile y endpoints de salud (`/health`).
- `floci-aws/`: Scripts de configuración de emulación AWS con Floci (IAM, S3, EKS y ECR).
- `docs-and-tests/`: Colección de Postman, evidencias en capturas de pantalla e informe técnico final.

---

## Registro de Comandos Ejecutados (Fase 1 - Integrante 1)

### 1. Inicialización y Verificación del Clúster Minikube
```powershell
# Arrancar el clúster con Docker driver
minikube start --driver=docker

# Verificar el estado de los componentes de Minikube
minikube status

# Verificar que el nodo principal esté en estado Ready
kubectl get nodes
```

### 2. Aislamiento de Recursos (Namespace)
```powershell
# Crear el namespace dedicado para el parcial
kubectl create namespace parcial2-app

# Validar creación del namespace
kubectl get namespaces
```

### 3. Gestión de Credenciales de Seguridad (Secret)
```powershell
# Crear Secret imperativo para evitar contraseñas en texto plano
kubectl create secret generic db-credentials --from-literal=POSTGRES_USER=postgres --from-literal=POSTGRES_PASSWORD=postgres -n parcial2-app

# Consultar Secret creado
kubectl get secrets -n parcial2-app
```

### 4. Almacenamiento Persistente (PVC - Punto Extra 1)
```powershell
# Aplicar el volumen persistente (1Gi)
kubectl apply -f .\k8s\db-pvc.yaml

# Verificar que el estado pase a Bound
kubectl get pvc -n parcial2-app
```

### 5. Despliegue de Base de Datos PostgreSQL y Servicio Interno
```powershell
# Desplegar PostgreSQL 15 y su Service ClusterIP (puerto 5432)
kubectl apply -f .\k8s\postgres-deployment.yaml

# Comprobar el estado del Pod (ContainerCreating -> Running 1/1)
kubectl get pods -n parcial2-app

# Comprobar el Service interno
kubectl get svc -n parcial2-app
```

---

## Parámetros de Conexión Interna (Para Integrantes 2 y 3)

| Parámetro | Valor Configurado |
| :--- | :--- |
| **Namespace** | `parcial2-app` |
| **DNS Interno K8s** | `postgres-service.parcial2-app.svc.cluster.local:5432` |
| **Nombre de BD** | `parcialdb` |
| **Secret Requerido** | `db-credentials` (`POSTGRES_USER` / `POSTGRES_PASSWORD`) |
| **Volumen** | `postgres-pvc` montado en `/var/lib/postgresql/data` |

---

## Comandos Útiles para Pruebas y Depuración

```powershell
# Port-forward para conectar DBeaver localmente a PostgreSQL
kubectl port-forward svc/postgres-service 5432:5432 -n parcial2-app

# Monitorear pods en tiempo real
kubectl get pods -n parcial2-app -w

# Ver logs detallados del pod de la BD
kubectl logs -l app=postgres -n parcial2-app
```