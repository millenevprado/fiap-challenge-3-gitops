# Runbook: auth-service HTTP 5xx rate > 5%

**Alerta:** `auth-service HTTP 5xx rate > 5%` (Grafana, pasta *ToggleMaster*)
**Severidade:** critical
**Dono:** time de plataforma ToggleMaster

## Impacto

O `auth-service` valida todas as chaves de API. Se ele falha:

- `flag-service` e `targeting-service` rejeitam as requisições;
- o `evaluation-service` não consegue montar a decisão (cache miss);
- clientes recebem erro ao avaliar flags.

## Automação (self-healing)

Quando o alerta dispara, **sem intervenção humana**:

1. Grafana envia o alerta para o contact point `togglemaster-oncall`.
2. **PagerDuty** abre o incidente.
3. **Slack** recebe a mensagem detalhada.
4. **AWS Lambda** `togglemaster-self-healing` recebe o webhook e executa
   `kubectl rollout restart deployment/auth-service`.
5. A Lambda espera o rollout terminar e posta o resultado no Slack.

Guardrails da automação:

- Só reinicia deployments da allow-list, no namespace `togglemaster`.
- Cooldown de 5 min: se o mesmo deployment já foi reiniciado há pouco, não
  reinicia de novo e avisa que precisa de humano (escala pelo PagerDuty).

## Diagnóstico manual (se o self-healing não resolver)

1. Dashboard **ToggleMaster - Saúde do Ecossistema**: painel "Taxa de erros 5xx".
2. Logs no Loki (Grafana > Explore > Loki):
   ```logql
   {k8s_namespace_name="togglemaster", service_name="auth-service"} |~ "(?i)erro|error"
   ```
3. Trace no New Relic (APM > auth-service > Distributed tracing), filtrando
   por erros: mostra se a falha é no handler ou na query ao Postgres.
4. Execução da automação:
   ```bash
   aws logs tail /aws/lambda/togglemaster-self-healing --since 30m --follow
   ```
5. Estado do deployment:
   ```bash
   kubectl -n togglemaster rollout status deployment/auth-service
   kubectl -n togglemaster get pods -l app.kubernetes.io/name=auth-service
   ```

## Ações comuns

| Causa | Ação |
|---|---|
| Processo em estado ruim (pool de conexões, memória) | `rollout restart` (já feito pela automação) |
| RDS `authdb` indisponível | Verificar o RDS no console AWS; restart não resolve |
| Deploy recente com bug | Reverter a tag da imagem no repo GitOps (ArgoCD sincroniza) |

## Encerramento

O alerta resolve sozinho quando a taxa de 5xx volta abaixo de 5%. O Grafana
manda o "resolved" para o PagerDuty (fecha o incidente) e para o Slack.
