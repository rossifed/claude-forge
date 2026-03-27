# Provider Analysis Checklist

Reusable operational checklist for starting a new provider analysis. Reference from SKILL.md.

## Pre-Analysis

- [ ] Provider documentation located (PDFs, guides, or live DB access)
- [ ] MCP server configured for provider source DB (if applicable)
- [ ] Target schema context available (documentation, context files, or DB query access)
- [ ] MCP access to target DB verified
- [ ] Working directory identified — `analysis/` folder exists in the project
- [ ] Existing provider integration reviewed (if replacing): staging views, intermediate views, known pitfalls

## Phase 1 — Document Ingestion

- [ ] Documentation navigation map built (TOC, key sections identified)
- [ ] Data model extracted per service/dataset:
  - [ ] Tables/datasets listed with key fields and types
  - [ ] Primary keys and natural keys identified
  - [ ] Entity identification system documented (provider IDs, ISINs, SEDOLs, etc.)
  - [ ] Symbol systems inventoried (ticker, RIC, Bloomberg, FIGI, etc.)
  - [ ] Update frequency and granularity noted
- [ ] Structured notes written to `analysis/<provider>-model.md`
- [ ] If live DB: sample queries run, documented model vs actual compared

## Phase 2 — Coverage Assessment

- [ ] Coverage matrix completed for all target schema domains
- [ ] Gaps classified by severity (Critical / High / Medium / Low)
- [ ] Enrichment opportunities flagged (provider exceeds current coverage)

## Phase 3 — Field Mapping (per covered domain)

- [ ] Field-level mapping table produced
- [ ] ID resolution path documented (entity, instrument, quote, venue mappings)
- [ ] Transform type identified for each field (direct, lookup, derive, etc.)
- [ ] Unmappable fields listed with impact assessment
- [ ] New data source entry specified (mnemonic, description)

## Phase 4 — Gap & Risk Report

- [ ] All gaps documented with severity and downstream impact
- [ ] Recommendations prioritized: build order, defer list, alternative sources
- [ ] Data quality risks from documentation or sampling noted

## Deliverables

- [ ] `analysis/<provider>-model.md` — structured data model notes
- [ ] `analysis/<provider>-analysis.md` — full analysis (coverage, mappings, gaps, recommendations)
- [ ] Data knowledge findings proposed for persistent context
- [ ] Cross-provider comparison completed (if replacing an existing source)
