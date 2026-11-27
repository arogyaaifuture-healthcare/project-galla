-- Report queries (Section 30.2). Parameters: :'tenant_id', :'outlet_id' (uuid), :'d_from', :'d_to' (business dates, inclusive).
-- Rules: VOID bills are excluded everywhere; "net sales" = SUM(bill_lines.taxable_amount) (after discount, before tax);
-- every report must reconcile to SUM(bills.grand_total) of the same filter (gate RP9 returns zero rows).
-- RP1 category-wise sales (open items and lines without a menu item are shown, never dropped)
SELECT CASE WHEN oi.is_open_item THEN 'Open items' ELSE coalesce(mc.name,'Uncategorised') END AS category,
       sum(l.quantity) AS qty, sum(l.line_gross) AS gross, sum(l.discount_amount) AS discount, sum(l.taxable_amount) AS net_sales, sum(l.tax_amount) AS tax
FROM bills b JOIN orders o ON o.id=b.order_id JOIN bill_lines l ON l.bill_id=b.id AND l.active AND l.line_type='ITEM'
LEFT JOIN order_items oi ON oi.id=l.order_item_id LEFT JOIN menu_items mi ON mi.id=oi.menu_item_id LEFT JOIN menu_categories mc ON mc.id=mi.category_id
WHERE b.outlet_id=:'outlet_id' AND b.status<>'VOID' AND o.business_date BETWEEN :'d_from' AND :'d_to'
GROUP BY 1 ORDER BY net_sales DESC, category;
-- RP2 order-type / source-wise (dine-in, takeaway, delivery; partner orders split by partner)
SELECT o.order_type, o.order_source, coalesce(o.partner_name,'') AS partner, count(*) AS bills, sum(b.subtotal) AS subtotal, sum(b.discount_total) AS discount,
       sum(b.tax_total) AS tax, sum(b.grand_total) AS grand_total
FROM bills b JOIN orders o ON o.id=b.order_id
WHERE b.outlet_id=:'outlet_id' AND b.status<>'VOID' AND o.business_date BETWEEN :'d_from' AND :'d_to'
GROUP BY 1,2,3 ORDER BY 1,2,3;
-- RP3 cashier-wise (who generated the bill)
SELECT u.full_name AS cashier, count(*) AS bills, sum(b.discount_total) AS discount, sum(b.grand_total) AS grand_total
FROM bills b JOIN orders o ON o.id=b.order_id JOIN users u ON u.id=b.generated_by
WHERE b.outlet_id=:'outlet_id' AND b.status<>'VOID' AND o.business_date BETWEEN :'d_from' AND :'d_to'
GROUP BY u.id, u.full_name ORDER BY grand_total DESC, cashier;
-- RP4 table-wise (dine-in only)
SELECT t.name AS dining_table, count(*) AS bills, coalesce(sum(o.guest_count),0) AS covers, round(avg(b.grand_total),2) AS avg_bill, sum(b.grand_total) AS grand_total
FROM bills b JOIN orders o ON o.id=b.order_id JOIN dining_tables t ON t.id=o.table_id
WHERE b.outlet_id=:'outlet_id' AND b.status<>'VOID' AND o.business_date BETWEEN :'d_from' AND :'d_to'
GROUP BY t.id, t.name ORDER BY grand_total DESC, dining_table;
-- RP5 customer insights (visits, spend, last visit)
SELECT c.name, c.phone, count(*) AS visits, sum(b.grand_total) AS total_spend, round(avg(b.grand_total),2) AS avg_bill, max(o.business_date) AS last_visit
FROM bills b JOIN orders o ON o.id=b.order_id JOIN customers c ON c.id=o.customer_id
WHERE b.tenant_id=:'tenant_id' AND b.status<>'VOID' AND o.business_date BETWEEN :'d_from' AND :'d_to'
GROUP BY c.id ORDER BY total_spend DESC, c.name;
-- RP6 consolidated multi-outlet, per outlet and day, with a total row
SELECT coalesce(ou.code,'ALL') AS outlet, coalesce(o.business_date::text,'ALL') AS business_date, count(*) AS bills,
       sum(b.subtotal) AS subtotal, sum(b.discount_total) AS discount, sum(b.tax_total) AS tax, sum(b.grand_total) AS grand_total
