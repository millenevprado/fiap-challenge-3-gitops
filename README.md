# fiap-challenge-3-gitops

Repositório de GitOps do ToggleMaster (Tech Challenge Fase 3, item 3 —
Entrega Contínua & GitOps). Contém **apenas manifestos Kubernetes puros**
(sem Helm, sem Kustomize) para os 5 microsserviços que rodam no cluster EKS
provisionado em [`fiap-challenge-3-infra`](https://github.com/millenevprado/fiap-challenge-3-infra).

Nenhum `kubectl apply` deve ser rodado manualmente a partir da máquina de um
desenvolvedor em produção — este repositório é a fonte da verdade e será
sincronizado automaticamente pelo ArgoCD (próxima etapa: instalação do
ArgoCD no cluster e configuração do Sync apontando para este repositório).

## Estrutura

```
namespace.yaml              # namespace "togglemaster", único para as 5 apps
auth-service/
  deployment.yaml
  service.yaml
  configmap.yaml
  secret.yaml
flag-service/        (mesma estrutura)
targeting-service/   (mesma estrutura)
evaluation-service/  (mesma estrutura)
analytics-service/   (mesma estrutura)
```

Cada pasta de serviço é autocontida — quando o ArgoCD entrar em cena
(próxima etapa), cada uma vira uma `Application` independente apontando
para o seu próprio subdiretório, o que permite sincronizar/promover cada
microsserviço de forma isolada.

## Mapeamento de portas e dependências

| Serviço             | Porta | Depende de                                   |
|---------------------|-------|-----------------------------------------------|
| auth-service         | 8001  | RDS `authdb`                                  |
| flag-service         | 8002  | RDS `flagdb`, auth-service                    |
| targeting-service    | 8003  | RDS `targetingdb`, auth-service               |
| evaluation-service   | 8004  | ElastiCache (Redis), SQS, flag/targeting-svc  |
| analytics-service    | 8005  | SQS, DynamoDB (`ToggleMasterAnalytics`)       |

Todos expõem `/health` e usam esse caminho para os probes de
readiness/liveness. A comunicação entre serviços usa DNS interno do
cluster (ex.: `http://auth-service:8001`), nunca `localhost`.
