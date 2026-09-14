# fiap-challenge-3-gitops

Repositório de GitOps do ToggleMaster (Tech Challenge Fase 3, item 3 —
Entrega Contínua & GitOps). Contém **apenas manifestos Kubernetes puros**
(sem Helm, sem Kustomize) para os 5 microsserviços que rodam no cluster EKS
provisionado em [`fiap-challenge-3-infra`](https://github.com/millenevprado/fiap-challenge-3-infra).

Nenhum `kubectl apply` deve ser rodado manualmente a partir da máquina de um
desenvolvedor — este repositório é a fonte da verdade e é sincronizado
automaticamente pelo **ArgoCD**, instalado no cluster via Terraform
(`fiap-challenge-3-infra/modules/argocd`). Cada serviço tem sua própria
`Application` (também definida como código no repo de infra), apontando
para o subdiretório homônimo aqui, com sync automático (`prune` + `selfHeal`).

## Estrutura

```
namespace.yaml              # namespace "togglemaster", único para as 5 apps
auth-service/
  deployment.yaml
  service.yaml
  configmap.yaml
  secret.yaml                # ExternalSecret (ver seção "Secrets" abaixo)
flag-service/                # deployment, service, configmap, secret (ExternalSecret)
targeting-service/           # deployment, service, configmap, secret (ExternalSecret)
evaluation-service/
  deployment.yaml
  service.yaml
  configmap.yaml
  secret.yaml                # ExternalSecret (SERVICE_API_KEY)
  serviceaccount.yaml         # anotada com IAM role (IRSA)
analytics-service/
  deployment.yaml
  service.yaml
  configmap.yaml
  serviceaccount.yaml         # anotada com IAM role (IRSA) — sem secret.yaml,
                               # não precisa de credencial nenhuma
```

Cada pasta de serviço é autocontida — vira uma `Application` independente do
ArgoCD, o que permite sincronizar/promover cada microsserviço de forma
isolada.

## Secrets: nada de valor hardcoded no Git

Nenhum manifesto aqui contém senha, chave ou endpoint sensível em texto
puro. Em vez de `Secret` estático, os serviços que precisam de credenciais
usam **ExternalSecret** (CRD do [External Secrets
Operator](https://external-secrets.io), instalado no cluster via Terraform),
que busca o valor real no **AWS Secrets Manager** e materializa um `Secret`
comum no cluster:

| Serviço             | O que vem do Secrets Manager                          |
|---------------------|--------------------------------------------------------|
| auth-service        | `DATABASE_URL` (credenciais reais do RDS) + `MASTER_KEY` |
| flag-service        | `DATABASE_URL` (credenciais reais do RDS)               |
| targeting-service   | `DATABASE_URL` (credenciais reais do RDS)               |
| evaluation-service  | `SERVICE_API_KEY` (chave interna pra chamar flag/targeting-service) |
| analytics-service   | nenhum — acessa SQS/DynamoDB via IRSA, sem credencial   |

`evaluation-service` e `analytics-service` também têm um `serviceaccount.yaml`
anotado com `eks.amazonaws.com/role-arn`: é **IRSA** (IAM Roles for Service
Accounts) — o pod assume a role do IAM automaticamente pelo seu token
projetado, então a AWS SDK (SQS/DynamoDB) nunca precisa de
`AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` estático.

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
cluster (ex.: `http://auth-service:8001`), nunca `localhost`. Todos os
Services são `ClusterIP` — nada é exposto publicamente; o desafio não pede
isso, e testes/demos são feitos via `kubectl port-forward`.

## Observação: schema do banco

Os `db/init.sql` de cada serviço (tabelas `api_keys`, `flags`,
`targeting_rules`) ainda são aplicados manualmente contra o RDS — nenhum
serviço roda migração automática no startup. Se o RDS for recriado do zero,
esse passo precisa ser refeito antes dos serviços conseguirem funcionar.
Fica como próximo passo formalizar isso como um `Job` com hook `PreSync` do
ArgoCD, rodando o `init.sql` automaticamente antes de cada sync.
