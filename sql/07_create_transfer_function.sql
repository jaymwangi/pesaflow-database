
-- PesaFlow: Atomic, idempotent transfer function

-- Replace the previous three-argument function.
DROP FUNCTION IF EXISTS payments.transfer_funds(BIGINT, BIGINT, NUMERIC);

CREATE OR REPLACE FUNCTION payments.transfer_funds(
    p_sender_account_id BIGINT,
    p_receiver_account_id BIGINT,
    p_amount NUMERIC(19, 2),
    p_idempotency_key UUID
)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE
    v_transfer_id BIGINT;
    v_sender_balance NUMERIC(19, 2);
    v_account_count INTEGER;

    v_existing_sender BIGINT;
    v_existing_receiver BIGINT;
    v_existing_amount NUMERIC(19, 2);
    v_existing_status TEXT;
BEGIN
    -- Validate the request.
    IF p_idempotency_key IS NULL THEN
        RAISE EXCEPTION 'Idempotency key is required';
    END IF;

    IF p_sender_account_id = p_receiver_account_id THEN
        RAISE EXCEPTION 'Sender and receiver must be different accounts';
    END IF;

    IF p_amount IS NULL OR p_amount <= 0 THEN
        RAISE EXCEPTION 'Transfer amount must be positive';
    END IF;

    -- Lock accounts in a consistent order to reduce deadlocks.
    PERFORM a.account_id
    FROM payments.accounts AS a
    WHERE a.account_id IN (
        p_sender_account_id,
        p_receiver_account_id
    )
    ORDER BY a.account_id
    FOR UPDATE;

    -- Ensure both accounts exist.
    SELECT COUNT(*)
    INTO v_account_count
    FROM payments.accounts
    WHERE account_id IN (
        p_sender_account_id,
        p_receiver_account_id
    );

    IF v_account_count <> 2 THEN
        RAISE EXCEPTION 'Sender or receiver account does not exist';
    END IF;

    -- Claim this idempotency key.
    -- A concurrent request using the same key must wait for
    -- the first transaction to commit or roll back.
    INSERT INTO payments.transfers (
        sender_account_id,
        receiver_account_id,
        amount,
        status,
        idempotency_key
    )
    VALUES (
        p_sender_account_id,
        p_receiver_account_id,
        p_amount,
        'pending',
        p_idempotency_key
    )
    ON CONFLICT (idempotency_key) DO NOTHING
    RETURNING transfer_id INTO v_transfer_id;

    -- If the key already exists, return the original transfer
    -- only when the request details match.
    IF v_transfer_id IS NULL THEN
        SELECT
            transfer_id,
            sender_account_id,
            receiver_account_id,
            amount,
            status
        INTO
            v_transfer_id,
            v_existing_sender,
            v_existing_receiver,
            v_existing_amount,
            v_existing_status
        FROM payments.transfers
        WHERE idempotency_key = p_idempotency_key;

        IF v_existing_sender <> p_sender_account_id
           OR v_existing_receiver <> p_receiver_account_id
           OR v_existing_amount <> p_amount THEN
            RAISE EXCEPTION
                'Idempotency key was already used for a different request';
        END IF;

        IF v_existing_status <> 'completed' THEN
            RAISE EXCEPTION
                'Existing transfer with this key is not completed';
        END IF;

        RETURN v_transfer_id;
    END IF;

    -- Check available funds after obtaining the account locks.
    SELECT balance
    INTO v_sender_balance
    FROM payments.accounts
    WHERE account_id = p_sender_account_id;

    IF v_sender_balance < p_amount THEN
        RAISE EXCEPTION
            'Insufficient funds: available %, requested %',
            v_sender_balance, p_amount;
    END IF;

    -- Apply both sides of the transfer.
    UPDATE payments.accounts
    SET balance = balance - p_amount
    WHERE account_id = p_sender_account_id;

    UPDATE payments.accounts
    SET balance = balance + p_amount
    WHERE account_id = p_receiver_account_id;

    -- Record the matching debit and credit.
    INSERT INTO payments.ledger_entries (
        transfer_id,
        account_id,
        entry_type,
        amount
    )
    VALUES
        (v_transfer_id, p_sender_account_id, 'debit', p_amount),
        (v_transfer_id, p_receiver_account_id, 'credit', p_amount);

    -- Mark completed only after balances and ledger are updated.
    UPDATE payments.transfers
    SET status = 'completed'
    WHERE transfer_id = v_transfer_id;

    RETURN v_transfer_id;
END;
$$;
