.PHONY: up down verify observability-up observability-down logs cost nuke

up:
	docker compose up -d --build

down:
	docker compose down -v

logs:
	docker compose logs -f nginx bouncer

verify:
	docker compose exec -T bouncer npm test

observability-up:
	docker compose -f docker-compose.yml -f docker-compose.observability.yml up -d --build
	./scripts/kibana-setup.sh

observability-down:
	docker compose -f docker-compose.yml -f docker-compose.observability.yml down -v

cost:
	./scripts/cost-check.sh

nuke:
	./scripts/destroy.sh
