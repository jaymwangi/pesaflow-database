# PesaFlow — PostgreSQL Payment System

PesaFlow is a database engineering portfolio project that models a digital payments system using PostgreSQL. It demonstrates relational database design, atomic money transfers, transaction safety, idempotent requests, ledger validation, deferred constraint triggers, and automated SQL testing.

## Features

- **Relational data model:** Customers, accounts, transfers, and ledger entries.
- **Data integrity:** Primary keys, foreign keys, `CHECK` constraints, and unique constraints.
- **Atomic transfers:** Account balance updates, transfer records, and ledger entries participate in a single database transaction.
- **Concurrency control:** Account rows are locked during transfers to reduce race conditions and protect balance consistency.
- **Idempotency:** UUID idempotency keys prevent duplicate execution when the same successful request is retried.
- **Balance validation:** Rejects invalid amounts, self-transfers, nonexistent accounts, and transfers with insufficient funds.
- **Ledger validation:** Ensures debit and credit entries use the correct accounts and match the transfer amount.
- **Deferred integrity enforcement:** Constraint triggers verify that completed transfers have exactly one matching debit and one matching credit.
- **Automated SQL tests:** Seven transaction tests cover successful transfers, insufficient funds, invalid accounts, idempotency, and deferred ledger-integrity enforcement.

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

## Architecture and transaction workflow

A transfer is processed by the `payments.transfer_funds()` PL/pgSQL function.

1. Validate the request parameters and idempotency key.
2. Lock the sender and receiver account rows.
3. Check that both accounts exist.
4. Check whether the idempotency key has already been used.
5. Verify that the sender has sufficient funds.
6. Update the sender and receiver balances.
7. Insert the corresponding debit and credit ledger entries.
8. Mark the transfer as completed.
9. Enforce the completed-transfer ledger requirements when deferred constraint checks run.

The function participates in the caller's database transaction; it does not commit independently. This allows the caller to commit the complete operation or roll back its changes.

## Setup

**Prerequisites:** PostgreSQL 18 installed, the `psql` command available in your terminal, and access to a PostgreSQL user permitted to create the database and its objects.

### 1. Create the database

From the repository root, connect to the default `postgres` database:

```bash
psql -U postgres -d postgres -v ON_ERROR_STOP=1 -f sql/01_create_database.sql
```

Skip this step if the `pesaflow` database already exists.

### 2. Create the schema, tables, and database logic

Run the following commands **in order** from the repository root:

```bash
psql -U postgres -d pesaflow -v ON_ERROR_STOP=1 -f sql/02_create_schema.sql
psql -U postgres -d pesaflow -v ON_ERROR_STOP=1 -f sql/03_create_tables.sql
psql -U postgres -d pesaflow -v ON_ERROR_STOP=1 -f sql/04_seed_data.sql
psql -U postgres -d pesaflow -v ON_ERROR_STOP=1 -f sql/07_create_transfer_function.sql
psql -U postgres -d pesaflow -v ON_ERROR_STOP=1 -f sql/08_validate_ledger_entry.sql
psql -U postgres -d pesaflow -v ON_ERROR_STOP=1 -f sql/09_enforce_completed_transfer_ledger.sql
```

These commands are intended for a fresh database. Do not rerun the table-creation or seed-data scripts against an existing database without understanding their effects.

### 3. Run an example transfer

The transfer function accepts a sender account ID, receiver account ID, amount, and UUID idempotency key.

```sql
BEGIN;

SELECT payments.transfer_funds(
    1,
    2,
    100.00,
    '11111111-1111-4111-8111-111111111111'::UUID
) AS transfer_id;

COMMIT;
```

Use a new UUID for each new logical request. When retrying the same request, reuse its original UUID and parameters. A matching retry returns the existing completed transfer ID without applying the transfer again. Reusing a key with different transfer details is rejected.

**Important:** If an SQL statement raises an error inside a transaction, PostgreSQL normally marks that transaction as aborted. Roll back the failed transaction before continuing.

## Integrity controls

PesaFlow uses several layers of database enforcement:

- **Table constraints:** Protect relationships, valid values, and uniqueness.
- **A `BEFORE INSERT` trigger:** Validates ledger entries against their associated transfer, including the transfer amount and the correct sender or receiver account.
- **Deferred constraint triggers:** Check the final transaction state to ensure a completed transfer has exactly one matching debit and one matching credit.
- **Transactional rollback:** Allows failed operations to be rolled back without retaining partial balance or ledger changes.

The deferred checks also reject deleting a ledger entry when doing so would leave a completed transfer without its required debit-credit pair.

## Run automated tests

From the repository root, run:

```bash
psql -U postgres -d pesaflow -v ON_ERROR_STOP=1 -f tests/test_transactions.sql
```

The test suite contains seven tests:

1. **Successful transfer:** Verifies account balance changes and matching debit and credit entries.
2. **Insufficient funds:** Verifies that the transfer is rejected without leaving transfer or balance changes.
3. **Self-transfer:** Verifies that an account cannot transfer funds to itself.
4. **Nonexistent account:** Verifies that a transfer to an unknown account is rejected.
5. **Idempotent retry:** Verifies that retrying the same request does not transfer funds twice or duplicate records.
6. **Missing ledger entries:** Verifies that a completed transfer without its required ledger entries is rejected when deferred constraints are checked.
7. **Invalid ledger deletion:** Verifies that deleting a required ledger entry is rejected when deferred constraints are checked.

The tests use transactions and rollbacks so their test changes do not persist in the database.

Additional manual verification has included rejecting reuse of an idempotency key with different request details, validating ledger entries against their transfers, and checking the resulting account balances and ledger records.

## Project structure

```text
sql/        Schema, seed data, transfer logic, triggers, and queries
tests/      Automated SQL transaction tests
docs/       Database design and SQL concepts
app/        API code
dashboard/  Dashboard code
```

## Engineering considerations

PesaFlow demonstrates core database engineering mechanisms; it is not a production-ready banking platform.

A production implementation would also require appropriate authentication and authorization, restricted database privileges, API-level validation, monitoring and alerting, reconciliation procedures, and broader concurrency and failure-recovery testing.

## Author

Built as a portfolio project to demonstrate practical PostgreSQL, SQL, PL/pgSQL, transaction management, and database integrity skills.
