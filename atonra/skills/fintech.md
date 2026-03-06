---
description: "Financial data handling conventions for Atonra fintech projects"
user_invocable: true
---

# Fintech Domain Conventions

Apply these rules when working on financial computation, portfolio optimization, or any code that handles monetary values or financial instruments.

## Numerical Precision

- **Currency amounts and portfolio weights:** use `Decimal` (Python) or a fixed-point library (TypeScript). Never use `float` or `number` for financial calculations.
- **Python:** use `decimal.Decimal` with explicit precision. Set rounding mode explicitly (`ROUND_HALF_EVEN` for financial standard).
- **TypeScript:** use a library like `big.js` or `dinero.js` for monetary values.
- When converting between types, always specify precision: `Decimal("0.01")` not `Decimal(0.01)`.

## Financial Data Types

- Represent currency codes as ISO 4217 strings (e.g., `"USD"`, `"CHF"`), not integers or custom enums.
- Represent dates as `datetime.date` (Python) or ISO 8601 strings — never timestamps for calendar dates (ex-dates, settlement dates).
- ISIN, CUSIP, SEDOL identifiers: always validate format before processing.

## Portfolio Calculations

- Weights must sum to 1.0 (or 100%) — add explicit validation.
- Returns: use log returns for aggregation across time, simple returns for aggregation across assets.
- Always specify whether a return is gross or net of fees.

## Data Integrity

- Financial time series: always check for missing data points, weekends, holidays before computation.
- Price data: validate against reasonable bounds (no negative prices for equities, no zero prices).
- When joining datasets (prices, factors, holdings), verify date alignment and handle missing values explicitly — never silently forward-fill without documenting the assumption.

## API Contracts for Financial Data

- All monetary amounts in API responses must include the currency code alongside the value.
- Percentage values: always document whether the value is in decimal form (0.05) or percentage form (5.0).
- Timestamps in APIs: always UTC with explicit timezone indicator.
