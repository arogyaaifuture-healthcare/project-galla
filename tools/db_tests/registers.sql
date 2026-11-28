-- Register queries (Section 28.B). Parameters: :outlet_id (uuid), :d_from, :d_to (business dates, inclusive). VOID bills are excluded everywhere.
-- R1 sales register, one row per bill
SELECT o.business_date, b.bill_number, coalesce(b.document_title,'BILL') AS document_title, b.status, b.customer_name, b.buyer_gstin, b.place_of_supply_state_code,
       coalesce(sum(l.line_gross) FILTER (WHERE l.line_type='ITEM'),0.00) AS gross_items, b.discount_total,
       coalesce(sum(l.taxable_amount),0.00) AS taxable_value, b.tax_total, b.round_off, b.grand_total
FROM bills b JOIN orders o ON o.id=b.order_id LEFT JOIN bill_lines l ON l.bill_id=b.id AND l.active
WHERE b.outlet_id=:outlet_id AND b.status<>'VOID' AND o.business_date BETWEEN :d_from AND :d_to
GROUP BY o.business_date, b.id ORDER BY o.business_date, b.bill_number;
-- R2 sales by tax rate, per bill (a bill's rate = sum of its component rates on the line; CGST 2.5 + SGST 2.5 = 5.00)
SELECT b.bill_number, lr.rate_percent, sum(lr.taxable_amount) AS taxable_value, sum(lr.tax_amount) AS tax_amount, sum(lr.line_total) AS line_total
FROM bills b JOIN orders o ON o.id=b.order_id
JOIN (SELECT l.bill_id, l.id, l.taxable_amount, l.tax_amount, l.line_total,
             coalesce((SELECT sum(t.rate_percent) FROM bill_line_taxes t WHERE t.bill_line_id=l.id),0.00) AS rate_percent
      FROM bill_lines l WHERE l.active) lr ON lr.bill_id=b.id
WHERE b.outlet_id=:outlet_id AND b.status<>'VOID' AND o.business_date BETWEEN :d_from AND :d_to
GROUP BY b.bill_number, lr.rate_percent ORDER BY b.bill_number, lr.rate_percent;
-- R3 HSN summary (lines without a code are grouped under '' and flagged, never dropped)
SELECT coalesce(l.hsn_sac_code,'') AS hsn_sac_code, lr.rate_percent, sum(CASE WHEN l.line_type='ITEM' THEN l.quantity ELSE 0 END) AS quantity,
       sum(l.taxable_amount) AS taxable_value, sum(l.tax_amount) AS tax_amount, sum(l.line_total) AS line_total,
       bool_or(l.hsn_sac_code IS NULL) AS lines_without_hsn_flag
FROM bills b JOIN orders o ON o.id=b.order_id JOIN bill_lines l ON l.bill_id=b.id AND l.active
CROSS JOIN LATERAL (SELECT coalesce(sum(t.rate_percent),0.00) AS rate_percent FROM bill_line_taxes t WHERE t.bill_line_id=l.id) lr
WHERE b.outlet_id=:outlet_id AND b.status<>'VOID' AND o.business_date BETWEEN :d_from AND :d_to
GROUP BY coalesce(l.hsn_sac_code,''), lr.rate_percent ORDER BY 1,2;
-- R4 tax summary by component
SELECT t.component_name, t.rate_percent, sum(t.taxable_amount) AS taxable_value, sum(t.tax_amount) AS tax_amount
FROM bills b JOIN orders o ON o.id=b.order_id JOIN bill_lines l ON l.bill_id=b.id AND l.active JOIN bill_line_taxes t ON t.bill_line_id=l.id
WHERE b.outlet_id=:outlet_id AND b.status<>'VOID' AND o.business_date BETWEEN :d_from AND :d_to
GROUP BY t.component_name, t.rate_percent ORDER BY 1,2;
-- R5 payment-mode summary (SUCCESS payments of live bills; the method of a bill that is only partly paid still counts what was received)
SELECT p.method, count(*) AS payments, sum(p.amount) AS amount
FROM payments p JOIN bills b ON b.id=p.bill_id JOIN orders o ON o.id=b.order_id
WHERE b.outlet_id=:outlet_id AND b.status<>'VOID' AND p.status='SUCCESS' AND o.business_date BETWEEN :d_from AND :d_to
GROUP BY p.method ORDER BY p.method;
-- R6 reconciliation check (must return zero rows; the export refuses to produce a file otherwise and raises REGISTER_NOT_RECONCILED)
SELECT b.bill_number, b.grand_total, (sum(l.taxable_amount) + b.tax_total + b.round_off) AS recomputed
FROM bills b JOIN orders o ON o.id=b.order_id JOIN bill_lines l ON l.bill_id=b.id AND l.active
WHERE b.outlet_id=:outlet_id AND b.status<>'VOID' AND o.business_date BETWEEN :d_from AND :d_to
GROUP BY b.id HAVING sum(l.taxable_amount) + b.tax_total + b.round_off <> b.grand_total;
