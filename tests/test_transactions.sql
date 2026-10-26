
-- PesaFlow: Transaction behaviour tests
-- Run with:
-- psql -U postgres -d pesaflow -v ON_ERROR_STOP=1 -f tests/test_transactions.sql
--
-- Each test runs inside a transaction and rolls back its changes.

-- Test 1: A valid transfer updates balances and creates
-- exactly two matching ledger entries.
BEGIN;

DO $$
DECLARE
    v_sender_before NUMERIC(19, 2);
    v_receiver_before NUMERIC(19, 2);
    v_sender_after NUMERIC(19, 2);
    v_receiver_after NUMERIC(19, 2);
    v_transfer_id BIGINT;
    v_ledger_count INTEGER;
    v_debit_total NUMERIC(19, 2);
    v_credit_total NUMERIC(19, 2);
BEGIN
    SELECT balance INTO v_sender_before
    FROM payments.accounts
    WHERE account_id = 1;

    SELECT balance INTO v_receiver_before
    FROM payments.accounts
    WHERE account_id = 2;

    v_transfer_id := payments.transfer_funds(
        1, 2, 10.00,
        'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
    );

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

    SELECT
        COUNT(*),
        COALESCE(SUM(amount) FILTER (WHERE entry_type = 'debit'), 0),
        COALESCE(SUM(amount) FILTER (WHERE entry_type = 'credit'), 0)
    INTO v_ledger_count, v_debit_total, v_credit_total
    FROM payments.ledger_entries
    WHERE transfer_id = v_transfer_id;

    IF v_ledger_count <> 2 THEN
        RAISE EXCEPTION
            'Test 1 failed: expected two ledger entries, got %',
            v_ledger_count;
    END IF;

    IF v_debit_total <> 10.00 OR v_credit_total <> 10.00 THEN
        RAISE EXCEPTION
            'Test 1 failed: ledger is unbalanced; debit %, credit %',
            v_debit_total, v_credit_total;
    END IF;

    RAISE NOTICE 'Test 1 passed: successful, balanced transfer';
END;
$$;

ROLLBACK;

-- Test 2: Insufficient funds must not leave data behind.
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
        PERFORM payments.transfer_funds(
            1, 2, 999999.00,
            'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
        );

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

    IF EXISTS (
        SELECT 1
        FROM payments.transfers
        WHERE idempotency_key =
            'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
    ) THEN
        RAISE EXCEPTION 'Test 2 failed: idempotency key was not rolled back';
    END IF;

    RAISE NOTICE 'Test 2 passed: insufficient funds rejected and rolled back';
END;
$$;

ROLLBACK;

-- Test 3: A self-transfer must be rejected.
BEGIN;

DO $$
BEGIN
    BEGIN
        PERFORM payments.transfer_funds(
            1, 1, 10.00,
            'cccccccc-cccc-4ccc-8ccc-cccccccccccc'
        );

        RAISE EXCEPTION 'Test 3 failed: self-transfer was accepted';
    EXCEPTION
        WHEN SQLSTATE 'P0001' THEN
            IF SQLERRM <>
                'Sender and receiver must be different accounts' THEN
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
        PERFORM payments.transfer_funds(
            1, 9999, 10.00,
            'dddddddd-dddd-4ddd-8ddd-dddddddddddd'
        );

        RAISE EXCEPTION
            'Test 4 failed: nonexistent account was accepted';
    EXCEPTION
        WHEN SQLSTATE 'P0001' THEN
            IF SQLERRM <>
                'Sender or receiver account does not exist' THEN
                RAISE;
            END IF;
    END;

    RAISE NOTICE 'Test 4 passed: nonexistent account rejected';
END;
$$;

ROLLBACK;


-- Test 5: Retrying the same request must not transfer twice.
BEGIN;

DO $$
DECLARE
    v_first_id BIGINT;
    v_retry_id BIGINT;
    v_sender_before NUMERIC(19, 2);
    v_receiver_before NUMERIC(19, 2);
    v_sender_after NUMERIC(19, 2);
    v_receiver_after NUMERIC(19, 2);
    v_transfer_count INTEGER;
    v_ledger_count INTEGER;
BEGIN
    SELECT balance INTO v_sender_before
    FROM payments.accounts
    WHERE account_id = 1;

    SELECT balance INTO v_receiver_before
    FROM payments.accounts
    WHERE account_id = 2;

    v_first_id := payments.transfer_funds(
        1, 2, 25.00,
        'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee'
    );

    v_retry_id := payments.transfer_funds(
        1, 2, 25.00,
        'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee'
    );

    IF v_first_id <> v_retry_id THEN
        RAISE EXCEPTION 'Test 5 failed: retry returned a different transfer ID';
    END IF;

    SELECT balance INTO v_sender_after
    FROM payments.accounts
    WHERE account_id = 1;

    SELECT balance INTO v_receiver_after
    FROM payments.accounts
    WHERE account_id = 2;

    IF v_sender_after <> v_sender_before - 25.00 THEN
        RAISE EXCEPTION 'Test 5 failed: sender was charged incorrectly';
    END IF;

    IF v_receiver_after <> v_receiver_before + 25.00 THEN
        RAISE EXCEPTION 'Test 5 failed: receiver was credited incorrectly';
    END IF;

    SELECT COUNT(*) INTO v_transfer_count
    FROM payments.transfers
    WHERE idempotency_key = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';

    SELECT COUNT(*) INTO v_ledger_count
    FROM payments.ledger_entries
    WHERE transfer_id = v_first_id;

    IF v_transfer_count <> 1 OR v_ledger_count <> 2 THEN
        RAISE EXCEPTION
            'Test 5 failed: expected one transfer and two ledger entries';
    END IF;

    RAISE NOTICE 'Test 5 passed: retry did not duplicate the transfer';
END;
$$;

ROLLBACK;
