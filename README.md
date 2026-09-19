# ghosthref

A self-hosted web server that classifies automated traffic by catching two
things: clients that fetch paths their own `robots.txt` group forbids, and
clients that follow links no human could possibly have clicked.

Architecture overview + diagram: [`ARCHITECTURE.md`](ARCHITECTURE.md)
Design doc: [`docs/specs/2026-09-15-ghosthref-design.md`](docs/specs/2026-09-15-ghosthref-design.md)

Final DevOps project — a personal AWS bill, not a lab-sponsored account. Budget
is $15 total and the AWS stack is only ever up for ~3 days; see the design doc
and the cost sections below before running anything against real AWS.

## Repository layout

```
robots.txt              the source of truth — compiled into everything else, never hand-edited elsewhere
site/                    the static homepage, served by nginx
bouncer/                 the Node service that decides pass/throttle/block
  src/                   server.js, robots.js, verdict.js, store.js
  test/                  verify.js — the correctness harness (npm test)
  db/migrations/         Postgres schema
nginx/                   nginx.conf — the auth_request edge, identical in Compose and Kubernetes
filebeat/                filebeat.yml — ships nginx's log into a plain, auto-mapped Elasticsearch index
scripts/                 all bash automation lives here — one file, one job each
docs/specs/              design docs, one per major decision
```

## Prerequisites

- Docker + Docker Compose, Node.js, for local development (steps 1–6, free).
- AWS CLI, Terraform, Ansible, a personal AWS account, and an existing EC2 key
  pair, for the AWS build (steps 7–14).
- A `.env` file in the repo root (copy `.env.example`). Never committed.
- A domain name, and the pre-launch canary-baseline screenshots (see
  `docs/canary-baseline.md`, added in step 6) taken **before** DNS resolves —
  that control cannot be recreated afterward.

## Steps

This README is filled in step by step as the project is built, in the same
verifiable, run-it-for-real style as the previous class project
(`aws-kubernetes`). Each heading below is added by its own commit.

### Step 1: Repo skeleton
`.gitignore`, `.env.example`, this README, the design spec, and the Makefile.

### Step 2: robots.txt and the static site
*(added in `02-robots-and-site`)*

### Step 3: The bouncer service
*(added in `03-bouncer`)*

### Step 4: Local vertical slice
*(added in `04-compose-stack`)*

### Step 5: Simulator and test harness
*(added in `05-simulator`)*

### Step 6: Local observability
*(added in `06-local-observability`)*

### Step 7: AWS infrastructure

One VPC, one public subnet, three EC2 instances (k3s server, data host,
Jenkins), three security groups, and a $10 budget alarm. See
`docs/specs/2026-09-15-ghosthref-design.md` for why it's a single AZ with no
private subnet or ALB — both were cut on cost, not by accident. k3s runs as a
single node — its server isn't tainted the way kubeadm's control-plane is, so
it can run workloads too; a second node would only earn its keep once we're
deliberately load-testing HPA, which isn't a graded requirement here.

**One-time setup, before the first `terraform apply`:**
```
aws ec2 import-key-pair --key-name ghosthref-key \
  --public-key-material fileb://~/.ssh/id_ed25519.pub
cp .env.example .env   # fill in your AWS access key + secret
./scripts/login.sh
```

**Then:**
```
cd terraform
terraform init
terraform apply -var="my_ip_cidr=$(curl -s ifconfig.me)/32" -var="alert_email=you@example.com"
```

Verify — three public IPs printed as outputs, and each one reachable:
```
ssh -i ~/.ssh/id_ed25519 ubuntu@<k3s_server_public_ip>
```

### Step 8: Teardown and cost control
*(added in `08-teardown`)*

### Step 9: k3s cluster

