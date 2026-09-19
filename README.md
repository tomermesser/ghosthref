# ghosthref

A self-hosted server that catches bots two ways: fetching a path `robots.txt`
disallows, or following a link no human could click.

Architecture overview + diagram: `[ARCHITECTURE.md](ARCHITECTURE.md)`

## Repository layout

```
robots.txt        the source of truth — compiled into everything else, never hand-edited elsewhere
site/              the static homepage, served by nginx
bouncer/           the Node service that decides pass/throttle/block
  src/             server.js, robots.js, verdict.js, store.js
  test/            verify.js — the correctness harness (npm test)
  db/migrations/   Postgres schema
nginx/             nginx.conf — the auth_request edge, identical in Compose and Kubernetes
k8s/               Kubernetes manifests — bouncer, nginx-edge, secret, filebeat
ansible/           playbooks — k3s, data host (Postgres/Redis/Elasticsearch/Kibana), Jenkins
terraform/         VPC, security groups, EC2 instances, budget alarm
filebeat/          filebeat.yml — ships nginx's log into a plain, auto-mapped Elasticsearch index
kibana/            saved-objects.ndjson — the dashboard, exported as code
scripts/           one file, one job each — run any of them from the repo root:
  login.sh         writes AWS credentials from .env to ~/.aws/credentials, verifies them
  cost-check.sh    prints this month's AWS spend so far (make cost)
  destroy.sh       terraform destroy + a sweep for anything left behind (make nuke)
  kibana-setup.sh  creates the ghosthref-access data view in Kibana (run by make observability-up)
```



## Prerequisites

- Docker + Docker Compose, Node.js — local development, free.
- AWS CLI, Terraform, Ansible, `gh` CLI, a personal AWS account, an EC2 key pair — the AWS build.
- A `.env` file in the repo root (copy `.env.example`). Never committed.



## Running it locally

```bash
make up            # docker compose: nginx, bouncer, redis, postgres
make verify         # six crawler scenarios, precision/recall printed
```

Add observability (Elasticsearch + Kibana + Filebeat) on top:

```bash
make observability-up
```

Open `http://localhost:5601`, build a dashboard against the `ghosthref-access`
data view (created for you), then export it as code: Stack Management →
Saved Objects → select the dashboard + data view → Export → save as
`kibana/saved-objects.ndjson`.

## Deploying to AWS

**A. Infrastructure** (`terraform/`) — VPC, 3 security groups, 3 EC2 instances
(k3s server, data host, Jenkins), budget alarm:

```bash
aws ec2 import-key-pair --key-name ghosthref-key --public-key-material fileb://~/.ssh/id_ed25519.pub
cp .env.example .env             # fill in your AWS access key + secret
./scripts/login.sh

cd terraform
terraform init
terraform apply -var="my_ip_cidr=$(curl -s ifconfig.me)/32" -var="alert_email=you@example.com"
```

Note the 3 IPs from `terraform output`.



**B. Configuration** (`ansible/`) — installs k3s on one host, and
Postgres/Redis/Elasticsearch/Kibana + Jenkins on the other two:

```bash
cd ansible
cp inventory.ini.example inventory.ini   # fill in the 3 IPs
ansible all -m ping
ansible-playbook site.yml
```

Verify: `ssh ubuntu@<k3s_public_ip> 'kubectl get nodes'` → `Ready`.



**C. Deploy the app** (`k8s/`):

```bash
# First time only — nothing has pushed the bouncer image yet (Jenkins pushes
# commit-SHA tags later; this bootstraps `:latest` so the first deploy has
# something to pull). Build for amd64 explicitly if you're on Apple Silicon.
docker buildx build --platform linux/amd64 -t tomermes/ghosthref-bouncer:latest bouncer/ --push

kubectl create configmap ghosthref-config \
  --from-file=robots.txt=robots.txt --from-file=nginx.conf=nginx/nginx.conf --from-file=index.html=site/index.html \
  --dry-run=client -o yaml | kubectl apply -f -

cp k8s/secret.yaml.example k8s/secret.yaml               # fill in the data host's private IP
cp k8s/filebeat-daemonset.yaml.example k8s/filebeat-daemonset.yaml   # same
kubectl apply -f k8s/secret.yaml -f k8s/bouncer.yaml -f k8s/nginx-edge.yaml -f k8s/filebeat-daemonset.yaml
```

Verify: `kubectl get pods` → all `Running`; `curl http://<k3s_public_ip>/` → `200`.



**D. Kibana on AWS** — no public route; reach it through the k3s node, then
import the same `kibana/saved-objects.ndjson` from local dev:

```bash
ssh -L 5601:<data_private_ip>:5601 ubuntu@<k3s_public_ip>
```

Open `http://localhost:5601` → Stack Management → Saved Objects → Import.



**E. CI/CD** (`Jenkinsfile`) — push to `main` → test → compile `robots.txt`
into the ConfigMap → build → push (SHA-tagged) → deploy:

1. `ssh ubuntu@<jenkins_public_ip> 'sudo cat /var/lib/jenkins/secrets/initialAdminPassword'`
2. Open `http://<jenkins_public_ip>:8080` → install suggested plugins + **Docker Pipeline** → create your own admin user.
3. **Manage Jenkins → Credentials → System → Global** (not your personal store — jobs can't read from there) → add:
  - `dockerhub-creds` — Docker Hub access token with **Read & Write** scope, not your account password
  - `k8s-kubeconfig` — secret file: `ansible/kubeconfig`
  - `github-webhook-secret` — any random string
  - `data-host-ip` — the data host's private IP
4. New Item → Pipeline → check "GitHub hook trigger for GITScm polling" → Pipeline script from SCM → this repo, branch `main`.
5. Register the webhook:

```bash
gh api repos/tomermesser/ghosthref/hooks -f name=web \
  -f "config[url]=http://<jenkins_public_ip>:8080/github-webhook/" \
  -f "config[content_type]=json" -f "config[secret]=<same secret as github-webhook-secret>" \
  -F active=true -f "events[]=push"
```

Push a real change to `main` and watch it deploy on its own.

## Tearing down

```bash
make nuke
```

Runs `terraform destroy` and sweeps the region for anything left behind
(instances, volumes, Elastic IPs, NAT gateways, load balancers). Run it as
soon as you're done for the day — EBS volumes and Elastic IPs bill even while
an instance is stopped.