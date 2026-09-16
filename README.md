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
*(added in `07-terraform`)*

### Step 8: Teardown and cost control
*(added in `08-teardown`)*

### Step 9: k3s cluster
*(added in `09-ansible-k3s`)*

### Step 10: Data host and Jenkins
*(added in `10-ansible-services`)*

### Step 11: Kubernetes manifests
*(added in `11-k8s-manifests`)*

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
