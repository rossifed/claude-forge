---
name: database-modeling
description: "Database schema design conventions: column types, naming, sizing, keys, and value storage rules for creating or modifying tables and columns"
user-invocable: false
---

# Database Modeling

Conventions for designing and evolving relational database schemas. Apply these when creating tables, adding columns, writing migrations, or reviewing schema changes.

## Before modeling

- Read the source specification (documentation, data dictionary) before choosing types or names.
- Query actual data in the source DB to verify assumptions (max lengths, value ranges, cardinality).
- Check existing tables in the same schema for naming patterns and conventions — be consistent. If `updated_at` is used everywhere, do not introduce `last_modified`.
- Flag ambiguous or uncertain cases to the user rather than model incorrectly. Wrong schema is worse than slow schema.

## Date and time

- Verify whether a time component is needed. Use `date` for calendar dates (birth date, fiscal period end), `timestamp` for point-in-time events.
- When using timestamps, verify whether timezone info must be preserved. Drop timezone only when certain the value is expressed in UTC — and reflect it in the name (e.g., `published_at_utc`).

## Column types and sizing

- **Varchar:** check max length from source specs or actual DB data. Use tight bounds — `varchar(12)` for ISO codes, not `varchar(255)`. When in doubt, query `SELECT MAX(LENGTH(col))` on actual data.
- **Surrogate key type:** match to expected cardinality.
  - `smallint` (max ~32k): reference/lookup tables (countries, currencies, types)
  - `integer` (max ~2B): domain entity tables (companies, instruments)
  - `bigint`: only for high-volume tables (market data, financial values, timeseries)
- **Monetary/financial values:** use `numeric(precision, scale)` with dimensions derived from expected max values — never `float` or `double precision`. Float introduces rounding errors unacceptable for financial data.
- **Boolean:** use `boolean` — never `integer` 0/1 or `char(1)` Y/N.

## Naming

- Explicit names, no abbreviations: `instrument_type` not `instr_typ`, `currency_id` not `ccy_id`.
- Avoid prefixes or suffixes unless motivated by a specific, documented need.
- Business-domain naming, source-agnostic: name after the business concept, not the provider's internal terminology or codes. The schema should survive a provider change without renaming.
- Table names: singular (`company`, not `companies`), snake_case.
- Column names: snake_case, self-describing. Foreign keys: `<referenced_table>_id` (e.g., `country_id`).

## Values and units

- **Absolute values in master/golden tables:** if the source provides values with a scale factor (thousands, millions), multiply by the factor before storing. Store the absolute value — unless there is a documented reason to keep the raw representation.
- **Currency accompaniment:** monetary columns must have an accompanying currency reference (FK or column). Omit only when the currency is inherent and permanent for the entire table (e.g., a table that is by-definition single-currency, documented as such).
- **Unit of expression:** values with units (weight, volume, percentage) must store or reference the unit alongside the value. Do not assume the consumer knows the unit.

## Keys and identity

- Prefer surrogate keys over natural keys for entities. Natural keys from external providers are unstable (codes get reassigned, formats change). Store natural keys in mapping/reference columns, not as primary keys.
- Composite primary keys are acceptable for junction/association tables and timeseries fact tables where the combination is inherently stable.
