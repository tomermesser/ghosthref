.PHONY: up down verify observability-up observability-down logs cost nuke

## Local app stack (added in step 04-compose-stack)
up:
	docker compose up -d --build

down:
	docker compose down -v

logs:
	docker compose logs -f nginx bouncer

## Correctness harness (added in step 05-simulator)
verify:
	docker compose exec -T bouncer npm test

## Local observability override (added in step 06-local-observability)
observability-up:
	docker compose -f docker-compose.yml -f docker-compose.observability.yml up -d --build
	./scripts/kibana-setup.sh

observability-down:
	docker compose -f docker-compose.yml -f docker-compose.observability.yml down -v

## AWS cost control (added in step 08-teardown)
cost:
	./scripts/cost-check.sh

nuke:
	./scripts/destroy.sh
