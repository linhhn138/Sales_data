--1. Tính tỉ lệ đơn hàng thành công / tổng số đơn hàng của từng nhóm sản phẩm theo mùa 

WITH total_trans_cte AS
  (
    SELECT
        p.masterCategory,
        p.season,
        COUNT(DISTINCT CASE WHEN payment_status = 'Success' THEN t.booking_id END) AS success_trans,
        COUNT(DISTINCT CASE WHEN payment_status = 'Failed' THEN t.booking_id END) AS fail_trans,
        COUNT(DISTINCT t.booking_id) AS total_transactions
    FROM `project-thuhuyen-2023.K303.transaction` t
    JOIN `project-thuhuyen-2023.K303.product` p
      ON t.product_id = p.id
    WHERE p.season IS NOT NULL
    GROUP BY p.masterCategory, p.season
  )
SELECT
    masterCategory,
    season,
    success_trans,
    fail_trans,
    total_transactions,
    FORMAT('%.2f%%', success_trans * 100.0 / total_transactions) AS success_rate
FROM total_trans_cte
ORDER BY masterCategory, season;

--2. Tỷ lệ khách hàng mua hàng nhiều hơn 1 lần theo quốc gia

WITH cus_order_cte AS
  (
    SELECT
        customer_id
    FROM `project-thuhuyen-2023.K303.transaction`
    WHERE payment_status = 'Success'
    GROUP BY customer_id
    HAVING COUNT(DISTINCT booking_id) > 1
  )
SELECT
    home_location,
    COUNT(DISTINCT t.customer_id) AS total_customers,
    COUNT(DISTINCT e.customer_id) AS repeat_customers,
    FORMAT('%.2f%%', COUNT(DISTINCT e.customer_id) * 100.0 / COUNT(DISTINCT c.customer_id)) AS repeat_rate_pct
FROM `project-thuhuyen-2023.K303.transaction` t
JOIN `project-thuhuyen-2023.K303.customer` c
  ON c.customer_id = t.customer_id
LEFT JOIN cus_order_cte e
  ON c.customer_id = e.customer_id AND t.payment_status = 'Success'
GROUP BY home_location
ORDER BY repeat_rate_pct DESC;

--3. Tính tổng doanh thu, , số lượng giao dịch, số khách hàng các ngày trong tuần trong quý 2 năm 2017

SELECT
    '2017-Q2' AS quarter_year,
    FORMAT_DATE('%A', DATE(created_at)) AS day_of_week,
    COUNT(DISTINCT booking_id) AS total_transactions,
    COUNT(DISTINCT customer_id) AS total_customers,
    SUM(quantity*item_price) AS total_revenue
FROM `project-thuhuyen-2023.K303.transaction`
WHERE EXTRACT(YEAR FROM created_at) = 2017
  AND EXTRACT(QUARTER FROM created_at) = 2
  AND payment_status = 'Success'
GROUP BY day_of_week;

--4. Tính tổng doanh thu tích luỹ (cumulative revenue) theo từng tháng qua các năm 
--và tỉ lệ phần trăm doanh thu của từng tháng trên tổng doanh thu năm

WITH rev_cte AS
  (
    SELECT
        EXTRACT(YEAR FROM created_at) AS year,
        EXTRACT(MONTH FROM created_at) AS month,
        SUM(item_price*quantity) AS monthly_total
    FROM `project-thuhuyen-2023.K303.transaction`
    WHERE payment_status = 'Success'
    GROUP BY year, month
  )
SELECT year, month, monthly_total,
    SUM(monthly_total) OVER(ORDER BY year,month) AS cumulative_revenue,
    SUM(monthly_total) OVER(PARTITION BY year) AS total_year_revenue,
    FORMAT('%.2f%%',monthly_total*100/SUM(monthly_total) OVER(PARTITION BY year)) AS pct_monthly_per_year
FROM rev_cte
ORDER BY year, month;

