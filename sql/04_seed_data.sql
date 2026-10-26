
-- PesaFlow: Seed development data
-- Run only against the local development database.

INSERT INTO payments.customers (full_name, email)
VALUES
    ('Mary Wanjiku', 'mary@example.com'),
    ('Peter Otieno', 'peter@example.com'),
    ('Amina Hassan', 'amina@example.com');

INSERT INTO payments.accounts (customer_id, currency, balance)
VALUES
    (
        (SELECT customer_id FROM payments.customers
         WHERE email = 'mary@example.com'),
        'KES',
        5000.00
    ),
    (
        (SELECT customer_id FROM payments.customers
         WHERE email = 'peter@example.com'),
        'KES',
        2000.00
    ),
    (
        (SELECT customer_id FROM payments.customers
         WHERE email = 'amina@example.com'),
        'KES',
        1500.00
    );
