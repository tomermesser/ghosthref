# Architecture

What this repo builds, in one diagram, and which tool is responsible for which
part. See `README.md` for the runnable step-by-step build log, and
`docs/specs/2026-09-15-ghosthref-design.md` for the design rationale.

```mermaid
flowchart TD
    subgraph LOCAL["Local — docker compose (free)"]
        direction TB
        NGINX_L["nginx<br/>auth_request + JSON log"]
        BOUNCER_L["bouncer (Node)<br/>verdict()"]
        REDIS_L[("redis<br/>rules, counters, blocklist")]
        PG_L[("postgres<br/>violation history")]
        ES_L[("elasticsearch + kibana<br/>dashboard built + exported here")]
        NGINX_L -->|auth_request| BOUNCER_L
        BOUNCER_L <--> REDIS_L
        BOUNCER_L -.async write.-> PG_L
        NGINX_L -.filebeat.-> ES_L
    end

    GH["GitHub repo<br/>ghosthref"] -->|"webhook: POST /github-webhook/<br/>on push to main"| JENKINS

    subgraph TF["Terraform — terraform/"]
        direction TB
        VPC(["aws_vpc.ghosthref<br/>10.2.0.0/16"])
        SUB(["public subnet, single AZ"])
        IGW(["aws_internet_gateway"])
        RT(["aws_route_table<br/>0.0.0.0/0 → igw"])
        KSG(["k3s-sg<br/>22+80 from my IP<br/>+6443 from jenkins-sg"])
        DSG(["data-sg<br/>5432/6379/9200/5601 from k3s-sg only"])
        JSG(["jenkins-sg<br/>22+8080 from my IP<br/>8080 from GitHub webhook IPs"])
        SRV(["EC2: k3s-server (t3.small)"])
        DATA(["EC2: data host (t3.medium)"])
        JENK_EC2(["EC2: jenkins (t3.small)"])
        BUDGET(["aws_budgets_budget<br/>alert at $10"])

        VPC --> SUB --> RT
        IGW --> RT
        SUB --> KSG --> SRV & JENK_EC2
        SUB --> DSG --> DATA
    end

    subgraph ANSIBLE["Ansible — ansible/playbooks/"]
        direction TB
        P1["01-k3s.yml<br/>single node,<br/>--disable traefik"]
        P2["02-data.yml<br/>postgres + redis + elasticsearch + kibana"]
        P3["03-jenkins.yml<br/>docker + kubectl + jenkins"]
    end

    SRV -.provisioned by.-> P1
    DATA -.provisioned by.-> P2
    JENK_EC2 -.provisioned by.-> P3

    P1 --> K8S

    subgraph K8S["k3s cluster — single node (server + worker in one)"]
        direction TB
        EDGE["nginx-edge<br/>Deployment + Service (LoadBalancer :80)"]
        BOUNCER_K["bouncer<br/>Deployment + Service + HPA"]
        SIM["simulator<br/>Deployment (scale for load demo)"]
        FB["filebeat<br/>DaemonSet"]
        CM["ConfigMap: robots rules + nginx.conf + site"]
        SEC["Secret: postgres + elasticsearch creds"]
        EDGE -->|auth_request| BOUNCER_K
        CM -.mounted by.-> EDGE
        CM -.mounted by.-> BOUNCER_K
        SEC -.mounted by.-> BOUNCER_K
        FB -.ships logs from.-> EDGE
    end

    BOUNCER_K <-->|5432/6379| DATA
    FB -->|9200| DATA

    subgraph JENKINS["Jenkins EC2 — Jenkinsfile pipeline"]
        direction TB
        J1["Checkout"] --> J2["Test"] --> J3["Compile robots.txt<br/>→ ConfigMap + Postgres rules"] --> J4["Build<br/>docker build"] --> J5["Push<br/>docker push"] --> J6["Deploy<br/>kubectl set image"] --> J7["Verify<br/>run simulators, fail on<br/>any changed verdict"]
    end

    J5 -->|"tag: git short-SHA"| DH["Docker Hub<br/>ghosthref/bouncer"]
    J6 -->|"private IP :6443"| K8S
    DH -->|pulled by| K8S

    OP["Operator (you)"] -->|login.sh: .env → ~/.aws/credentials| TF
    OP -->|SSH, one-time Jenkins setup| JENK_EC2
    OP -->|make nuke: destroy + sweep| TF
```

## Who owns what

| Layer | Tool | Responsibility |
|---|---|---|
| Local development | **Docker Compose** | The entire app — nginx, bouncer, redis, postgres, and (in the observability override) elasticsearch + kibana + filebeat. Every dashboard is built and exported here, at zero cost, before anything touches AWS. |
| Cloud infrastructure | **Terraform** | VPC, one public subnet, IGW, route table, three security groups, three EC2 instances (all pinned to standard CPU credits), a Budget alarm. Local state (gitignored, solo/single-machine project) — `apply`/`destroy` are idempotent and reversible. |
| Node configuration | **Ansible** | One playbook installs k3s, single node, `--disable traefik`; one provisions the data host (Postgres, Redis, Elasticsearch, Kibana); one provisions Jenkins. Agentless (SSH), run from the operator's laptop against a manually-filled inventory. |
| Cluster orchestration | **k3s** | Single-binary Kubernetes; ServiceLB gives a `type: LoadBalancer` Service a real public IP on port 80 with no cloud load balancer to pay for. |
| Application definition | **kubectl YAML manifests** | Deployment + Service + ConfigMap + Secret + HPA per component (`k8s/*.yaml`). Only the image tag changes per deploy (`kubectl set image`), same as the previous project. |
| App packaging | **Docker + Docker Hub** | `bouncer/Dockerfile` and `webserver/Dockerfile`-equivalent for nginx-edge. Jenkins tags every build with the triggering commit's short SHA. |
| CI/CD | **Jenkins + GitHub webhook** | The only fully automated path from `git push` to a live rollout — and the one stage worth demoing: it compiles `robots.txt` into the ConfigMap and Postgres rules, then re-runs the six simulators against the deployed environment and **fails the build if any verdict changed**. |
| Observability | **Filebeat → Elasticsearch → Kibana** | Decoupled from the request path — if Elasticsearch is down, enforcement still works. No Logstash, no Grafana, no Prometheus. |
| Cost control | **`make nuke` / `make cost`** (`scripts/`) | `terraform destroy` plus a region-wide sweep for orphaned instances, volumes, EIPs, NAT gateways and load balancers. Verified to report zero survivors *before* the first `apply`, not after. |
| Secrets | **`.env` + `login.sh`** (AWS) / **Jenkins credentials store** (Docker Hub token, kubeconfig, webhook secret) | Nothing credential-bearing is ever committed. |

## Design principle carried through

Same discipline as the previous project: a short design spec before code, small
steps each run for real and verified against live output, one commit per working
checkpoint. The addition here is a hard cost ceiling — teardown (`make nuke`) is
built and verified *before* the first expensive resource exists, not bolted on
afterward. Anything environment-specific (`terraform.tfstate`,
`ansible/inventory.ini`, `kubeconfig`) is gitignored and regenerated per run.