-- 5. Phân nhóm khách hàng theo độ tuổi (18–25, 26–35, 36-45, 46-60, 60+)) và quốc gia (home_country), rồi tính:
--Tổng chi tiêu
--Chi tiêu trung bình mỗi giao dịch
--Chi tiêu trung bình mỗi khách hàng
--Số lượng khách hàng
--Số lượng giao dịch thành công

WITH age_cte AS
  (
    SELECT customer_id, home_location,
        DATE_DIFF(CURRENT_DATE(), birthdate, YEAR) AS age
    FROM `project-thuhuyen-2023.K303.customer`
  ),
group_age_cte AS
  (
    SELECT *,
        CASE
          WHEN age < 18 THEN '<18' -- vì có nhóm khách hàng dưới 18 tuổi nên em tạo thêm 1 age_group
          WHEN age BETWEEN 18 AND 25 THEN '18-25'
          WHEN age BETWEEN 26 AND 35 THEN '26-35'
          WHEN age BETWEEN 36 AND 45 THEN '36-45'
          WHEN age BETWEEN 46 AND 60 THEN '46-60'
          WHEN age > 60 THEN '60+'
        END AS age_group
    FROM age_cte
  ),
total_cte AS
  (
    SELECT home_location, age_group,
        COUNT(DISTINCT c.customer_id) AS total_customers,
        COUNT(DISTINCT booking_id) AS total_transactions,
        SUM(item_price*quantity) AS total_spending,
    FROM `project-thuhuyen-2023.K303.transaction` t
    JOIN group_age_cte c
      ON t.customer_id = c.customer_id
    WHERE payment_status = 'Success'
    GROUP BY home_location, age_group
  )
SELECT *,
    ROUND(total_spending/total_transactions,1) AS avg_spending_per_transaction,
    ROUND(total_spending/total_customers,1) AS avg_spending_per_customer
FROM total_cte
ORDER BY home_location;

--6. Tìm sản phẩm được mua nhiều nhất theo từng giới tính, kèm theo loại sản phẩm, tổng số lượng đã bán, tổng doanh thu và tổng số khách hàng đã mua trong quý 4 năm 2021 biết tổng doanh thu total_revenue = quantity*item_price

WITH gender_total_cte AS
  (
    SELECT product_id, gender,
        SUM(quantity) AS total_quantity,
        COUNT(t.customer_id) AS total_customer,
        SUM(quantity*item_price) AS total_revenue
    FROM `project-thuhuyen-2023.K303.transaction` t
    JOIN `project-thuhuyen-2023.K303.customer` c
      ON t.customer_id = c.customer_id
    WHERE payment_status = 'Success'
      AND EXTRACT(YEAR FROM created_at) = 2021
      AND EXTRACT(QUARTER FROM created_at) = 4
    GROUP BY product_id, gender
  ),
max_gender_cte AS
  (
    SELECT product_id, gender,total_quantity,total_revenue,total_customer,
        RANK() OVER(PARTITION BY gender ORDER BY total_quantity DESC) AS rank_by_gender
    FROM gender_total_cte
  )
SELECT product_id, productDisplayName, masterCategory, subCategory, articleType
    total_quantity,total_revenue,
    total_customer
FROM `project-thuhuyen-2023.K303.product` p
JOIN max_gender_cte m
  ON p.id = m.product_id
WHERE rank_by_gender = 1;

--7. Tìm các khách hàng thuộc top 6 chi tiêu nhiều nhất trong năm 2022

WITH cus_spent_cte AS --tính tổng chi tiêu của khách hàng từ năm 2016 đến năm 2022
  (
    SELECT customer_id,
        EXTRACT(YEAR FROM created_at) AS year,
        SUM(quantity*item_price) AS total_spent,
        COUNT(DISTINCT booking_id) AS total_trans
    FROM `project-thuhuyen-2023.K303.transaction`
    WHERE EXTRACT(YEAR FROM created_at) BETWEEN 2016 AND 2022
      AND payment_status = 'Success'
    GROUP BY customer_id,year
  ),
