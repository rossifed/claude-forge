---
name: data-validation
description: "Validate financial data integrity across pipeline layers (raw → master) and against external public sources. Source-agnostic methodology — works with any data provider."
user-invocable: true
argument-hint: "domain (e.g. 'segment estimates', 'fundamentals', 'market data') and optional company/currency filter"
---

# Data Validation

Source-agnostic methodology for validating financial data integrity. Ensures that transformations (scaling, currency, mapping, deduplication) preserve data from source to master, regardless of the upstream provider.

## When this skill activates

- After loading a new dataset or completing a full reload
- When onboarding a new data domain or migrating to a new provider
- Periodic data quality checks
- After pipeline changes that affect transformations
- When investigating suspected data issues

## Validation Layers

### Layer 1: Raw → Master (internal pipeline consistency)

Verify that pipeline transformations produce correct values.

**What to check:**
- Values match after scaling/unit conversion
- Currency codes resolve correctly (including subunits — e.g., GBp → GBP / 100, ILA → ILS / 100)
- Entity mapping is correct (provider IDs → internal company_id)
- Deduplication didn't lose valid data or keep duplicates
- Row counts are in expected range vs raw source
- NULL handling (missing currencies, missing mappings)

**Method:**
1. Identify the raw source tables for the domain being validated
2. Read the staging and intermediate views to understand the transformation chain
3. Query master for a company + latest fiscal year/period
4. Query raw source tables with the same key, applying the transformations manually in SQL
5. Compare values — they should match exactly or within floating-point tolerance

### Layer 2: Master → External (accuracy vs ground truth)

Verify that master values match publicly reported figures. This is provider-independent — the ground truth is the company's own filings.

**What to check:**
- Segment revenues match company earnings releases
- Total revenue / net income match annual reports
- Market data matches public exchange data
- Consensus estimates are in plausible ranges

**External sources (ordered by reliability):**
1. **Company investor relations pages** — earnings press releases, quarterly results
2. **Regulatory filings** — SEC EDGAR (US), Companies House (UK), AMF (France), EDINET (Japan), DART (Korea)
3. **News aggregators** — for revenue/earnings headline numbers
4. **Wikipedia** — useful for order-of-magnitude validation only

**Method:**
1. Use WebFetch on the company's investor relations / news page
2. Search for the latest earnings release or annual results announcement
3. Extract segment or total revenue figures
4. Compare with master values — flag discrepancies with magnitude

### Layer 3: Cross-provider (during migration)

When migrating from one provider to another, compare both providers' data for the same entities.

**Method:**
1. Select a panel of companies covered by both providers
2. Query the same metrics (revenue, segments, estimates) from both raw sources
3. Compare values — differences reveal provider-specific transformations or data quality gaps
4. Document systematic differences (different scaling conventions, different segment granularity)

## Sampling Strategy

### By currency (recommended for first-time validation)

Select one representative company per target currency to catch scaling/conversion bugs. GBP is always critical due to subunit risk.

```sql
-- Template: find one company per currency with most data in the target table
SELECT DISTINCT ON (c.code)
    c.code AS currency, e.name AS company, t.company_id
FROM master.<target_table> t
JOIN master.entity e ON e.entity_id = t.company_id
JOIN master.currency c ON c.currency_id = t.currency_id
WHERE c.code IN ('USD', 'EUR', 'GBP', 'JPY', 'KRW', 'CNY', 'INR', 'CHF')
AND <recent_data_filter>
ORDER BY c.code, count(*) OVER (PARTITION BY c.code, t.company_id) DESC
```

**Target currencies:**

| Currency | Why | Subunit risk |
|---|---|---|
| USD | Largest coverage, baseline | No |
| EUR | Major non-USD currency | No |
| GBP | **Subunit GBp = pence** | Yes — always verify |
| JPY | No decimals, large numbers | No |
| KRW | Very large numbers (trillions) | No |
| CNY | Chinese companies | No |
| INR | Indian companies, large numbers | No |
| CHF | Swiss companies | No |

### By sector/size (deeper validation)

After currency validation passes:
- Largest company per GICS sector
- Companies with complex segment structures (conglomerates, banks)
- Companies that recently restated financials

### Random sampling (regression checks)

Pick N random companies from master, validate against raw. Useful for automated checks.

## How to Build Raw Queries

The raw query depends on the current data provider. Do NOT hardcode queries — derive them from the pipeline code.

### Step 1: Read the pipeline

1. Find the staging view for the domain: `src/data/dbt_project/models/staging/stg_qa_<domain>*.sql`
2. Find the intermediate view: `src/data/dbt_project/models/intermediate/int_<domain>*.sql`
3. Identify:
   - Which raw tables are joined
   - What transformations are applied (scaling macros, currency lookups, type casts)
   - What deduplication is done
   - What filters are applied

### Step 2: Build the raw comparison query

