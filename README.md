# URL Shortener

A production-shaped URL shortener built to explore infrastructure as code, container orchestration, and CI/CD on AWS.

The application itself is deliberately simple — create a short link, follow it. The interesting parts are everything around it: the infrastructure is defined entirely in Terraform, deploys are automated through GitHub Actions with no stored credentials, and the read path is cached with measured results.

---

## Architecture

```
                          Internet
                              │
                              ▼
                ┌─────────────────────────┐
                │  Application Load       │   public subnets (2 AZs)
                │  Balancer :80           │
                └─────────────────────────┘
                              │
              ┌───────────────┴───────────────┐
              ▼                               ▼
     ┌─────────────────┐            ┌─────────────────┐
     │ Fargate task 1  │            │ Fargate task 2  │   private subnets
     │ app :3000       │            │ app :3000       │
     └─────────────────┘            └─────────────────┘
              │                               │
              ├───────────────┬───────────────┤
              ▼               ▼               ▼
      ┌──────────────┐ ┌────────────┐ ┌──────────────┐
      │ ElastiCache  │ │    RDS     │ │ NAT Gateway  │
      │ Redis :6379  │ │ Postgres   │ │ (outbound)   │
      └──────────────┘ └────────────┘ └──────────────┘
```

**Request path:** the ALB is the only internet-reachable component. It health-checks tasks via `/health` and forwards traffic to healthy targets. Application tasks run in private subnets with no public IPs. Redis is checked first on redirects; a miss falls through to Postgres and populates the cache.

**Startup path:** ECS pulls the container image from ECR and fetches the database connection string from Secrets Manager using the task execution role, then injects it into the container. Outbound traffic from private subnets routes through a NAT gateway.

---

## Stack

| Layer | Choice |
|---|---|
| Application | Node.js, TypeScript, Express |
| Database | PostgreSQL on RDS |
| Cache | Redis on ElastiCache |
| Compute | ECS Fargate |
| Registry | ECR (immutable tags) |
| Networking | VPC, public/private subnets across 2 AZs, ALB |
| Secrets | AWS Secrets Manager |
| IaC | Terraform, remote state in S3 |
| CI/CD | GitHub Actions with OIDC |
| Observability | CloudWatch Logs |

---

## Design decisions

**Stateless application.** The app holds no state between requests — everything lives in Postgres. This is what makes horizontal scaling a one-line change (`desired_count`), because any task can serve any request without coordination.

**302 redirects, not 301.** Browsers cache permanent redirects aggressively and would stop hitting the server entirely. A temporary redirect keeps every visit flowing through the application, which preserves the ability to change link targets and to record click events later.

**Cache-aside with a TTL, not explicit invalidation.** Short code → URL mappings are immutable here: a link is never edited or deleted. Immutable data cannot go stale, so a TTL is sufficient and exists for memory hygiene rather than correctness. If links became editable, this would need to change to explicit invalidation on write — the mechanism is dictated by whether the underlying data can change, not by preference.

**The cache is best-effort.** Every Redis failure path falls back to Postgres. A cache should never be able to take down the service it accelerates.

**Immutable image tags.** ECR rejects overwriting a tag. Combined with tagging by commit SHA, every deployed image traces back to exactly one commit, and rollback is pointing the service at a previous tag rather than guessing what `latest` meant at a given time.

**Layered network security.** Three chained security groups: the ALB accepts traffic from the internet, the app accepts traffic only from the ALB's security group, and the database accepts traffic only from the app's security group. Rules reference security group identity rather than IP ranges, because Fargate task IPs change on every deploy. Security groups are not transitive — the load balancer cannot reach the database.

**Separate roles for infrastructure and application.** The ECS execution role pulls images and fetches secrets; the task role is what application code would use for AWS calls. Splitting them means the application cannot perform infrastructure operations even if compromised.

**No long-lived credentials in CI.** GitHub Actions authenticates via OIDC — GitHub presents a signed token identifying the repository, AWS verifies the signature and checks it against a trust policy, and issues temporary credentials scoped to the job. No AWS access keys are stored in the repository.

---

## Performance

Redis caching was added after deployment and measured before and after. Identical load against the same short link: 10,000 requests, 20 concurrent, redirects not followed.

| Percentile | Before | After | Change |
|---|---|---|---|
| p50 | 53.7 ms | 52.4 ms | −2% |
| p95 | 79.9 ms | 70.6 ms | −12% |
| **p99** | **141.5 ms** | **103.6 ms** | **−27%** |
| p99.9 | 372.2 ms | 162.9 ms | −56% |
| slowest | 661.4 ms | 248.8 ms | −62% |

The median barely moved, which is the expected result — roughly 50 ms of every measurement is network round-trip to `us-east-1` from the client, and no cache affects that. The improvement is concentrated in the tail, where database round-trips and connection pool contention under concurrency produced outliers.

The takeaway is that the cache made the service more *consistent* rather than faster on average. Adjusting for the fixed network floor, server-side p99 improved by roughly 40%.

*Measured from a client outside AWS, so absolute figures include internet latency. The comparison is valid because that component is constant across both runs.*

---

## CI/CD

Two concerns, deliberately separated by path filters:

**Application deploys** trigger on changes to `src/`, `Dockerfile`, or package files. The pipeline builds the image, tags it with the commit SHA, pushes to ECR, registers a new ECS task definition revision with the new image, and updates the service. The job does not pass until ECS reports the new tasks stable.

**Infrastructure changes** are applied through Terraform separately. Application code changes far more frequently than infrastructure, and a failed application deploy has a much smaller blast radius than a failed infrastructure change — they warrant different triggers and different levels of scrutiny.

---

## Running locally

```bash
docker compose up --build
```

Starts the application and Postgres together. Redis is optional locally — without `REDIS_URL` set, the cache layer is bypassed and all reads go to Postgres.

```bash
# create a short link
curl -X POST http://localhost:3000/shorten \
  -H "Content-Type: application/json" \
  -d '{"url":"https://example.com"}'

# follow it
curl -i http://localhost:3000/<code>
```

## Deploying

```bash
cd infra
terraform init
terraform apply
```

State is stored remotely in S3 with versioning, encryption at rest, and state locking enabled.

---

## Known gaps

Things deliberately left undone, and why:

- **No HTTPS.** Requires a registered domain and an ACM certificate.
- **No autoscaling.** Task count is fixed. Adding it is straightforward but there is no load pattern here that justifies it yet.
- **Short code collisions return a 500.** The database `UNIQUE` constraint correctly prevents duplicates, but the insert is not retried on conflict. At 62⁷ possible codes the probability is negligible for this scale; a retry loop would be the correct fix at higher volume.
- **`rejectUnauthorized: false` on the database TLS connection.** Traffic is encrypted, but the RDS certificate is not verified. Bundling the Amazon RDS CA certificate would close this.
- **Duplicate URLs produce distinct short codes.** This is intentional — it matches how most shorteners behave, and keeps per-link analytics separable.
