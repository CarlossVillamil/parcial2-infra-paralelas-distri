# Fase 2: Floci (Integrante 2)

Todos los scripts se ejecutan **desde la raiz del repo, en la EC2**, en este orden:

| Script | Seccion del informe | Que hace |
| :--- | :--- | :--- |
| `01-start-floci.sh` | 6.1 | Red `floci-net`, contenedor Floci con IAM enforcement, AWS CLI v2 |
| `02-iam.sh` | 6.2 | Usuario `parcial2-operator`, rol `eks-role`, politica `parcial2-least-privilege`, prueba negativa |
| `03-s3.sh` | 6.3 | Bucket `parcial2-backups` con `k8s/` y un dump fresco de la BD |
| `04-eks.sh` | 6.4 | Cluster `parcial2-eks` (k3s), nginx, node group de 2 nodos vs 1 nodo real |
| `05-ecr.sh` | 6.5 | Imagen de la API al ECR y Pod en el EKS; reproduce los problemas de DNS y HTTP/HTTPS y aplica la solución |

- `env.sh`: endpoint y credenciales admin publicas del emulador (`test/test`).
- Las claves del operador se guardan en `~/.floci/operator.env` (fuera del repo). **No las subas a git.**
- `kubectl-eks.sh`: kubectl contra el EKS de Floci usando `~/.kube/floci-eks`; el contexto `minikube` nunca cambia.
- `iam-policy.json`: sin `"*"`. `iam-policy-ecr-auth.json` es la unica excepcion
  (`ecr:GetAuthorizationToken` no admite restriccion por recurso en AWS) y solo se usa en el paso ECR.