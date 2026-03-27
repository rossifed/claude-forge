---
name: data-provider-analysis
description: "Analyze data provider documentation and databases, compare coverage against target master schema, map source fields to target tables, detect gaps, and propose transformations for data provider migration or onboarding"
user-invocable: true
argument-hint: "provider name or PDF path"
---

# Data Provider Analysis

Systematic methodology for analyzing a data provider's data model against a target master schema. Produces coverage maps, gap reports, and transformation specs.

## When this skill activates

- Evaluating a new data provider for onboarding
- Comparing provider coverage against target schema requirements
- Designing staging/intermediate layer transformations for a new source
- Replacing one provider with another (migration gap analysis)
- Auditing an existing provider integration for gaps or regressions

## Prerequisites

Before starting, verify:
1. **Target schema context** — a domain map or schema documentation is available (via context files, walk-up, or direct DB query)
2. **Provider documentation** — PDFs, guides, or live DB access via MCP
3. **MCP access** — target DB queryable for column-level inspection when needed
4. **Working directory** — project where analysis outputs will be written

## Phase 1: Document Ingestion

### For PDF documentation

1. Read the PDF using the Read tool (it supports PDFs natively — use `pages` parameter for large files)
2. Start with table of contents / index pages to build a navigation map
3. Focus on data model / schema / field reference sections — skip API auth, SDK setup, and GUI docs
4. Extract concrete examples — they reveal data formats better than descriptions
5. Write structured notes to `analysis/<provider>-model.md` in the working project:
   - One section per dataset/service
   - For each: table/dataset name, key fields, data types, relationships, update frequency, granularity

### For live database access (MCP)

1. List schemas and tables via MCP (`search_objects` or `information_schema`)
2. Sample key tables (`SELECT TOP 5` / `LIMIT 5`) to understand actual data shape
3. Compare documented model vs actual data — flag discrepancies
4. Write findings to the same `analysis/<provider>-model.md`

### Key questions to answer per dataset

- What entities does it cover? (companies, instruments, indices, funds)
- What geographies/markets?
- What time range and update frequency?
- What is the primary key / natural key?
- How are entities identified? (provider-specific IDs, ISINs, SEDOLs, CUSIPs, PermIDs, etc.)
- What symbol systems are available? (ticker, RIC, Bloomberg, etc.)

## Phase 2: Domain Coverage Mapping

For each domain in the target schema, assess provider coverage. Use the target schema context (loaded via walk-up or queried via MCP) to enumerate domains and their key tables.

### Coverage matrix format

```markdown
| Target Domain | Key Tables | Provider Dataset | Coverage | Notes |
|---|---|---|---|---|
| [domain 1] | [tables] | [provider dataset] | Full/Partial/None | ... |
| [domain 2] | [tables] | [provider dataset] | ... | ... |
| ... | ... | ... | ... | ... |
```

### Coverage levels

- **Full**: provider covers all required fields with adequate granularity
- **Partial**: provider covers the domain but missing fields or limited granularity — list what's missing
- **None**: no equivalent dataset in the provider — assess impact on downstream consumers
- **Exceeds**: provider offers data not currently in the master schema — flag as potential enrichment

### For each Partial or None

- Identify specifically what is missing (which fields, which coverage gaps)
- Assess impact: is this critical for downstream consumers (views, marts, portfolios)?
- Propose alternatives: other provider datasets, derived calculations, or accept the gap

## Phase 3: Field-Level Mapping

For each domain with Full or Partial coverage, produce a field mapping spec.

### Mapping table format

```markdown
| Target Table.Column | Type | Nullable | Provider Field | Transform | Notes |
|---|---|---|---|---|---|
| [table.column] | [type] | [Y/N] | [src.field] | direct | ... |
| [table.fk_column] | [type] | [Y/N] | [src.field] | lookup | via reference table |
```

### Transform categories

| Transform | Description |
|---|---|
| `direct` | 1:1 mapping, no transformation needed |
| `rename` | Same data, different field name |
| `type_cast` | Same data, different type (e.g., string date → date) |
| `lookup` | Requires joining to a reference/mapping table |
| `derive` | Computed from multiple source fields |
| `aggregate` | Requires grouping/aggregation from source |
| `constant` | Hardcoded value (e.g., data_source_id for the new provider) |
| `none` | No source field available — document the gap |

### ID Resolution mapping (critical for every provider)

Every provider integration must resolve to the target's entity/ID system:
1. Document how provider entity IDs map to internal entity IDs (new data source entry needed)
2. Document instrument/security ID resolution
3. Document quote/listing resolution
4. Document venue/exchange resolution
5. Identify common cross-provider identifiers (ISIN, SEDOL, CUSIP, FIGI) that can link to existing data

## Phase 4: Gap & Risk Report

### Gap categories

1. **Coverage gaps** — master domains with no provider equivalent
2. **Field gaps** — target fields with no source mapping
3. **Granularity gaps** — provider data less granular than target needs
4. **Temporal gaps** — provider history shorter than target requires
5. **Quality risks** — known data quality issues from documentation or sampling
6. **Symbol gaps** — identifier systems present/absent vs current provider

### Risk classification

| Level | Criteria | Example |
|---|---|---|
| **Critical** | Blocks core functionality | No entity IDs, no market data |
| **High** | Degrades analytics quality | Missing financials, incomplete estimates |
| **Medium** | Limits features | Partial corporate actions, fewer classifications |
| **Low** | Cosmetic or rarely used | Missing weblinks, incomplete descriptions |

### Output

Write the full analysis to `analysis/<provider>-analysis.md`:
1. Executive summary (1 paragraph)
2. Coverage matrix (Phase 2)
3. Field mappings per domain (Phase 3)
4. Gap & risk report (Phase 4)
5. Recommendations: build order, what to defer, what to source elsewhere

## Phase 5: Staging/Intermediate Design

**Only proceed when explicitly requested** — do not auto-advance from analysis.

### Staging views (source-dependent)

- One view per provider dataset feeding a target domain
- Naming: `stg_<provider_prefix>_<dataset>`
- Handles: type casting, field renaming, source-specific cleaning, deduplication
- Provider-specific logic ONLY — no cross-source joins

### Intermediate views (source-agnostic)

- Joins provider IDs to internal entity IDs via the target's mapping tables
- Produces the exact column set expected by the target load process
- Naming: `int_<domain>_<specificity>`
- Must follow existing pipeline patterns (check project documentation)

## Cross-Provider Comparison

When replacing or augmenting a provider:

1. **Query existing staging views** to see current source fields used
2. **Query existing intermediate views** to see the target field set
3. **The delta** between new provider fields and existing intermediate output = migration gap
4. **Symbol enrichment** — if new provider has identifiers not in the current provider, flag as enrichment opportunity for the target's instrument/entity tables
5. **Data quality comparison** — sample same entities in both sources, compare values for key fields

### Cross-reference approach

Use the target's entity/ID mapping tables to find:
- Entities present in the current source but missing in the new source (coverage regression)
- Entities present in the new source but absent from the current source (coverage gain)
- Common entities where values differ (quality comparison)

## Data Knowledge Integration

When analysis reveals pitfalls, unit conversions, format quirks, or mapping gotchas:
- Propose capturing them in a persistent knowledge file (context or documentation)
- Follow the format already established in the project
- Wait for user confirmation before writing

## Supporting Files

- `${CLAUDE_SKILL_DIR}/provider-checklist.md` — Operational checklist for starting a new provider analysis
