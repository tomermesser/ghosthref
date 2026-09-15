# Design: Ghosthref

## Context

Final DevOps project. Reuses the infrastructure patterns proved out in
`aws-kubernetes` (Terraform + Ansible + Kubernetes + Jenkins-on-merge) and puts a
real workload on top: a web server that turns `robots.txt` from an advisory file
into an enforced, observable policy.

**Hard constraint: this is a personal AWS bill, not a lab-sponsored account.**
Budget $15 total. The AWS stack lives ~3 days, then it is destroyed. Everything
below is designed around that.

## The idea

Two provable signals classify automated traffic without any fuzzy "good bot /
bad bot" judgment:

1. **Disallowed path fetch** — a request for a honeypot path listed in
   `robots.txt` and linked nowhere else on the internet proves the client read
   the rules and did the opposite.
2. **Invisible link follow** — the same honeypot path is also linked from the
   homepage HTML with `aria-hidden`, `tabindex="-1"` and off-screen positioning.
   No human input method reaches it; a client that arrives via this link is a
   naive crawler following every `href`.

The `Referer` header distinguishes the two: absent means "read robots.txt and
disobeyed," homepage URL means "never read robots.txt, just followed links."

## Verdict tiers

Four-way, not two-way — blocking the wrong tier is the main failure mode.

| Tier | Meaning | Action |
|---|---|---|
| `COMPLIANT` | Never touched a disallowed path | Serve normally |
| `USER_PROXY` | Violated, but declared identity is exempt by spec (`ChatGPT-User`, `Perplexity-User`, `Meta-ExternalFetcher`, `Google-Extended`, `Claude-User`) | Log only, never block |
| `NON_COMPLIANT` | Violated with no such excuse | Escalate: <5/hr warn, <20/hr throttle (429), ≥20/hr block 24h |
| `FORGED` | Future work — claims a verifiable operator, IP outside published ranges | Block immediately |

Run in shadow mode (log, enforce nothing) for the first day after go-live.

## Architecture

```
  LOCAL (free)
  docker compose: nginx · bouncer · redis · postgres
  + override: elasticsearch · kibana · filebeat

  AWS — one VPC, ~3 days, then destroyed
  ┌──────────────────────────────────────────────────────────────┐
  │  public-a (AZ a)                     public-b (AZ b)         │
  │  ┌─────────────┐   ┌───────────┐     ┌───────────┐           │
  │  │ k3s-server  │   │ jenkins   │     │ k3s-agent │           │
  │  │ t3.small    │   │ t3.small  │     │ t3.small  │           │
  │  └─────────────┘   └─────┬─────┘     └───────────┘           │
  │    k3s: nginx-edge · bouncer · simulator · filebeat           │
  │    Service type LoadBalancer → :80 (ServiceLB, no cloud LB)   │
  │                          │ 5432 / 6379 / 9200  (SG→SG only)   │
  │                    ┌─────▼──────┐                             │
  │                    │ data host  │ t3.medium + swap            │
  │                    │ PG · Redis │ ES · Kibana                 │
  │                    └────────────┘                             │
  └──────────────────────────────────────────────────────────────┘
        jenkins ──6443──▶ k3s-server         S3: terraform state
```

Request path: `Client → Nginx (auth_request) → Bouncer ←→ Redis/Postgres`.
Observability path is decoupled: `Nginx JSON log → Filebeat → Elasticsearch →
Kibana` — if Elasticsearch is down, enforcement still works.

## Decisions and why

| Decision | Choice | Reason |
|---|---|---|
| Kubernetes | **k3s**, not kubeadm | Runs the server on a `t3.small`; kubeadm's control plane wants 2GB before scheduling anything, forcing `t3.medium`. One playbook instead of four — flannel, metrics-server and a load-balancer controller ship built in. kubeadm was already demonstrated in the previous project. |
| Public entrypoint | `type: LoadBalancer` via k3s ServiceLB | A real Service object, a clean URL, $0. A cloud ALB would be ~$16/mo. |
| Always-on edge host | None | No split between on-demand and always-on — there is one 3-day window. |
| Subnets | Two public subnets, two AZs, no private subnet | Subnets are free, multi-AZ is free coverage. A private data host needs a NAT Gateway (~$33/mo) for no security benefit a strict SG doesn't already give. |
| Nginx in k8s | Own Deployment, `nginx.conf` in a ConfigMap, no Ingress | The identical `nginx.conf` runs in Compose and in Kubernetes. `ingress-nginx` forces auth through annotations and breaks the 401→429 throttle distinction. |
| Log shipper | Filebeat straight to Elasticsearch | No Logstash. ES's built-in `geoip` ingest processor does the enrichment. |
| Observability store | Elasticsearch + Kibana only | No Grafana, no Prometheus — they'd answer questions ES already answers. |
| Dashboards | Built locally in Docker, exported as saved objects, imported on the real cluster | The only things ever debugged on a running AWS meter are Terraform, the k3s install, Filebeat over the network, and Jenkins. |
| TLS | HTTP only | Mass scanners hit every public IPv4 on port 80 regardless. HTTPS is a 10-minute add-on if wanted later. |
| Data store split | Redis on the hot path, Postgres for history, Elasticsearch for search/dashboards | Verdict logic never does a synchronous Postgres or HTTP call — p99 budget is 5ms. |

## Cut from scope (and why)

- **LLM-ingestion canary finding** — needs months of crawl/index/train time, not
  days. Keep only the pre-launch zero-results screenshot as a baseline; report
  it as an ongoing measurement, not a result.
- **50–100 pages of site content** — cut to ~10. The larger number only served
  the wild-crawler research angle, which the 3-day window already limits.
- **Forged-identity check, ES alerting, deny-map cron** — named as future work.
- **Private subnet + NAT Gateway, ALB** — the right production shape, cut here
  purely on cost. Named as future work.

## Safety rails

- Shadow mode on day 1 of the live run.
- Permanent allowlist bypassing the whole pipeline (Googlebot, Bingbot).
- Kill switch: one Redis key forcing every verdict to `ALLOW`.
- Never block `USER_PROXY` — that traffic exists because a human just asked a
  question about the page.
- Limitation to state up front: counters are keyed by IP; CGNAT, mobile carriers
  and cloud NAT share IPs across many real users.

## Full plan

See `~/.claude/plans/so-i-need-to-shimmying-wozniak.md` for the 15-step build
order, budget breakdown, gotchas, and per-step verification commands.
