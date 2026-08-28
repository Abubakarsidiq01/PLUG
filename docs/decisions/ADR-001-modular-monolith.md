# ADR-001: Use a modular monolith for V1

- Status: Accepted
- Date: 2026-08-28

## Context

PLUG has two engineers and must prove a connected one-zone product before optimizing independent deployment or scale.

## Decision

Use one Java 21 / Spring Boot 3 application with explicit internal domain packages and one deployment.

## Consequences

Development, deployment, tracing, and transactions remain simple. Domain boundaries must still be reviewed. Kafka, Kubernetes, and microservices are out of V1 scope and require a new ADR.

## Revisit when

Measured scale, fault isolation, or independent deployment needs justify the operational cost.