FROM bills b JOIN orders o ON o.id=b.order_id JOIN outlets ou ON ou.id=b.outlet_id
WHERE b.tenant_id=:'tenant_id' AND b.status<>'VOID' AND o.business_date BETWEEN :'d_from' AND :'d_to'
GROUP BY ROLLUP (ou.code, o.business_date) ORDER BY 1,2;
-- RP7 monthly trend with growth over the previous month (NULL for the first month)
WITH m AS (SELECT date_trunc('month', o.business_date)::date AS month, sum(b.grand_total) AS grand_total, count(*) AS bills
           FROM bills b JOIN orders o ON o.id=b.order_id
           WHERE b.tenant_id=:'tenant_id' AND b.status<>'VOID' AND o.business_date BETWEEN :'d_from' AND :'d_to' GROUP BY 1)
SELECT month, bills, grand_total, round(100*(grand_total - lag(grand_total) OVER (ORDER BY month)) / NULLIF(lag(grand_total) OVER (ORDER BY month),0), 2) AS growth_percent
FROM m ORDER BY month;
-- RP8 payment-mode label summary (uses payment_modes labels when set, else the base method)
SELECT coalesce(pm.label, p.method) AS payment_mode, p.method, count(*) AS payments, sum(p.amount) AS amount
FROM payments p JOIN bills b ON b.id=p.bill_id JOIN orders o ON o.id=b.order_id LEFT JOIN payment_modes pm ON pm.id=p.payment_mode_id
WHERE b.outlet_id=:'outlet_id' AND b.status<>'VOID' AND p.status='SUCCESS' AND o.business_date BETWEEN :'d_from' AND :'d_to'
GROUP BY 1,2 ORDER BY 1;
-- RP9 reconciliation gate for one outlet: must return ZERO rows (a report export that returns a row here is refused: REPORT_NOT_RECONCILED)
WITH ref AS (SELECT coalesce(sum(b.grand_total),0) AS gt FROM bills b JOIN orders o ON o.id=b.order_id
             WHERE b.outlet_id=:'outlet_id' AND b.status<>'VOID' AND o.business_date BETWEEN :'d_from' AND :'d_to'),
rp2 AS (SELECT coalesce(sum(b.grand_total),0) AS gt FROM bills b JOIN orders o ON o.id=b.order_id
        WHERE b.outlet_id=:'outlet_id' AND b.status<>'VOID' AND o.business_date BETWEEN :'d_from' AND :'d_to'),
cat AS (SELECT coalesce(sum(l.taxable_amount + l.tax_amount),0) AS items FROM bills b JOIN orders o ON o.id=b.order_id
        JOIN bill_lines l ON l.bill_id=b.id AND l.active AND l.line_type='ITEM'
        WHERE b.outlet_id=:'outlet_id' AND b.status<>'VOID' AND o.business_date BETWEEN :'d_from' AND :'d_to'),
nonitems AS (SELECT coalesce(sum(l.taxable_amount + l.tax_amount),0) AS other FROM bills b JOIN orders o ON o.id=b.order_id
        JOIN bill_lines l ON l.bill_id=b.id AND l.active AND l.line_type<>'ITEM'
        WHERE b.outlet_id=:'outlet_id' AND b.status<>'VOID' AND o.business_date BETWEEN :'d_from' AND :'d_to'),
ro AS (SELECT coalesce(sum(b.round_off),0) AS r FROM bills b JOIN orders o ON o.id=b.order_id
       WHERE b.outlet_id=:'outlet_id' AND b.status<>'VOID' AND o.business_date BETWEEN :'d_from' AND :'d_to')
SELECT 'category+charges+round_off <> grand_total' AS problem, ref.gt, cat.items + nonitems.other + ro.r AS recomputed
FROM ref, cat, nonitems, ro WHERE ref.gt <> cat.items + nonitems.other + ro.r;
