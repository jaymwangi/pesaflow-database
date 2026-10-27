-- PesaFlow: Enforce ledger integrity for completed transfers.

-- Check that a completed transfer has exactly one valid debit
-- and exactly one valid credit, matching its accounts and amount.

CREATE OR REPLACE FUNCTION payments.assert_completed_transfer_ledger_pair(
    p_transfer_id BIGINT
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_sender_account_id BIGINT;
    v_receiver_account_id BIGINT;
    v_amount NUMERIC(19, 2);
    v_status TEXT;

    v_debit_count BIGINT;
    v_credit_count BIGINT;
    v_valid_debit_count BIGINT;
    v_valid_credit_count BIGINT;
BEGIN
    SELECT
        sender_account_id,
        receiver_account_id,
        amount,
        status
    INTO
        v_sender_account_id,
        v_receiver_account_id,
        v_amount,
        v_status
    FROM payments.transfers
    WHERE transfer_id = p_transfer_id;

    -- Only completed transfers require a complete ledger pair.
    IF NOT FOUND OR v_status <> 'completed' THEN
        RETURN;
    END IF;

    SELECT
        COUNT(*) FILTER (
            WHERE entry_type = 'debit'
        ),
        COUNT(*) FILTER (
            WHERE entry_type = 'credit'
        ),
        COUNT(*) FILTER (
            WHERE entry_type = 'debit'
              AND account_id = v_sender_account_id
              AND amount = v_amount
        ),
        COUNT(*) FILTER (
            WHERE entry_type = 'credit'
              AND account_id = v_receiver_account_id
              AND amount = v_amount
        )
    INTO
        v_debit_count,
        v_credit_count,
        v_valid_debit_count,
        v_valid_credit_count
    FROM payments.ledger_entries
    WHERE transfer_id = p_transfer_id;

    IF v_debit_count <> 1
       OR v_credit_count <> 1
       OR v_valid_debit_count <> 1
       OR v_valid_credit_count <> 1 THEN
        RAISE EXCEPTION
            'Completed transfer % must have exactly one matching debit and credit',
            p_transfer_id;
    END IF;
END;
$$;


-- Trigger dispatcher: validate the affected transfer(s) at commit.

CREATE OR REPLACE FUNCTION payments.enforce_completed_transfer_ledger_pair()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_TABLE_NAME = 'transfers' THEN
        PERFORM payments.assert_completed_transfer_ledger_pair(
            NEW.transfer_id
        );

    ELSIF TG_OP = 'INSERT' THEN
        PERFORM payments.assert_completed_transfer_ledger_pair(
            NEW.transfer_id
        );

    ELSIF TG_OP = 'DELETE' THEN
        PERFORM payments.assert_completed_transfer_ledger_pair(
            OLD.transfer_id
        );

    ELSE
        -- An update could move an entry between transfers.
        PERFORM payments.assert_completed_transfer_ledger_pair(
            OLD.transfer_id
        );

        IF NEW.transfer_id IS DISTINCT FROM OLD.transfer_id THEN
            PERFORM payments.assert_completed_transfer_ledger_pair(
                NEW.transfer_id
            );
        END IF;
    END IF;

    RETURN NULL;
END;
$$;


-- Check transfers inserted or updated, including status changes.
DROP TRIGGER IF EXISTS enforce_completed_transfer_ledger_pair_on_transfer
ON payments.transfers;

CREATE CONSTRAINT TRIGGER enforce_completed_transfer_ledger_pair_on_transfer
AFTER INSERT OR UPDATE ON payments.transfers
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW
EXECUTE FUNCTION payments.enforce_completed_transfer_ledger_pair();


-- Check ledger changes that could invalidate a completed transfer.
DROP TRIGGER IF EXISTS enforce_completed_transfer_ledger_pair_on_ledger
ON payments.ledger_entries;

CREATE CONSTRAINT TRIGGER enforce_completed_transfer_ledger_pair_on_ledger
AFTER INSERT OR UPDATE OR DELETE ON payments.ledger_entries
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW
EXECUTE FUNCTION payments.enforce_completed_transfer_ledger_pair();