Reconstruct the transformation manually in a single SQL query against raw tables:
- Apply the same scaling logic (read the DBT macros to understand the formulas)
- Apply the same currency resolution
- Apply the same entity mapping
- Do NOT apply deduplication — we want to see if the intermediate dedup is correct

### Step 3: Compare

```sql
-- Pattern: side-by-side raw vs master for a specific company
WITH raw_computed AS (
    -- Raw query with manual transformations
    SELECT <key_columns>, <computed_value> AS raw_value, <currency> AS raw_ccy
    FROM raw.<source_tables> ...
    WHERE <company_filter> AND <period_filter>
),
master_values AS (
    SELECT <key_columns>, value AS master_value, c.code AS master_ccy
    FROM master.<target_table> t
    JOIN master.currency c ON c.currency_id = t.currency_id
    WHERE <company_filter> AND <period_filter>
)
SELECT r.*, m.master_value, m.master_ccy,
    CASE WHEN r.raw_value = m.master_value THEN '✓'
         WHEN abs(r.raw_value - m.master_value) / NULLIF(abs(r.raw_value), 0) < 0.0001 THEN '~'
         ELSE '✗' END AS match
FROM raw_computed r
FULL OUTER JOIN master_values m ON <key_match>
ORDER BY ...
```

## Transformation Pitfalls Checklist

These are common sources of data corruption across providers. Check each when validating.

| Pitfall | How to detect | Example |
|---|---|---|
| **Unit/scale not applied** | Master values 1000x or 1Mx too small | Revenue in millions instead of absolute |
| **Subunit not converted** | GBP values 100x too large | GBp not divided by 100 |
| **Wrong scale direction** | Values inverted (divided instead of multiplied) | Revenue 1Mx too small |
| **Scale applied to wrong items** | Per-share values inflated by 1Mx | EPS of 50,000 instead of 0.05 |
| **Currency mismatch** | Values in wrong currency | USD value tagged as EUR |
| **Entity mapping error** | Values from wrong company | Two companies swapped |
| **Duplicate rows** | Same key appears twice in master | Missing dedup in pipeline |
| **Missing rows** | Raw has data but master doesn't | JOIN too restrictive (INNER vs LEFT) |
| **Date/period mismatch** | Values assigned to wrong period | Fiscal year offset |

## Report Format

### Summary table

```
| Company | Currency | Domain | Raw→Master | Master→External | Status |
|---|---|---|---|---|---|
| NVIDIA | USD | Segments | ✓ exact | ✓ press release | PASS |
| Hermès | EUR | Segments | ✓ exact | — not accessible | PARTIAL |
| LSEG | GBP | Segments | ✓ exact | — not accessible | PARTIAL |
```

### Status definitions

- **PASS** — Raw→Master match + external validation confirms
- **PARTIAL** — Raw→Master match but external source not accessible
- **FAIL** — Divergence found at any layer
- **SKIP** — No data available for this currency/company

### Detail (only if divergence found)

For each divergence:
1. Show the specific values (raw vs master vs external)
2. Compute the ratio (master/raw) to identify the likely cause
3. Check the transformation chain to pinpoint where the error occurs
4. Propose fix

### Tolerance thresholds

- **Exact match**: integer values must be identical
- **Float tolerance**: < 0.01% difference acceptable
- **Rounding display**: values shown in billions may differ by up to rounding unit — this is OK
- **Order of magnitude mismatch**: ALWAYS flag — likely scaling bug

## MCP Servers

Determine available MCP servers from the project context. Typical setup:

- **Test DB (raw + master):** for raw → master comparison
- **Prod DB (master only):** for production validation
- **Source DB (provider-specific):** for direct source comparison (may require VPN)

When the source DB is unreachable, use the raw schema in the test DB — it contains a Sling copy of the source data.

## Test Fixtures

Reusable test cases are stored in `${CLAUDE_SKILL_DIR}/fixtures/<domain>.md`. Each fixture defines:
- A panel of companies with their IDs, currencies, and edge case rationale
- Raw query templates for comparison
- External source URLs where accessible
- Known edge cases for the domain
- Regression values from previous validations (to detect regressions)

When running a validation, always load the fixture first. If no fixture exists for the domain, build one from scratch and propose saving it.

## Saving Reports

After completing a validation, **always ask** the user if they want to save the report. Do not save automatically.

If yes, save to `analysis/validation/YYYY-MM-DD_<domain>.md` in the active project directory (not in forge). Include:
- Date and scope of validation
- Full summary table
- Divergence details if any
- Fixture version used

Previous reports in `analysis/validation/` serve as audit trail — compare current results against past reports to detect regressions.

## Provider-Specific Reference

When executing this skill, check if provider-specific query patterns have been documented from previous validation sessions. Look in:
- Fixture files (`${CLAUDE_SKILL_DIR}/fixtures/`)
- Memory files (`memory/reference_*`)
- Data knowledge context (`context/data-knowledge.md`)
- Previous validation reports in `analysis/validation/`

If not documented, derive queries from the staging/intermediate DBT views as described in "How to Build Raw Queries".