rank_cus_cte AS --chia rank cho các khách hàng có chi tiêu trong năm 2022
  (
    SELECT customer_id,
        RANK() OVER(ORDER BY total_spent DESC) AS rank_cus
    FROM cus_spent_cte
    WHERE year = 2022
  ),
sum_rev_year_cte AS --tìm tổng chi tiêu và số giao dịch trong các năm từ 2016-2020
  (SELECT
        a.customer_id,
        MAX(CASE WHEN a.year = 2016 THEN a.total_spent ELSE 0 END) AS total_spent_2016,
        MAX(CASE WHEN a.year = 2016 THEN a.total_trans ELSE 0 END) AS total_trans_2016,
        MAX(CASE WHEN a.year = 2017 THEN a.total_spent ELSE 0 END) AS total_spent_2017,
        MAX(CASE WHEN a.year = 2017 THEN a.total_trans ELSE 0 END) AS total_trans_2017,
        MAX(CASE WHEN a.year = 2018 THEN a.total_spent ELSE 0 END) AS total_spent_2018,
        MAX(CASE WHEN a.year = 2018 THEN a.total_trans ELSE 0 END) AS total_trans_2018,
        MAX(CASE WHEN a.year = 2019 THEN a.total_spent ELSE 0 END) AS total_spent_2019,
        MAX(CASE WHEN a.year = 2019 THEN a.total_trans ELSE 0 END) AS total_trans_2019,
        MAX(CASE WHEN a.year = 2020 THEN a.total_spent ELSE 0 END) AS total_spent_2020,
        MAX(CASE WHEN a.year = 2020 THEN a.total_trans ELSE 0 END) AS total_trans_2020
    FROM cus_spent_cte a
    JOIN project-thuhuyen-2023.K303.transaction t
      ON a.customer_id = t.customer_id
    GROUP BY a.customer_id
    )
SELECT t.customer_id, -- show top 6 người có chi tiêu nhiều nhất trong năm 2022
    CONCAT(first_name,' ',last_name) AS full_name,
    email, home_country,
    total_spent_2016, total_trans_2016,
    total_spent_2017, total_trans_2017,
    total_spent_2018, total_trans_2018,
    total_spent_2019, total_trans_2019,
    total_spent_2020, total_trans_2020
FROM `project-thuhuyen-2023.K303.transaction` t
JOIN `project-thuhuyen-2023.K303.customer` c
  ON c.customer_id = t.customer_id
JOIN sum_rev_year_cte s
  ON s.customer_id = t.customer_id
JOIN rank_cus_cte r
  ON r.customer_id = t.customer_id
WHERE rank_cus <= 6;

--8. Tìm các sản phẩm có doanh thu tăng liên tục trong bất kỳ 7 năm liên tiếp và trả ra kết quả tổng doanh thu trong từng năm kể từ năm đầu tiên (year_start).

WITH rev_cte AS -- tìm revenue của từng năm
  (
    SELECT product_id,
        EXTRACT(YEAR FROM created_at) AS year_start,
        SUM(quantity * item_price) AS revenue
    FROM `project-thuhuyen-2023.K303.transaction`
    WHERE payment_status = 'Success'
    GROUP BY product_id, year_start
  ),
lead_rev_cte AS
  (
    SELECT product_id, year_start,
        revenue AS revenue_year_1,
        LEAD(revenue,1) OVER(PARTITION BY product_id ORDER BY year_start) AS revenue_year_2,
        LEAD(revenue,2) OVER(PARTITION BY product_id ORDER BY year_start) AS revenue_year_3,
        LEAD(revenue,3) OVER(PARTITION BY product_id ORDER BY year_start) AS revenue_year_4,
        LEAD(revenue,4) OVER(PARTITION BY product_id ORDER BY year_start) AS revenue_year_5,
        LEAD(revenue,5) OVER(PARTITION BY product_id ORDER BY year_start) AS revenue_year_6,
        LEAD(revenue,6) OVER(PARTITION BY product_id ORDER BY year_start) AS revenue_year_7
    FROM rev_cte
  )
