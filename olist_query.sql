-- 1. Doanh nghiệp hiện đang kinh doanh những danh mục sản phẩm nào (bằng tiếng anh)?
SELECT 
	DISTINCT n.product_category_name_english
FROM products p
INNER JOIN product_category_name_translation n
	ON p.product_category_name = n.product_category_name

-- 2. Danh mục sản phẩm nào được mua nhiều nhất, và mức đóng góp của chúng vào tổng doanh thu là bao nhiêu?
WITH cte AS (
    SELECT DISTINCT p.product_id, n.product_category_name_english
    FROM products p
    INNER JOIN product_category_name_translation n
        ON p.product_category_name = n.product_category_name
),
category_revenue AS (
    SELECT 
        cte.product_category_name_english,
        COUNT(i.product_id) AS total_items,
        SUM(p.payment_value) AS total_revenue
    FROM orders o
    INNER JOIN order_items i
        ON o.order_id = i.order_id
    LEFT JOIN cte
        ON i.product_id = cte.product_id
    LEFT JOIN order_payments p
        ON o.order_id = p.order_id
    GROUP BY cte.product_category_name_english
)
SELECT 
    product_category_name_english,
    total_items,
    total_revenue,
    ROUND(100 * total_revenue / (SELECT SUM(total_revenue) FROM category_revenue), 2) AS percentage
FROM category_revenue
ORDER BY total_items DESC;

-- 3. Trong các danh mục bán chạy nhất, phân bố giá sản phẩm như thế nào (giá thấp nhất, cao nhất, trung bình)?
SELECT
    n.product_category_name_english,
    COUNT(*) AS total_items_sold,
    COUNT(DISTINCT o.order_id) AS total_orders,
    MIN(o.price) AS min_price,
    MAX(o.price) AS max_price,
    ROUND(AVG(o.price), 2) AS avg_price
FROM order_items o
INNER JOIN products p
    ON o.product_id = p.product_id
INNER JOIN product_category_name_translation n
    ON p.product_category_name = n.product_category_name
GROUP BY n.product_category_name_english
ORDER BY total_items_sold DESC;

-- 4. Trung bình giá trị đơn hàng (AOV) của khách là bao nhiêu?
WITH order_total AS (
    SELECT c.customer_unique_id, o.order_id, SUM(p.payment_value) AS order_value
    FROM orders o
    INNER JOIN order_payments p
        ON o.order_id = p.order_id
	INNER JOIN customers c
		ON o.customer_id = c.customer_id
    GROUP BY c.customer_unique_id, o.order_id
)
SELECT customer_unique_id,
       ROUND(AVG(order_value), 2) AS aov_per_customer
FROM order_total
GROUP BY customer_unique_id
ORDER BY aov_per_customer DESC;

-- 5. Trung bình một khách hàng mua bao nhiêu đơn?
WITH orders_per_customer AS (
    SELECT 
        c.customer_unique_id,
        COUNT(DISTINCT o.order_id) AS total_orders
    FROM orders o
	INNER JOIN customers c
	ON o.customer_id = c.customer_id
    GROUP BY customer_unique_id
)
SELECT ROUND(AVG(total_orders), 2) AS avg_orders_per_customer
FROM orders_per_customer;

-- 6. Doanh thu và số đơn hàng thay đổi thế nào theo từng tháng/quý?
SELECT 
    TO_CHAR(o.order_purchase_timestamp, 'YYYY-MM') AS year_month,
    COUNT(DISTINCT o.order_id) AS total_orders,
    ROUND(SUM(p.payment_value)::numeric, 2) AS total_revenue
FROM orders o
INNER JOIN order_payments p
    ON o.order_id = p.order_id
GROUP BY TO_CHAR(o.order_purchase_timestamp, 'YYYY-MM')
ORDER BY year_month;

-- 7. Có sự khác biệt nào về hành vi mua sắm giữa các khu vực/bang khác nhau?
SELECT
    g.geolocation_state,
    COUNT(DISTINCT o.order_id) AS total_orders,
    COUNT(DISTINCT c.customer_unique_id) AS total_customers,
    ROUND(SUM(p.payment_value), 2) AS total_revenue,
    ROUND(SUM(p.payment_value) * 1.0 / COUNT(DISTINCT o.order_id), 2) AS avg_order_value
FROM customers c
INNER JOIN orders o
    ON o.customer_id = c.customer_id
INNER JOIN order_payments p
    ON o.order_id = p.order_id
INNER JOIN geolocation g
    ON c.customer_zip_code_prefix = g.geolocation_zip_code_prefix
GROUP BY g.geolocation_state
ORDER BY total_revenue DESC;

8. Mỗi tháng có bao nhiêu khách hàng mới tham gia mua sắm (kích thước cohort)?
WITH first_purchase AS (
    SELECT 
        c.customer_unique_id,
        MIN(DATE_TRUNC('month', o.order_purchase_timestamp)) AS cohort_month
    FROM customers c
    INNER JOIN orders o
        ON c.customer_id = o.customer_id
    GROUP BY c.customer_unique_id
)
SELECT 
    cohort_month,
    COUNT(DISTINCT customer_unique_id) AS new_customers
FROM first_purchase
GROUP BY cohort_month
ORDER BY cohort_month;

