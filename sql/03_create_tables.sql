
-- PesaFlow: Core payment tables
-- All application tables belong to the payments schema.

CREATE TABLE payments.customers (
    customer_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    full_name TEXT NOT NULL,
    email TEXT NOT NULL UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE payments.accounts (
    account_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id BIGINT NOT NULL
        REFERENCES payments.customers(customer_id),
    currency CHAR(3) NOT NULL DEFAULT 'KES',
    balance NUMERIC(19, 2) NOT NULL DEFAULT 0.00,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT accounts_balance_nonnegative
        CHECK (balance >= 0),

    CONSTRAINT accounts_currency_supported
        CHECK (currency IN ('KES'))
);

CREATE TABLE payments.transfers (
    transfer_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    sender_account_id BIGINT NOT NULL
        REFERENCES payments.accounts(account_id),
    receiver_account_id BIGINT NOT NULL
        REFERENCES payments.accounts(account_id),
    amount NUMERIC(19, 2) NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending',
    idempotency_key UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT transfers_amount_positive
        CHECK (amount > 0),

    CONSTRAINT transfers_different_accounts
        CHECK (sender_account_id <> receiver_account_id),

    CONSTRAINT transfers_status_valid
        CHECK (status IN ('pending', 'completed', 'failed')),

    CONSTRAINT transfers_idempotency_key_unique
        UNIQUE (idempotency_key)
);

CREATE TABLE payments.ledger_entries (
    entry_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    transfer_id BIGINT NOT NULL
        REFERENCES payments.transfers(transfer_id),
    account_id BIGINT NOT NULL
        REFERENCES payments.accounts(account_id),
    entry_type TEXT NOT NULL,
    amount NUMERIC(19, 2) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT ledger_entry_type_valid
        CHECK (entry_type IN ('debit', 'credit')),

    CONSTRAINT ledger_amount_positive
        CHECK (amount > 0)
);