SELECT product_id, productDisplayName, gender,
  masterCategory, subCategory, year_start,
  revenue_year_1, revenue_year_2, revenue_year_3,
  revenue_year_4, revenue_year_5, revenue_year_6,
  revenue_year_7
FROM `project-thuhuyen-2023.K303.product` p
JOIN lead_rev_cte l
ON p.id = l.product_id
WHERE revenue_year_1 < revenue_year_2
  AND revenue_year_2 < revenue_year_3
  AND revenue_year_3 < revenue_year_4
  AND revenue_year_4 < revenue_year_5
  AND revenue_year_5 < revenue_year_6
  AND revenue_year_6 < revenue_year_7
ORDER BY year_start, product_id;

--9. So sánh tỷ lệ chốt đơn hàng (conversion_rate_pct)  theo session giữa các khoảng thời gian ngày 
--(từ ngày  0 đến 10, 11 đến 20, từ ngày 21 trở đi) trong từng tháng, 
-- biết: conversion_rate = (Số session có ít nhất 1 lần "BOOKING") / (Tổng số session) × 100

WITH day_range_cte AS --chia group cho các ngày
  (
    SELECT DISTINCT session_id, event_name,
        FORMAT_TIMESTAMP('%Y-%m', event_time) AS year_month,
        CASE
          WHEN EXTRACT(DAY FROM event_time) BETWEEN 1 AND 10 THEN 'day_01_10'
          WHEN EXTRACT(DAY FROM event_time) BETWEEN 11 AND 20 THEN 'day_11_20'
          ELSE 'day_21_end'
        END AS date_range
    FROM `project-thuhuyen-2023.K303.click_stream`
  )
SELECT year_month, date_range,
    COUNT(DISTINCT session_id) AS total_sessions,
    COUNT(CASE WHEN event_name = 'BOOKING' THEN session_id END) AS sessions_with_booking,
    FORMAT('%.2f%%',COUNT(CASE WHEN event_name = 'BOOKING' THEN session_id END)*100/COUNT(DISTINCT session_id)) AS conversion_rate_pct
FROM day_range_cte
GROUP BY year_month, date_range
ORDER BY year_month, date_range;

--10. Tính tỷ trọng số session mà khách hàng bỏ sản phẩm vào giở hàng (ADD_TO_CART) nhưng không đi tới mua hàng (BOOKING), 
-- biết:  Percent_no_booking =   (no_booking_sessions  / total_add_to_cart_session) * 100

WITH add_to_cart_sessions_cte AS -- tìm những session có add_to_cart
  (
    SELECT DISTINCT session_id,
        FORMAT_TIMESTAMP('%Y-%m', event_time) AS month
    FROM `project-thuhuyen-2023.K303.click_stream`
    WHERE event_name = 'ADD_TO_CART'
  ),
booking_sessions_cte AS -- tìm những session có booking
  (
    SELECT DISTINCT session_id
    FROM `project-thuhuyen-2023.K303.click_stream`
    WHERE event_name = 'BOOKING'
  ),
no_booking_sessions_cte AS -- tìm những session ko có booking
  (
    SELECT a.session_id, a.month
    FROM add_to_cart_sessions_cte a
    LEFT JOIN booking_sessions_cte b
      ON a.session_id = b.session_id
    WHERE b.session_id IS NULL
  )
SELECT a.month,
    COUNT(a.session_id) AS total_add_to_cart_sessions,
    COUNT(n.session_id) AS no_booking_sessions,
    FORMAT('%.2f%%', SAFE_DIVIDE(COUNT(n.session_id) * 100, COUNT(a.session_id))) AS percent_no_booking
FROM add_to_cart_sessions_cte a
LEFT JOIN no_booking_sessions_cte n
  ON a.session_id = n.session_id
GROUP BY a.month
ORDER BY a.month;
