# Cloud Cost Tracker: Product Requirements Document

| | |
|---|---|
| Status | Draft v1 |
| Date | 2026-11-11 |
| Owner | `mt-securesail` (sole user) |
| Reference project | [`mt-securesail/rails-ecs-demo`](https://github.com/mt-securesail/rails-ecs-demo) (stack, pipeline, and security controls are mirrored from it) |

---

## 1. Summary

Cloud Cost Tracker is a small, single-user web dashboard that shows how much the AWS account has spent in the current
billing period, what the whole period is likely to cost, and which services the money is going to. It is meant to stay
open in a browser window while working on other AWS projects (mainly the `rails-ecs-demo` training app), so that
runaway or forgotten resources are noticed quickly.

It is built with the same stack, Terraform layout, CI/CD pipeline, and security controls as `rails-ecs-demo`, so
lessons and code carry over in both directions.

## 2. Goals and non-goals

### Goals

1. Show, on one page: today's date, the billing period start date, month-to-date charges, and the forecast total for the
   billing period.
2. Show month-to-date charges broken down by AWS service.
3. Compare the current month with the previous 3 complete months, in total and by service.
4. Show clearly how fresh each number is ("as of" times).
5. Update itself automatically, with no manual reloads, while the window stays open for days.
6. Cost very little to run, and almost nothing when switched off.
7. Match or exceed the security controls of `rails-ecs-demo`.

### Non-goals (v1)

- Alerts or notifications of any kind (AWS Budgets covers that if ever needed).
- Multiple users, signup, or roles.
- Multiple AWS accounts or per-account breakdowns.
- True real-time (minute-by-minute) cost data. AWS does not provide it (see section 5).
- Writing to AWS in any way. The app is strictly read-only against billing APIs.
- A database.

## 3. User and usage

- **One user** (the owner), on a laptop browser, with the tab left open during work sessions.
- Typical question the page answers at a glance: *"Did what I just did (or forgot to tear down) change my bill, and is
  this month on track?"*
- The app runs in the AWS Organization's **management account**, which is also where the training app runs. Cost data
  read from the management account covers the whole organization.

## 4. Functional requirements

Priority: **Must** = v1 is not done without it. **Should** = planned for v1, can slip. **Could** = later phase.

### 4.1 Dashboard (single page)

| ID | Requirement | Priority |
|---|---|---|
| F1 | Show **today's date** (the browser's local date). | Must |
| F2 | Show the **billing period start date**: the first day of the current calendar month, in UTC (AWS bills by UTC calendar month). | Must |
| F3 | Show **current charges**: month-to-date estimated charges, in USD, from CloudWatch `EstimatedCharges` (section 5). | Must |
| F4 | Show **estimated total for the billing period**: Cost Explorer month-to-date cost plus Cost Explorer's forecast for the rest of the month (section 6.3). | Must |
| F5 | Show a headline line at the top of the page: **"Costs last updated at <date/time>"**, using the most recent "as of" time across all data sources (section 5), in the browser's local time zone, plus a relative age (for example, "Costs last updated at Wed, Nov 11, 2026, 2:14 PM (2 h ago)"). | Must |
| F5a | Directly underneath the headline line, show the **per-figure "as of" times**: one line each for current charges (CloudWatch) and for the estimated total, by-service breakdown, and 3-month comparison (Cost Explorer), in the same format. | Must |
| F6 | Show a **by-service breakdown** of month-to-date cost: top 10 services by cost, sorted descending, with the remainder grouped as "Other". | Must |
| F7 | Show a **comparison table**: rows are services (same top 10 + Other), columns are the previous 3 complete months plus the current month to date, with a totals row. | Must |
| F8 | Show the **day of the billing period** ("Day 11 of 30") and month-to-date cost from the previous month at the same day, so the current number has context. | Should |
| F9 | If a data source has failed or its data is older than expected, keep showing the last good values with a visible **"stale" warning** and the age, rather than a blank or an error page. | Must |
| F10 | If the forecast is unavailable (common early in a month, when AWS has too little data), show "Forecast unavailable" and a clearly labeled **simple projection** instead (section 6.3). | Must |
| F11 | Show a short footer note that AWS cost data lags actual usage by several hours, and that the two sources (CloudWatch and Cost Explorer) can differ slightly. | Must |
| F12 | Show the app version (commit SHA), as in `rails-ecs-demo`. | Should |

### 4.2 Refresh behavior

