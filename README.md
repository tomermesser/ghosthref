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
  pair, for the AWS build (steps 7–13).
- A `.env` file in the repo root (copy `.env.example`). Never committed.
- No domain name needed — the site is reachable directly at the k3s node's
  public IP; a domain is a nice-to-have, never a requirement.

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
it can run workloads too; a second node would only earn its keep for
deliberately generated, sustained concurrent load, which isn't part of this
project's scope.

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

To provision everything from scratch in one command:
```
cd ansible
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
resource requests/limits (caps how much a misbehaving pod can take before
Kubernetes throttles it) and liveness/readiness probes on `/healthz`.

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

### Step 12: Shipping logs to the cluster

`k8s/filebeat-daemonset.yaml.example` — one DaemonSet, one node, so this only
ever runs once. It reads `/var/log/containers/nginx-edge-*.log` directly —
kubelet names each file after its pod and container, so filtering by
filename alone is enough to only ship nginx-edge's logs, no Kubernetes API
access or RBAC needed.

Real difference from local Compose worth knowing: Compose's Filebeat used
`type: log` because we bind-mounted a real file directly. Here it's
`type: container`, because the container runtime writes stdout in its own
line format first (containerd/CRI: `<timestamp> stdout F <line>`, not JSON —
different from Docker's own json-file format, but the same underlying
problem) — `type: container` strips that automatically before Filebeat ever
sees our JSON.

```
cp k8s/filebeat-daemonset.yaml.example k8s/filebeat-daemonset.yaml   # fill in the data host's private IP
kubectl apply -f k8s/filebeat-daemonset.yaml
```

Verify:
```
kubectl logs -l app=filebeat --tail=20   # no errors
curl -s "http://<data_public_ip>:9200/ghosthref-access/_count"   # climbing as real traffic arrives
```

Once real data is flowing, this is also when you build the Kibana dashboard
(if you haven't already against local Compose in step 6) and export it as
`kibana/saved-objects.ndjson` — the same file re-imports cleanly here since
both environments write to the same `ghosthref-access` index shape.

### Step 13: CI/CD

`Jenkinsfile` — Checkout → **Test** → **Compile robots.txt** into the
ConfigMap → Build → Push (SHA-tagged) → Deploy (`kubectl set image` +
restart nginx-edge so it picks up the new ConfigMap). Test runs against the
real data host directly (no throwaway containers — one less thing to spin up
and tear down) and gates everything after it, so a broken code or `robots.txt`
change never gets built, pushed, or deployed in the first place. Test IPs are
all in `10.0.0.0/8`, so this never collides with or disturbs real visitor data.

**One-time Jenkins setup** (same pattern as the previous project):
1. `ssh ubuntu@<jenkins_public_ip> 'sudo cat /var/lib/jenkins/secrets/initialAdminPassword'`
2. Open `http://<jenkins_public_ip>:8080`, install suggested plugins + **Docker Pipeline**, create your admin user.
3. Manage Jenkins → Credentials → add:
   - `dockerhub-creds` — Username with password (Docker Hub access token, not your account password)
   - `k8s-kubeconfig` — Secret file: upload `ansible/kubeconfig`
   - `github-webhook-secret` — Secret text: any random string
   - `data-host-ip` — Secret text: the data host's **private** IP (regenerate this credential every time the data host is recreated)
4. New Item → Pipeline → GitHub hook trigger → Pipeline script from SCM → this repo, branch `main`, script path `Jenkinsfile`.
5. Register the webhook:
```
gh api repos/tomermesser/ghosthref/hooks -f name=web \
  -f "config[url]=http://<jenkins_public_ip>:8080/github-webhook/" \
  -f "config[content_type]=json" \
  -f "config[secret]=<same secret as github-webhook-secret>" \
  -F active=true -f "events[]=push"
```

**First, sanity-check all 4 credentials at once**: open the job in Jenkins
and click **Build Now** — no need to push anything yet. Whichever stage goes
red tells you exactly which credential is wrong (bad Docker Hub token fails
at Push, bad kubeconfig fails at Compile/Deploy, wrong `data-host-ip` or a
missing SG rule fails at Test).

Then the actual demo moment: change one `Disallow` line in `robots.txt`, push
to `main`, watch all 6 stages go green, then break it on purpose (a rule the
test suite depends on) and confirm the **Test** stage fails the build before
anything gets built or deployed.

## Tearing down

```
make nuke
```
Runs `terraform destroy` and sweeps the region for anything left behind
(instances, volumes, Elastic IPs, NAT gateways, load balancers). Run it as soon
as you're done for the day — EBS volumes and Elastic IPs bill even while an
instance is stopped, and this project's entire budget assumes the AWS stack is
destroyed between sessions, not stopped.
