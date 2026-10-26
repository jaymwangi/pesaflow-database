# PesaFlow — PostgreSQL Payment System

PesaFlow is a database engineering portfolio project that models a digital payments system using PostgreSQL. It demonstrates relational database design, transactional integrity, balanced ledger entries, idempotent payment requests, and automated SQL testing.

## Features

- **Relational data model:** Customers, accounts, transfers, and ledger entries.
- **Data integrity:** Primary keys, foreign keys, `CHECK` constraints, and unique constraints.
- **Atomic transfers:** Debit and credit operations execute within a single database transaction.
- **Concurrency control:** Account rows are locked during transfers to reduce race conditions.
- **Idempotency:** A UUID key prevents a retried payment request from transferring funds twice.
- **Ledger integrity:** Successful transfers create matching debit and credit entries.
- **Automated SQL tests:** Tests cover successful transfers, ledger balancing, insufficient funds, self-transfers, nonexistent accounts, and duplicate requests.

## Technology

- PostgreSQL 18
- SQL and PL/pgSQL
- Git and GitHub

## Database schema

All application tables belong to the `payments` schema.

| Table | Purpose |
|---|---|
| `payments.customers` | Customer details |
| `payments.accounts` | Account ownership, currency, and balance |
| `payments.transfers` | Transfer requests, status, and idempotency keys |
| `payments.ledger_entries` | Debit and credit records for transfers |

## Setup

Prerequisites: PostgreSQL 18 installed and the `psql` command available in your terminal.

### 1. Create the database

Run this command from the repository root, connecting to the default `postgres` database:

```bash
psql -U postgres -d postgres -v ON_ERROR_STOP=1 -f sql/01_create_database.sql
```

Skip this step if the `pesaflow` database already exists.

### 2. Create the schema and tables

Run these commands from the repository root:

```bash
psql -U postgres -d pesaflow -v ON_ERROR_STOP=1 -f sql/02_create_schema.sql
psql -U postgres -d pesaflow -v ON_ERROR_STOP=1 -f sql/03_create_tables.sql
psql -U postgres -d pesaflow -v ON_ERROR_STOP=1 -f sql/04_seed_data.sql
psql -U postgres -d pesaflow -v ON_ERROR_STOP=1 -f sql/07_create_transfer_function.sql
```

**Important:** These commands are intended for a fresh database. Do not rerun the table-creation or seed-data scripts against a database that already contains the project tables and records.

## Example transfer

The transfer function accepts the sender account ID, receiver account ID, amount, and an idempotency UUID.

```sql
BEGIN;

SELECT payments.transfer_funds(
    1,
    2,
    100.00,
    '11111111-1111-4111-8111-111111111111'
) AS transfer_id;

COMMIT;
```

Use the same UUID when retrying the *same logical request*. A retry with matching details returns the original transfer ID without applying another transfer. Reusing a key with different transfer details is rejected.

Every successful transfer updates both account balances and records a matching debit and credit. If the operation raises an error, PostgreSQL rolls back the failed statement; the caller must not commit a transaction that has entered an aborted state without first handling the error appropriately.

## Run automated tests

```bash
psql -U postgres -d pesaflow -v ON_ERROR_STOP=1 -f tests/test_transactions.sql
```

The SQL test suite uses transactions and rollbacks so test changes do not persist.

## Project structure

```text
sql/       Database schema, seed data, transfer logic, and queries
tests/     Automated SQL transaction tests
docs/      Database design and SQL concepts
app/       API code
dashboard/ Dashboard code
```

## Engineering considerations

This project demonstrates core database mechanisms rather than a production-ready banking platform. A production implementation would also need authentication and authorization, request-payload validation, stronger operational observability, reconciliation procedures, and additional concurrent-request and failure-recovery testing.

## Author

Built as a portfolio project to demonstrate practical PostgreSQL and database engineering skills.