-- 9. Có thể chia khách hàng thành các nhóm nào dựa trên điểm RFM?
WITH last_ref AS (
    SELECT MAX(order_purchase_timestamp) AS ref_date
    FROM orders
),
rfm AS (
    SELECT
        c.customer_unique_id,
        MAX(o.order_purchase_timestamp) AS last_order_date,
        COUNT(o.order_id) AS total_orders,
        SUM(oi.price) AS total_spent,
        lr.ref_date,
        DATE_PART('day', lr.ref_date - MAX(o.order_purchase_timestamp)) AS days_before_ref_date,
        COUNT(o.order_id) AS frequency,
        SUM(oi.price) AS monetary
    FROM customers c
    JOIN orders o ON c.customer_id = o.customer_id
    JOIN order_items oi ON o.order_id = oi.order_id
    CROSS JOIN last_ref lr
    GROUP BY c.customer_unique_id, lr.ref_date
),
rfm_scores AS (
    SELECT *,
        6 - NTILE(5) OVER (ORDER BY last_order_date DESC) AS r_score,
        NTILE(5) OVER (ORDER BY frequency ASC) AS f_score,
        NTILE(5) OVER (ORDER BY monetary ASC) AS m_score
    FROM rfm
),
rfm_code AS (
    SELECT *,
        CAST(r_score AS text) || CAST(f_score AS text) || CAST(m_score AS text) AS rfm_code
    FROM rfm_scores
)
SELECT 
    customer_unique_id,
    ref_date,
    last_order_date,
    days_before_ref_date,
    total_orders,
    total_spent,
    r_score,
    f_score,
    m_score,
    CASE
        WHEN rfm_code IN ('555','554','544','545','454','455','445') THEN 'Champions'
        WHEN rfm_code IN ('543','444','435','355','354','345','344','335') THEN 'Loyal Customers'
        WHEN rfm_code IN ('553','551','552','541','542','533','532','531','452','451','442','441','431','453','433','432','423','353','352','351','342','341','333','323') THEN 'Potential Loyalist'
        WHEN rfm_code IN ('512','511','422','421','412','411','311') THEN 'Recent Customers'
        WHEN rfm_code IN ('525','524','523','522','521','515','514','513','425','424','413','414','415','315','314','313') THEN 'Promising'
        WHEN rfm_code IN ('535','534','443','434','343','334','325','324') THEN 'Customers Needing Attention'
        WHEN rfm_code IN ('331','321','312','221','213') THEN 'About To Sleep'
        WHEN rfm_code IN ('255','254','245','244','253','252','243','242','235','234','225','224','153','152','145','143','142','135','134','133','125','124') THEN 'At Risk'
        WHEN rfm_code IN ('155','154','144','214','215','115','114','113') THEN 'Cannot Lose Them'
        WHEN rfm_code IN ('332','322','231','241','251','233','232','223','222','132','123','122','212','211') THEN 'Hibernating'
        ELSE 'Lost'
    END AS segment
FROM rfm_code
ORDER BY segment;

-- 10. Tỷ lệ doanh thu đến từ từng nhóm khách hàng là bao nhiêu?
WITH rfm AS (
    SELECT
        c.customer_unique_id,
        MAX(o.order_purchase_timestamp) AS last_purchase,
        COUNT(o.order_id) AS frequency,
        SUM(oi.price) AS monetary
    FROM customers c
    JOIN orders o ON c.customer_id = o.customer_id
    JOIN order_items oi ON o.order_id = oi.order_id
    GROUP BY c.customer_unique_id
),
rfm_scores AS (
    SELECT *,
        6 - NTILE(5) OVER (ORDER BY last_purchase DESC) AS r_score,
        NTILE(5) OVER (ORDER BY frequency ASC) AS f_score,
        NTILE(5) OVER (ORDER BY monetary ASC) AS m_score
    FROM rfm
),
rfm_code AS (
    SELECT *,
        CAST(r_score AS text) || CAST(f_score AS text) || CAST(m_score AS text) AS rfm_code
    FROM rfm_scores
),
rfm_segments AS (
    SELECT *,
        CASE
            WHEN rfm_code IN ('555','554','544','545','454','455','445') THEN 'Champions'
            WHEN rfm_code IN ('543','444','435','355','354','345','344','335') THEN 'Loyal Customers'
            WHEN rfm_code IN ('553','551','552','541','542','533','532','531','452','451','442','441','431','453','433','432','423','353','352','351','342','341','333','323') THEN 'Potential Loyalist'
            WHEN rfm_code IN ('512','511','422','421','412','411','311') THEN 'Recent Customers'
            WHEN rfm_code IN ('525','524','523','522','521','515','514','513','425','424','413','414','415','315','314','313') THEN 'Promising'
            WHEN rfm_code IN ('535','534','443','434','343','334','325','324') THEN 'Customers Needing Attention'
            WHEN rfm_code IN ('331','321','312','221','213') THEN 'About To Sleep'
            WHEN rfm_code IN ('255','254','245','244','253','252','243','242','235','234','225','224','153','152','145','143','142','135','134','133','125','124') THEN 'At Risk'
            WHEN rfm_code IN ('155','154','144','214','215','115','114','113') THEN 'Cannot Lose Them'
            WHEN rfm_code IN ('332','322','231','241','251','233','232','223','222','132','123','122','212','211') THEN 'Hibernating'
            ELSE 'Lost'
        END AS segment
    FROM rfm_code
)
SELECT segment,
       SUM(monetary) AS revenue,
       (SUM(monetary) * 100.0 / SUM(SUM(monetary)) OVER()) AS revenue_percentage
FROM rfm_segments
GROUP BY segment
ORDER BY revenue_percentage DESC;