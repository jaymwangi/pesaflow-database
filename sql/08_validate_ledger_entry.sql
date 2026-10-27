
-- PesaFlow: Validate ledger entries against their transfer.

CREATE OR REPLACE FUNCTION payments.validate_ledger_entry()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_sender_account_id BIGINT;
    v_receiver_account_id BIGINT;
    v_transfer_amount NUMERIC(19, 2);
BEGIN
    SELECT
        sender_account_id,
        receiver_account_id,
        amount
    INTO
        v_sender_account_id,
        v_receiver_account_id,
        v_transfer_amount
    FROM payments.transfers
    WHERE transfer_id = NEW.transfer_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Transfer % does not exist', NEW.transfer_id;
    END IF;

    IF NEW.amount <> v_transfer_amount THEN
        RAISE EXCEPTION
            'Ledger amount % must match transfer amount %',
            NEW.amount, v_transfer_amount;
    END IF;

    IF NEW.entry_type = 'debit'
       AND NEW.account_id <> v_sender_account_id THEN
        RAISE EXCEPTION
            'Debit entry must belong to the sender account';
    END IF;

    IF NEW.entry_type = 'credit'
       AND NEW.account_id <> v_receiver_account_id THEN
        RAISE EXCEPTION
            'Credit entry must belong to the receiver account';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS validate_ledger_entry_before_insert
ON payments.ledger_entries;

CREATE TRIGGER validate_ledger_entry_before_insert
BEFORE INSERT ON payments.ledger_entries
FOR EACH ROW
EXECUTE FUNCTION payments.validate_ledger_entry();