One playbook, one node: it installs k3s with Traefik disabled (nginx is our
own ingress) and ServiceLB left on (that's what gives `type: LoadBalancer` a
real port 80 with no cloud load balancer). k3s doesn't taint its server the
way kubeadm does, so this single node is both brain and worker. k3s's
kubeconfig hardcodes `127.0.0.1`, so the playbook rewrites it to the server's
private IP before fetching it — that copy is what Jenkins uses as a
credential later.

```
cd ansible
cp inventory.ini.example inventory.ini   # fill in the 3 IPs from `terraform output`
ansible all -m ping
ansible-playbook playbooks/01-k3s.yml
```

Verify — the node `Ready`, run over SSH since kubectl isn't exposed to the operator directly:
```
ssh -i ~/.ssh/id_ed25519_personal ubuntu@<k3s_server_public_ip> 'kubectl get nodes'
```

### Step 10: Data host and Jenkins

Two playbooks. `02-data.yml` installs Postgres, Redis, Elasticsearch
and Kibana on the data host — same choices as local Compose (no ILM, no
geoip, ES security disabled) since the SG restricting 5432/6379/9200 to the
k3s node only is the real boundary here too, not TLS. `03-jenkins.yml` is
close to a straight copy of the previous project's — Jenkins doesn't care
what app it's deploying.

**One-time:** the Postgres tasks need a collection not in Ansible core:
```
cd ansible
ansible-galaxy collection install -r requirements.yml
```

**Then, to provision everything from scratch in one command:**
```
ansible-playbook site.yml
```

Verify:
```
ssh -i ~/.ssh/id_ed25519_personal ubuntu@<data_public_ip> \
  'sudo -u postgres psql -d ghosthref -c "\dt"'   # the violations table exists
curl -s -o /dev/null -w '%{http_code}\n' http://<data_public_ip>:5601
# 302 (redirect to Kibana's login-less setup page) — reachable directly,
# no SSH tunnel needed, since data-sg already opens 5601 to your own IP
```

### Step 11: Kubernetes manifests

`k8s/bouncer.yaml` and `k8s/nginx-edge.yaml` — Deployment + Service each, with
resource requests/limits (bouncer's `requests.cpu` is what the HPA in step 12
measures against) and liveness/readiness probes on `/healthz`.

**No static ConfigMap file** — it's generated from the real source files, the
same command Jenkins will run on every merge in step 14, so there's never a
second copy of `robots.txt`/`nginx.conf`/the site to drift out of sync:
```
kubectl create configmap ghosthref-config \
  --from-file=robots.txt=robots.txt \
  --from-file=nginx.conf=nginx/nginx.conf \
  --from-file=index.html=site/index.html \
  --dry-run=client -o yaml | kubectl apply -f -
```

**The Secret is a template** (`k8s/secret.yaml.example`), same pattern as
`.env.example` — copy it, fill in the data host's *private* IP, apply:
```
cp k8s/secret.yaml.example k8s/secret.yaml   # then edit it
kubectl apply -f k8s/secret.yaml
kubectl apply -f k8s/bouncer.yaml -f k8s/nginx-edge.yaml
```

Verify:
```
kubectl get pods                 # 4 pods (2 bouncer + 2 nginx-edge), all Running, 1/1 Ready
kubectl get svc nginx-edge       # EXTERNAL-IP assigned (ServiceLB)
curl http://<EXTERNAL-IP>/       # 200, the homepage
```

### Step 12: Autoscaling
*(added in `12-k8s-autoscaling`)*

### Step 13: Shipping logs to the cluster
*(added in `13-filebeat`)*

### Step 14: CI/CD
*(added in `14-jenkins-pipeline`)*

## Tearing down

```
make nuke
```
Runs `terraform destroy` and sweeps the region for anything left behind
(instances, volumes, Elastic IPs, NAT gateways, load balancers). Run it as soon
as you're done for the day — EBS volumes and Elastic IPs bill even while an
instance is stopped, and this project's entire budget assumes the AWS stack is
destroyed between sessions, not stopped.
