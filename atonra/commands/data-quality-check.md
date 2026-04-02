# Data Quality Check

Run a systematic data quality validation on the specified domain or table.

## Arguments

$ARGUMENTS — domain to validate (e.g., "segment estimates", "financial segments", "fundamentals", "market data", "all") and optional filters (currency, company).

## Workflow

1. **Load the skill**: Use the `data-validation` skill for methodology.
2. **Load fixtures**: Read the fixture file from `data-validation/fixtures/` for the specified domain. If no fixture exists for this domain, build one from scratch following the skill methodology, then save it.
3. **Execute validation**:
   - For each company in the test panel, query master and raw
   - Compare values (check scaling, currency, mapping)
   - Attempt external source validation where URLs are available
4. **Report**: Output the validation report in chat with summary table + details on any divergence.
5. **Propose saving**: If the user wants an audit trail, save the report to `analysis/validation/YYYY-MM-DD_<domain>.md` in the active project.
6. **Update fixtures**: If new edge cases or issues were found, propose adding them to the fixture file.

## Examples

```
/data-quality-check financial segments
/data-quality-check segment estimates USD,EUR,GBP
/data-quality-check all
```
