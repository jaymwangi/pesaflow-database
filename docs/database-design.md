
# PesaFlow Database Design

## Core schema

All application tables are stored in the PostgreSQL `payments` schema.

- `customers`: customer identity and contact information.
- `accounts`: customer-owned accounts, currency and current balance.
- `transfers`: sender, receiver, amount and transfer status.
- `ledger_entries`: debit and credit records for each transfer.

## Integrity controls

- Primary keys uniquely identify records.
- Foreign keys enforce valid relationships.
- Unique customer emails prevent duplicate email addresses.
- Check constraints reject negative balances and non-positive transfer amounts.
- Account rows are locked during a transfer to reduce conflicting concurrent updates.
- Balance changes and ledger inserts occur inside one transaction.

## Validation results

### Successful transfer

Transferred KSh 750 from Mary Wanjiku (account 1) to Peter Otieno (account 2).

| Account | Before | After |
|---|---:|---:|
| Mary | 5,000.00 | 4,250.00 |
| Peter | 2,000.00 | 2,750.00 |
| Amina | 1,500.00 | 1,500.00 |

The transfer produced one debit entry and one credit entry, both for KSh 750. Total debits equalled total credits.

### Insufficient-funds test

Attempted to transfer KSh 10,000 from Mary's account, which held KSh 4,250.

The database raised an insufficient-funds exception. The account balance remained unchanged, and the transfer count remained at one.

## Current limitations

- The transfer script uses fixed account IDs and a fixed amount for demonstration.
- Re-running it could create a duplicate transfer.
- Balanced ledger entries are verified by a query but are not yet enforced automatically by the database.
- The current balance and ledger are not yet protected against every possible inconsistency or concurrent-operation edge case.
