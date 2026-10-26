
BEGIN;

DO $$
DECLARE
    v_transfer_id BIGINT;
    v_sender_balance NUMERIC(19, 2);
BEGIN
    -- Lock both accounts in a consistent order.
    PERFORM account_id
    FROM payments.accounts
    WHERE account_id IN (1, 2)
    ORDER BY account_id
    FOR UPDATE;

    -- Confirm that both accounts exist.
    IF (SELECT COUNT(*)
        FROM payments.accounts
        WHERE account_id IN (1, 2)) <> 2 THEN
        RAISE EXCEPTION 'Sender or receiver account does not exist';
    END IF;

    -- Check sender's available balance.
    SELECT balance
    INTO v_sender_balance
    FROM payments.accounts
    WHERE account_id = 1;

    IF v_sender_balance < 750.00 THEN
        RAISE EXCEPTION 'Insufficient funds';
    END IF;

    -- Create the transfer and capture its generated ID.
    INSERT INTO payments.transfers (
        sender_account_id,
        receiver_account_id,
        amount,
        status
    )
    VALUES (1, 2, 750.00, 'completed')
    RETURNING transfer_id INTO v_transfer_id;

    -- Update both account balances.
    UPDATE payments.accounts
    SET balance = balance - 750.00
    WHERE account_id = 1;

    UPDATE payments.accounts
    SET balance = balance + 750.00
    WHERE account_id = 2;

    -- Record the debit and credit.
    INSERT INTO payments.ledger_entries (
        transfer_id, account_id, entry_type, amount
    )
    VALUES
        (v_transfer_id, 1, 'debit', 750.00),
        (v_transfer_id, 2, 'credit', 750.00);
END;
$$;

COMMIT;
