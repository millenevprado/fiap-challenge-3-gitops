# Runbook: auth-service HTTP 5xx rate > 5%

**Alerta:** `auth-service HTTP 5xx rate > 5%` (Grafana, pasta *ToggleMaster*)
**Severidade:** critical
**Dono:** time de plataforma ToggleMaster

## Impacto

O `auth-service` valida todas as chaves de API. Se ele falha:

- `flag-service` e `targeting-service` rejeitam as requisições;
- o `evaluation-service` não consegue montar a decisão (cache miss);
- clientes recebem erro ao avaliar flags.

## Notificação

Quando o alerta dispara, o Grafana envia para o contact point
`togglemaster-oncall`:

1. **PagerDuty** abre o incidente (severidade critical).
2. **Slack** recebe a mensagem detalhada (serviço, valor atual, runbook,
   dashboard).

## Ação imediata

O auth-service costuma voltar com um restart (processo em estado ruim, por
exemplo pool de conexões corrompido):

```bash
kubectl -n togglemaster rollout restart deployment/auth-service
kubectl -n togglemaster rollout status deployment/auth-service
```

Se não resolver, siga o diagnóstico abaixo.

## Diagnóstico

1. Dashboard **ToggleMaster - Saúde do Ecossistema**: painel "Taxa de erros 5xx".
2. Logs no Loki (Grafana > Explore > Loki):
   ```logql
   {k8s_namespace_name="togglemaster", service_name="auth-service"} |~ "(?i)erro|error"
   ```
3. Trace no New Relic (APM > auth-service > Distributed tracing), filtrando
   por erros: mostra se a falha é no handler ou na query ao Postgres.
4. Estado do deployment:
   ```bash
   kubectl -n togglemaster rollout status deployment/auth-service
   kubectl -n togglemaster get pods -l app.kubernetes.io/name=auth-service
   ```

## Ações comuns

| Causa | Ação |
|---|---|
| Processo em estado ruim (pool de conexões, memória) | `rollout restart` |
| RDS `authdb` indisponível | Verificar o RDS no console AWS; restart não resolve |
| Deploy recente com bug | Reverter a tag da imagem no repo GitOps (ArgoCD sincroniza) |

## Encerramento

O alerta resolve sozinho quando a taxa de 5xx volta abaixo de 5%. O Grafana
manda o "resolved" para o PagerDuty (fecha o incidente) e para o Slack.
