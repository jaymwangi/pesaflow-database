
-- PesaFlow: Transaction behaviour tests
-- Run with: psql -U postgres -d pesaflow -v ON_ERROR_STOP=1 -f tests/test_transactions.sql
-- Each test runs inside a transaction and rolls back its changes.

BEGIN;

-- Test 1: A valid transfer should update balances and create
-- one transfer with matching debit and credit ledger entries.
DO $$
DECLARE
    v_sender_before NUMERIC(19, 2);
    v_receiver_before NUMERIC(19, 2);
    v_sender_after NUMERIC(19, 2);
    v_receiver_after NUMERIC(19, 2);
    v_transfer_id BIGINT;
    v_ledger_count INTEGER;
BEGIN
    SELECT balance INTO v_sender_before
    FROM payments.accounts
    WHERE account_id = 1;

    SELECT balance INTO v_receiver_before
    FROM payments.accounts
    WHERE account_id = 2;

    v_transfer_id := payments.transfer_funds(1, 2, 10.00);

    SELECT balance INTO v_sender_after
    FROM payments.accounts
    WHERE account_id = 1;

    SELECT balance INTO v_receiver_after
    FROM payments.accounts
    WHERE account_id = 2;

    IF v_sender_after <> v_sender_before - 10.00 THEN
        RAISE EXCEPTION 'Test 1 failed: sender balance is incorrect';
    END IF;

    IF v_receiver_after <> v_receiver_before + 10.00 THEN
        RAISE EXCEPTION 'Test 1 failed: receiver balance is incorrect';
    END IF;

    SELECT COUNT(*) INTO v_ledger_count
    FROM payments.ledger_entries
    WHERE transfer_id = v_transfer_id;

    IF v_ledger_count <> 2 THEN
        RAISE EXCEPTION 'Test 1 failed: expected two ledger entries, got %',
            v_ledger_count;
    END IF;

    RAISE NOTICE 'Test 1 passed: successful transfer';
END;
$$;

ROLLBACK;

-- Test 2: Insufficient funds must be rejected without changing data.
BEGIN;

DO $$
DECLARE
    v_balance_before NUMERIC(19, 2);
    v_transfer_count_before BIGINT;
BEGIN
    SELECT balance INTO v_balance_before
    FROM payments.accounts
    WHERE account_id = 1;

    SELECT COUNT(*) INTO v_transfer_count_before
    FROM payments.transfers;

    BEGIN
        PERFORM payments.transfer_funds(1, 2, 999999.00);
        RAISE EXCEPTION 'Test 2 failed: insufficient funds were accepted';
    EXCEPTION
        WHEN SQLSTATE 'P0001' THEN
            IF SQLERRM NOT LIKE 'Insufficient funds:%' THEN
                RAISE;
            END IF;
    END;

    IF (SELECT balance FROM payments.accounts WHERE account_id = 1)
       <> v_balance_before THEN
        RAISE EXCEPTION 'Test 2 failed: sender balance changed';
    END IF;

    IF (SELECT COUNT(*) FROM payments.transfers)
       <> v_transfer_count_before THEN
        RAISE EXCEPTION 'Test 2 failed: transfer record was created';
    END IF;

    RAISE NOTICE 'Test 2 passed: insufficient funds rejected';
END;
$$;

ROLLBACK;

-- Test 3: A self-transfer must be rejected.
BEGIN;

DO $$
BEGIN
    BEGIN
        PERFORM payments.transfer_funds(1, 1, 10.00);
        RAISE EXCEPTION 'Test 3 failed: self-transfer was accepted';
    EXCEPTION
        WHEN SQLSTATE 'P0001' THEN
            IF SQLERRM <> 'Sender and receiver must be different accounts' THEN
                RAISE;
            END IF;
    END;

    RAISE NOTICE 'Test 3 passed: self-transfer rejected';
END;
$$;

ROLLBACK;

-- Test 4: A transfer to a nonexistent account must be rejected.
BEGIN;

DO $$
BEGIN
    BEGIN
        PERFORM payments.transfer_funds(1, 9999, 10.00);
        RAISE EXCEPTION 'Test 4 failed: nonexistent account was accepted';
    EXCEPTION
        WHEN SQLSTATE 'P0001' THEN
            IF SQLERRM <> 'Sender or receiver account does not exist' THEN
                RAISE;
            END IF;
    END;

    RAISE NOTICE 'Test 4 passed: nonexistent account rejected';
END;
$$;

ROLLBACK;