| ID | Requirement | Priority |
|---|---|---|
| R1 | The page refreshes its data from the app's own JSON endpoint about **every 60 seconds** without a full page reload. Browser refreshes never call AWS directly. | Must |
| R2 | The backend fetches CloudWatch `EstimatedCharges` **every 30 minutes**. | Must |
| R3 | The backend fetches Cost Explorer month-to-date by service and the forecast **every 6 hours**. | Must |
| R4 | The backend fetches the previous 3 months by service **once a day**, since past months barely change. | Must |
| R5 | All fetches also run once **at app startup**, so a fresh task has data within a minute. | Must |
| R6 | Refresh intervals are configurable via environment variables, with the values above as defaults. | Should |
| R7 | At month rollover (UTC), the next scheduled fetch picks up the new period automatically. No manual action, no stale period on screen. | Must |
| R8 | A "Refresh now" control is **not** offered in v1, to keep Cost Explorer spending predictable. | n/a |

### 4.3 Later phases

| ID | Requirement | Priority |
|---|---|---|
| L1 | **"Currently running" panel**: list billable resources alive right now (EC2 instances, RDS instances, NAT gateways, load balancers, ECS services with running tasks, Elastic IPs), without pricing them. This is the near-real-time "did I forget to tear something down" signal. | Could (phase 4) |
| L2 | **Cognito login at the ALB** (an `authenticate-cognito` listener rule) in addition to the IP allowlist. | Could (phase 4) |
| L3 | A daily cost trend chart for the current month. | Could |
| L4 | **Other cost sources** (for example GCP, Azure, Okta, Salesforce). The app is named "Cloud Cost Tracker" so it can grow beyond AWS. Version 1 reads AWS only. | Could |

## 5. Data sources and freshness

AWS cost data is **not real time**. Usage is metered by each service and processed by AWS billing in batches.

| Source | Used for | AWS update frequency | Cost to read |
|---|---|---|---|
| CloudWatch metric `AWS/Billing` `EstimatedCharges` (dimension `Currency=USD`), us-east-1 only | F3 headline "current charges" | Several times a day (roughly every 4-8 h) | Effectively free at this volume |
| Cost Explorer `GetCostAndUsage` | F4 month-to-date part, F6, F7, F8 | At least daily; usually a few times a day | $0.01 per request |
| Cost Explorer `GetCostForecast` | F4 forecast part | Same as above | $0.01 per request |

**Expected Cost Explorer spend:** about 2 requests every 6 h plus 1-2 per day, or about **270-300 requests a month,
around $3/month**. Task restarts add about $0.03 each.

**"As of" times:**
- CloudWatch: the timestamp of the latest datapoint returned. This is when AWS last updated the number, not when the app
  fetched it.
- Cost Explorer: the time the app last fetched successfully. Cost Explorer does not report its own refresh time.

## 6. Calculation details

### 6.1 Billing period

- Period start = first day of the current month, 00:00 UTC. Period end (exclusive) = first day of next month, 00:00 UTC.
- All AWS queries use UTC dates. Only the display of "today" and "as of" times uses the browser's local time.

### 6.2 Current charges (F3)

