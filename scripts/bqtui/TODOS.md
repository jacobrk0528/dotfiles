# bqtui — potential additions

Ideas that fit the existing shell (a CLI/REST call feeding a tree, a tab,
or the results grid). Roughly ordered by expected payoff for day-to-day
BigQuery work. Dataform and Cloud Storage are already in.

## BigQuery

- [ ] **Scheduled queries** (`bq ls --transfer_config`, `bq mk --transfer_config`): list schedules with last/next run and status, run now, open the SQL in a tab.
- [ ] **Jobs pane** (`bq ls -j --all`): recent jobs across the project with user, bytes, duration, state, errors; open any job's SQL; cancel running jobs.
- [ ] **Data Transfer Service** (`bq ls --transfer_config` / `--transfer_run`): the Ads, Shopify, Attentive feeds — last run, next run, failures, run history.
- [ ] **INFORMATION_SCHEMA reports**: built-in queries for table storage/cost, slot usage by user, most expensive queries this month, unused tables.
- [ ] **Autocomplete**: table and column names from the explorer cache (Ctrl+Space).
- [ ] **Query parameters**: detect `@param` and prompt for values (`--parameter=` on `bq query`).
- [ ] **Job history detail**: open a job from history/results with full stats and query plan stages.
- [ ] **Dataset/table management**: create dataset, copy/snapshot table, set expiration, edit description/labels, delete with confirmation.
- [ ] **Export results to GCS** (`EXPORT DATA` or `bq extract`) from the results pane.
- [ ] **Routines & models**: list UDFs, stored procedures, BQML models with their definitions.
- [ ] **Row-level filter/search inside results** (`/` in the results grid).
- [ ] **Multiple result sets** for script queries (tabs per statement).

## Dataform (beyond the current pane)

- [ ] Write access: edit a workspace file in the editor and commit/push (`workspaces:writeFile`, `:commit`, `:push`).
- [ ] Run a single action (invocation with `includedTargets`) and "run with dependencies".
- [ ] Show an action's dependency graph as an indented tree.
- [ ] Watch a running invocation with live per-action state in a tab.
- [ ] Trigger release/workflow configs and edit cron schedules.

## Cloud Storage (beyond the current pane)

- [ ] Upload a local file / results export straight to a bucket.
- [ ] Delete, rename/move, and copy objects with confirmation.
- [ ] Signed URL generation (`gcloud storage sign-url`).
- [ ] Bucket metadata: lifecycle rules, IAM, size summary (`gcloud storage du`).
- [ ] Parquet/Avro schema preview via a temporary external table dry run.

## Other Google Cloud surfaces

- [ ] **Cloud Logging** (`gcloud logging read`): tail BigQuery audit logs or any filter in a tab.
- [ ] **Cloud Scheduler / Cloud Run jobs** (`gcloud scheduler jobs`, `gcloud run jobs`): list, trigger, and watch ETL entry points.
- [ ] **Pub/Sub** (`gcloud pubsub`): topics, subscriptions, peek messages.
- [ ] **Secret Manager** (`gcloud secrets`): read-only viewer with reveal-on-demand.
- [ ] **IAM** (`gcloud projects get-iam-policy`, dataset ACLs): who can access what.
- [ ] **Billing dashboard**: cost by service/day from the existing `Billing.gcp_billing_export_*` tables.
- [ ] **Cloud SQL** (`gcloud sql`): instances and a psql/mysql passthrough.
- [ ] **Composer / Airflow** (`gcloud composer environments`): DAG list and run states.
- [ ] **Dataplex / Data Catalog**: search across projects by table/column name and tags.

## App polish

- [ ] Config editor overlay (max rows, export dir, regions, theme).
- [ ] Theme from `quickshell/theme.json` so it matches the rest of the desktop.
- [ ] Resizable panes (drag the divider, or `<`/`>` keys).
- [ ] Split view: two query tabs side by side.
- [ ] Notifications via `ntfy` when a long query finishes while the terminal is unfocused.
