
-- PesaFlow: Reusable atomic transfer function

CREATE OR REPLACE FUNCTION payments.transfer_funds(
    p_sender_account_id BIGINT,
    p_receiver_account_id BIGINT,
    p_amount NUMERIC(19, 2)
)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE
    v_transfer_id BIGINT;
    v_sender_balance NUMERIC(19, 2);
    v_account_count INTEGER;
BEGIN
    -- Validate the requested transfer.
    IF p_sender_account_id = p_receiver_account_id THEN
        RAISE EXCEPTION 'Sender and receiver must be different accounts';
    END IF;

    IF p_amount IS NULL OR p_amount <= 0 THEN
        RAISE EXCEPTION 'Transfer amount must be positive';
    END IF;

    -- Lock both accounts in ascending ID order.
    PERFORM a.account_id
    FROM payments.accounts AS a
    WHERE a.account_id IN (
        p_sender_account_id,
        p_receiver_account_id
    )
    ORDER BY a.account_id
    FOR UPDATE;

    -- Confirm that both accounts exist.
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

    -- Read the sender's balance after obtaining the locks.
    SELECT balance
    INTO v_sender_balance
    FROM payments.accounts
    WHERE account_id = p_sender_account_id;

    IF v_sender_balance < p_amount THEN
        RAISE EXCEPTION
            'Insufficient funds: available %, requested %',
            v_sender_balance, p_amount;
    END IF;

    -- Create the transfer record.
    INSERT INTO payments.transfers (
        sender_account_id,
        receiver_account_id,
        amount,
        status
    )
    VALUES (
        p_sender_account_id,
        p_receiver_account_id,
        p_amount,
        'completed'
    )
    RETURNING transfer_id INTO v_transfer_id;

    -- Apply both balance changes.
    UPDATE payments.accounts
    SET balance = balance - p_amount
    WHERE account_id = p_sender_account_id;

    UPDATE payments.accounts
    SET balance = balance + p_amount
    WHERE account_id = p_receiver_account_id;

    -- Record matching debit and credit entries.
    INSERT INTO payments.ledger_entries (
        transfer_id,
        account_id,
        entry_type,
        amount
    )
    VALUES
        (v_transfer_id, p_sender_account_id, 'debit', p_amount),
        (v_transfer_id, p_receiver_account_id, 'credit', p_amount);

    RETURN v_transfer_id;
END;
$$;