- `GetMetricData` for `AWS/Billing` / `EstimatedCharges` / `Currency=USD` (no `ServiceName` dimension = account
  total), statistic `Maximum`, period 1 h (so the "as of" time is within an hour of AWS's update), over the last
  2 days. Use the most recent datapoint.
- The metric resets at the start of each month. A datapoint timestamped in the previous month must not be shown as the
  current month's charges. Show "No data yet this period" instead.
- Prerequisite: **"Receive CloudWatch billing alerts"** must be turned on in the management account
  (AWS Management Console → Billing and Cost Management → Billing preferences). Without it, the metric does not exist.

### 6.3 Estimated total for the period (F4, F10)

- Month-to-date: `GetCostAndUsage`, `TimePeriod` = period start to tomorrow (UTC), `Granularity=MONTHLY`,
  `Metrics=UnblendedCost`, `GroupBy=SERVICE`. Sum the groups. The same call feeds F6.
- Forecast: `GetCostForecast`, `TimePeriod` = today (UTC) to period end, `Metric=UNBLENDED_COST`,
  `Granularity=MONTHLY`. For the current month, AWS returns the forecast for the **whole month, actual costs to date
  included** (the same figure as "forecasted month end costs" in Billing and Cost Management). Estimated total =
  forecast mean, never less than month-to-date. Do **not** add month-to-date to it (findings log #4). On the last day
  of the month, estimated total = month-to-date.
- Fallback if the forecast call fails or AWS reports insufficient data: linear projection = month-to-date ÷ days
  elapsed × days in month, labeled **"Projection (simple)"**.
- The forecast's prediction interval (low/high) may be shown in small text. Should, not Must.

### 6.4 Comparison months (F7)

- One `GetCostAndUsage` call: `TimePeriod` = first day of the month 3 months ago to the current period start,
  `Granularity=MONTHLY`, `Metrics=UnblendedCost`, `GroupBy=SERVICE`.
- The top 10 services are chosen by **current month-to-date** cost. Services that only appear in earlier months fall into
  "Other". A service with no cost in a month shows "-".

### 6.5 Known differences between sources

CloudWatch `EstimatedCharges` and Cost Explorer can disagree by small amounts (different update times, and credits,
refunds, and tax can be applied differently). The page labels the headline figure as CloudWatch's estimate and the
breakdowns as Cost Explorer data, and does not try to reconcile them.

## 7. Architecture

### 7.1 Application

- **Ruby 3.4, Rails 8.1**, the same versions and conventions as `rails-ecs-demo`. Dockerfile follows the same pattern:
  base image pinned by digest, `apt-get upgrade`, non-root `appuser`, `/up` health check.
- **No database.** Data is cached in memory (`Rails.cache` memory store) in the single running task. A restart simply
  re-fetches (R5).
- **In-process scheduler.** Background refresh jobs run inside the Puma process using `Concurrent::TimerTask`
  (concurrent-ruby already ships with Rails), so no extra gem, queue, or database is needed. Each job catches and logs
  its own errors and never crashes the web process.
- **AWS SDK gems:** `aws-sdk-costexplorer` and `aws-sdk-cloudwatch`. Credentials come only from the ECS task role.
- **Frontend:** a server-rendered ERB page, plus one small JavaScript file (no inline scripts, no third-party CDNs)
  that polls `GET /summary.json` and updates the numbers in place.
- **Endpoints:** `GET /` (dashboard), `GET /summary.json` (cached data plus freshness metadata), `GET /up` (health).
  Nothing accepts user input that reaches AWS.
- **Tests:** unit tests for every calculation in section 6 (period boundaries, month rollover, last day of month,
  forecast fallback, stale detection, top 10 + Other grouping), using the AWS SDK's `stub_responses`. No test calls real
  AWS.

### 7.2 Infrastructure (Terraform in `infra/`, local state)

Mirrors `rails-ecs-demo/infra` file by file, with these differences:

| Area | Requirement |
|---|---|
| Naming | `project_name = "cloud-cost-tracker"`; region `us-east-1` (also where billing metrics and the Cost Explorer endpoint live). |
| GitHub OIDC provider | The account **already has** the `token.actions.githubusercontent.com` OIDC provider (created by `rails-ecs-demo`). Only one can exist per account, so this project must look it up with a `data` source and **must not** create it. This project creates only its own deploy role, trusted only for this repo's subject prefix. |
| ALB subnets | Place the ALB (and task) in **exactly 2** default-VPC subnets in different AZs, not all of them. This cuts the ALB's public IPv4 charges (about $3.60/month per address). |
| Domain and DNS | A general-use **training domain**, **`example-apps.com`**, is registered in **Route 53**, which creates the hosted zone. Terraform looks up the zone with a `data` source (it does not create or own it, so other training projects can add their own subdomains later), and manages only this app's record: an alias `A` record for **`cloud-cost-est.<domain>`** pointing to the ALB (IPv4 only; IPv6 would need a dual-stack ALB). The domain name is a variable. The weather app from `rails-ecs-demo` will use its own, separate domain and is not part of this one. |
| TLS | ACM certificate for `cloud-cost-est.<domain>`, DNS-validated by Terraform. HTTPS listener on 443 with a TLS 1.2/1.3 policy (`ELBSecurityPolicy-TLS13-1-2-2021-06` or newer). Port 80 listener only redirects to HTTPS. |
| Access | ALB security group allows 80/443 only from `allowed_cidrs` (your IP), as in the training app. |
| On/off switch | Variable `app_enabled` (default `true`). When `false`, Terraform removes the ALB, listeners, target group, ECS service, and DNS record. It keeps ECR, IAM roles, the cluster, the log group, the SSM parameter, the ACM certificate, and the task definition. Idle cost is then a few cents a month plus the $0.50 hosted zone. |
| Re-enable | When switched back on, the recreated ECS service must use the **latest** task definition revision in the family (looked up with a `data` source), not Terraform's placeholder revision, so the app comes back on the last deployed image without a redeploy. |
| Task role | Read-only: `ce:GetCostAndUsage`, `ce:GetCostForecast`, `cloudwatch:GetMetricData`. Nothing else. (Cost Explorer does not support resource-level permissions, so `Resource = "*"` is required for `ce:*`. Document it as an inline exception if a scanner flags it.) Phase 4 adds read-only `Describe*`/`List*` actions for L1. |
| ECR | Lifecycle policy keeping the last 10 images. Scan on push enabled. |
| Logs | CloudWatch log group, 14-day retention. |

### 7.3 CI/CD (GitHub Actions)

Same structure as `rails-ecs-demo`:

- `ci.yml`: `test` and `brakeman` jobs, on `pull_request` and `workflow_call`.
- `cd.yml`: on push to `main`, calls CI, then builds, pushes to ECR, and deploys to ECS via OIDC. Uses
  `concurrency: deploy-production` with `cancel-in-progress: false`.
- `container-scan.yml`: `trivy`, `grype`, `trivy-config` jobs (pinned binaries with verified checksums).
- `dependency-review.yml`.
- **New: on/off awareness.** If the ECS service does not exist (`app_enabled = false`), CD still builds and pushes the
  image, skips the ECS update with a clear notice, and succeeds.
- `zap.yml`: ZAP baseline scan of the app running on the GitHub runner, on every PR (required check). Copied from
  `rails-ecs-demo` (section 8.2, S5).
- `cd.yml` also gets a `zap-production` job after `deploy`, using a separate scan role (section 8.2, S6). Skipped when
  `app_enabled = false`.

## 8. Security requirements

### 8.1 Mirrored from `rails-ecs-demo` (all Must)

| Control | Detail |
|---|---|
| Public repo | `mt-securesail/cloud-cost-tracker` (public, so CodeQL and secret scanning are free). No account IDs, domain-specific secrets, `terraform.tfvars`, or state committed. |
| Branch ruleset `protect-main` | Require PR; block force-push and deletion; required checks: `test`, `brakeman`, `dependency-review`, `trivy`, `grype`, `trivy-config`, `zap`; code scanning gate on CodeQL (high or higher). |
| Secret scanning + push protection | On. |
| Dependabot | Alerts and security updates on; `dependabot.yml` for `docker` and `github-actions` with grouping and a 7-day cooldown. Add `bundler` version updates too. |
| CodeQL | Default setup, languages Ruby and GitHub Actions. |
| Brakeman | SARIF upload with category `brakeman`; job fails on any warning. |
| Container scanning | Trivy and Grype gates on fixable critical/high; exceptions in `.trivyignore.yaml` / `.grype.yaml` with reason and expiry. |
| IaC scanning | Trivy config on `infra/` and `Dockerfile`; inline exceptions with reason, decider, date, and review date. |
| Supply chain | Every action pinned to a full commit SHA with a version comment; scanners downloaded at pinned versions with checksum verification. |
| No stored AWS keys | GitHub → AWS via OIDC only. No AWS keys anywhere in GitHub. Role ARNs are GitHub *secrets* (only because they contain the account ID, which public logs must not show); everything else is repo variables. |
| Least-privilege IAM | Deploy role scoped to this project's ECR repo and roles; task role read-only billing (section 7.2). |
| Secrets | `SECRET_KEY_BASE` in SSM Parameter Store (SecureString), injected by ECS. Generated by Terraform as an ephemeral, write-only value, so it's never in Terraform state or plans and never passed in by hand. |
| `CLAUDE.md` | Same "how to talk to me" and safety rules (never push/merge to `main` or `terraform apply` without asking, experiments on branches, fake secrets only, public repo). |
| `docs/findings-log.md` | One row per finding: source, root cause, fix, regression check, link. |

### 8.2 New or stronger in this project

| ID | Control | Priority |
|---|---|---|
| S1 | **HTTPS only**, valid ACM certificate, HTTP→HTTPS redirect at the ALB. Removes the training app's HTTP listener exception. | Must |
| S2 | Rails `config.assume_ssl = true` and `config.force_ssl = true` (HSTS on), with `/up` excluded from the redirect so ALB health checks work. | Must |
| S3 | `config.hosts` restricted to `cloud-cost-est.<domain>` (plus the `/up` health check exclusion). | Must |
| S4 | **Security headers from day one**, copied from `rails-ecs-demo` (its rails-ecs-demo/PR #20, which fixed that app's ZAP findings): strict Content Security Policy (`default-src 'none'`, then only `'self'` for scripts, styles, images, fonts, and `connect-src`; `object-src`/`base-uri` `'none'`; `frame-ancestors 'none'`; per-request nonce for the page's `<style>` block; no inline scripts, no `unsafe-inline`/`unsafe-eval`, no third-party origins); `Permissions-Policy` disabling unused browser features; cross-origin isolation headers (COEP `require-corp`, COOP and CORP `same-origin`); `Cache-Control: no-store` on every response via middleware; unknown paths routed to an `ErrorsController#not_found` page so 404s also carry the headers. | Must |
| S5 | **ZAP baseline scan on every PR** (`zap.yml`, required check `zap`), copied from `rails-ecs-demo`: builds the image, runs it on the runner with a throwaway `SECRET_KEY_BASE`, and scans it with the official ZAP image pinned by digest. Passive only (crawl and inspect responses, no attack traffic). Nothing leaves the runner, and AWS isn't involved. Results go to the job summary and a `zap-report` artifact (no SARIF; ZAP findings are URLs, not code lines). For this app, the scan container also needs: background AWS fetching turned off (an env var such as `COST_FETCH_ENABLED=false`) so the runner never calls AWS, and the scan's hostname allowed through S3 (an env var such as `ALLOWED_HOSTS`). `assume_ssl` (S2) means plain HTTP inside the runner is treated as HTTPS, so HSTS and the redirect logic are still exercised. | Must |
| S6 | **ZAP scan of production after each deploy** (`zap-production` job in `cd.yml`), copied from `rails-ecs-demo`. It uses a **separate scan role** (`infra/zap_scan.tf`) that trusts only workflow runs on `main` (exact OIDC subject ending `:ref:refs/heads/main`), has a 1-hour maximum session, and can **only** add/remove inbound rules on the ALB security group. It can't deploy, and the deploy role can't open the firewall. The job adds the runner's IP (`/32`, port **443**, description `zap-scan-run-<run id>`) to the ALB security group, scans `https://cloud-cost-est.<domain>`, then always removes the rule (even on failure or cancel). Terraform removes leftover rules on the next apply. Skipped when `app_enabled = false`. | Must |
| S7 | **`.zap/rules.tsv`** shared by both scans, in the training repo's format. Start with that repo's already-fixed rules set to `FAIL` (10038 CSP, 10063 Permissions Policy, 90004 site isolation), since S4 implements them from the first commit, and 10049 (non-storable content) as `IGNORE` with its reason. Every `IGNORE` has a comment with the reason, the decider (GitHub username, not a real name), and a review date, and is logged in `docs/findings-log.md`. | Must |
| S8 | **Header regression tests** (`test/security/security_headers_test.rb`, copied and adapted), checking every header on `/`, `/up`, `/summary.json`, and a 404. They run in the required `test` job, so a change that drops a header can't merge. | Must |
| S9 | Logs never contain full AWS API responses or request credentials; log only counts, timings, and error classes. | Must |
| S10 | **Public Actions logs:** the repo is public, so its workflow logs are too. Mask the AWS account ID in every job that assumes an AWS role, and never print personal data (IP addresses other than the temporary runner's, emails, names). | Must |
| S11 | Keep the ZAP setup in step with `rails-ecs-demo`: when either repo improves its ZAP workflows, rules, or headers, port the change to the other. | Could |

### 8.3 Data sensitivity

The app displays spending amounts and AWS service names. It has no personal data, no customer data, and no write
access. The main risk is disclosure of spending patterns and of the fact that the account exists. That is why the IP
allowlist (and later Cognito, L2) and HTTPS are required even for a single user.

## 9. Non-functional requirements

| ID | Requirement |
|---|---|
| N1 | Dashboard loads in under 1 s from cache; `/summary.json` responds in under 200 ms. |
| N2 | Runs for weeks without a restart and without memory growth (cache holds only the latest results). |
| N3 | An AWS API failure never takes the page down (F9). Failed fetches retry at the next interval, with no tight retry loops that run up Cost Explorer charges. |
| N4 | Readable at a glance in a narrow side window (around 400 px wide) and on a full screen; supports light and dark mode. |
| N5 | Times and amounts are formatted consistently: USD with 2 decimals, dates as `Wed, Nov 11, 2026`. |

## 10. Running cost estimate (us-east-1)

| Item | Running 24/7 | Switched off (`app_enabled = false`) |
|---|---|---|
| ALB (base + minimal LCU) | ~$17/mo | $0 |
| ALB public IPv4 (2 addresses) | ~$7/mo | $0 |
| Fargate task (0.25 vCPU / 0.5 GB) | ~$9/mo | $0 |
| Task public IPv4 | ~$3.60/mo | $0 |
| Cost Explorer API | ~$3/mo | $0 |
| Route 53 hosted zone | $0.50/mo | $0.50/mo |
| ECR storage, logs, SSM, CloudWatch | < $1/mo | < $0.50/mo |
| **Total** | **~$40/mo** | **~$1/mo** |
| Domain registration (.com, Route 53) | ~$14/yr | ~$14/yr |

Prices change. Verify current pricing before relying on these figures.

## 11. Delivery phases

### Phase 0: Account and domain preparation (one-time, mostly AWS Management Console)
1. Register a general-use training domain in Route 53 (creates the hosted zone). The app will live at
   `cloud-cost-est.<domain>`.
2. Turn on "Receive CloudWatch billing alerts" in Billing preferences.
3. Confirm Cost Explorer is enabled (first-time enablement can take up to 24 h to show data).
4. Create the public GitHub repo `cloud-cost-tracker` and get its OIDC subject prefix.
5. Deferred (optional): install Docker Desktop for local image builds, scans, and running the production container.
   Not required, because GitHub Actions builds and scans every image. Revisit if waiting on CI round-trips becomes a
   problem.

### Phase 1: Pipeline and security skeleton
- A Rails "hello" page with `/up`, Dockerfile, Terraform (including HTTPS, domain, 2-subnet ALB, `app_enabled`), and all
  workflows and settings from section 8.1, *before* any cost features.
- Exit criteria: a PR shows every required check; merging deploys to `https://cloud-cost-est.<domain>`; HTTP redirects to HTTPS;
  switching `app_enabled` off and on works and the URL comes back with the latest image.

### Phase 2: Dashboard
- Requirements F1-F12 and R1-R7, with unit tests per section 7.1.
- Exit criteria: section 12 acceptance criteria pass.

### Phase 3: Dynamic scanning and hardening
- S1-S10 in place; both ZAP scans (PR and production) green, or findings logged and fixed; findings log up to date.

### Phase 4 (optional)
- L1 "Currently running" panel, L2 Cognito login, L3 trend chart, S11 keep ZAP aligned with the training repo.

## 12. Acceptance criteria (v1)

1. With the window left open, the numbers update on their own, and every AWS-sourced figure shows an "as of" time.
2. Today's date, the period start date (1st of the month), current charges, and estimated total all display, and the
   estimated total is greater than or equal to current month-to-date Cost Explorer cost.
3. The by-service table and the 3-month comparison show values matching Cost Explorer in the AWS Management Console
   (allowing for refresh timing).
4. Simulated failures (stubbed in tests) show stale warnings, and the forecast fallback works.
5. Over 24 h, the app makes no more Cost Explorer requests than the schedule in section 5 allows (verified from logs).
6. All required checks pass on `main`, the ZAP baseline passes, and the site is reachable only over HTTPS from an
   allowed IP.
7. `app_enabled = false` drops monthly cost to about $1, and re-enabling restores the same URL running the last deployed
   image.

## 13. Risks and open items

| Item | Notes |
|---|---|
| Workloads in the management account | AWS recommends keeping the Organization management account free of workloads and running apps in member accounts. Acceptable for a personal learning setup. If the training app later moves to a member account, this app can stay in the management account (where org-wide cost data lives) without changes. |
| Domain name | `example-apps.com` (registration submitted 2026-11-12), so the app URL is `https://cloud-cost-est.example-apps.com`. It is only a Terraform variable, and nothing else depends on it. Other training projects may add subdomains later. The production weather app uses its own separate domain. |
| Cost data lag | Inherent in AWS (section 5). L1 is the mitigation if the lag proves frustrating. |
| Source disagreement | CloudWatch vs. Cost Explorer differences (section 6.5) may confuse at first. Labeling is the mitigation. |
| Home IP changes | The IP allowlist breaks when your ISP changes your address. Update `allowed_cidrs` and run `terraform apply`. L2 (Cognito) would allow loosening the allowlist later. |
| Cost Explorer pricing | $0.01/request today. If it changes, adjust the R3/R4 intervals. |
