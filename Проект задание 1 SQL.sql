DROP DATABASE Customers_transactions;
CREATE DATABASE Customers_transactions;

USE Customers_transactions;

SET SQL_SAFE_UPDATES = 0;

UPDATE customers SET Gender = NULL WHERE Gender ='';
UPDATE customers SET Age = NULL WHERE Age = ''; 
ALTER TABLE customers MODIFY AGE INT NULL;

SELECT * FROM customers;

CREATE TABLE Transactions
    (date_new        DATE,
    Id_check        INT,
    ID_client       INT,
    Count_products  DECIMAL(10,3),
    Sum_payment     DECIMAL(10,2));

LOAD DATA INFILE "C:\\ProgramData\\MySQL\\MySQL Server 8.0\\Uploads\\transactions_info_work.csv"
INTO TABLE Transactions
FIELDS TERMINATED BY ','
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

SHOW VARIABLES LIKE 'secure_file_priv';

SELECT * FROM Transactions;

-- 1. Клиенты с непрерывной историей (операции в каждом из 13 месяцев)
WITH tx AS (
    SELECT *
    FROM Transactions
    WHERE date_new >= '2015-06-01' AND date_new <= '2016-06-01'
),
continuous AS (
    SELECT ID_client
    FROM tx
    GROUP BY ID_client
    HAVING COUNT(DISTINCT DATE_FORMAT(date_new, '%Y-%m')) = 13
)
SELECT
    t.ID_client,
    COALESCE(NULLIF(TRIM(c.Gender), ''), 'NA') AS Gender,
    NULLIF(c.Age, 0)                           AS Age,
    ROUND(SUM(t.Sum_payment) / COUNT(DISTINCT t.Id_check), 2) AS avg_check,
    ROUND(SUM(t.Sum_payment) / 13, 2)                           AS avg_month_sum,
    COUNT(DISTINCT t.Id_check)                                  AS operations_cnt,
    COUNT(*)                                                    AS lines_cnt,
    ROUND(SUM(t.Sum_payment), 2)                                AS total_sum
FROM tx t
JOIN continuous  k ON k.ID_client = t.ID_client
LEFT JOIN customers c ON c.Id_client = t.ID_client
GROUP BY t.ID_client, c.Gender, c.Age
ORDER BY t.ID_client;

-- 2 a–d. Показатели в разрезе месяцев
-- ---------------------------------------------------------------------
WITH tx AS (
    SELECT *
    FROM Transactions
    WHERE date_new >= '2015-06-01' AND date_new <= '2016-06-01'
),
m AS (
    SELECT
        DATE_FORMAT(date_new, '%Y-%m') AS ym,
        SUM(Sum_payment)               AS month_sum,
        COUNT(DISTINCT Id_check)       AS month_ops,
        COUNT(DISTINCT ID_client)      AS month_clients
    FROM tx
    GROUP BY DATE_FORMAT(date_new, '%Y-%m')
)
SELECT
    ym,
    ROUND(month_sum, 2)                                   AS month_sum,
    month_ops,
    ROUND(month_sum / month_ops, 2)                       AS a_avg_check,
    ROUND(month_ops / month_clients, 2)                   AS b_avg_ops_per_client,
    month_clients                                         AS c_clients_with_ops,
    ROUND(month_ops * 100 / SUM(month_ops) OVER (), 2)    AS d_ops_share_of_year_pct,
    ROUND(month_sum * 100 / SUM(month_sum) OVER (), 2)    AS d_sum_share_of_year_pct
FROM m
ORDER BY ym;

-- среднее по 13 месяцам (строка «Итого / среднее»)
WITH tx AS (
    SELECT *
    FROM Transactions
    WHERE date_new >= '2015-06-01' AND date_new <= '2016-06-01'
),
m AS (
    SELECT DATE_FORMAT(date_new, '%Y-%m') AS ym,
           SUM(Sum_payment) AS month_sum,
           COUNT(DISTINCT Id_check)  AS month_ops,
           COUNT(DISTINCT ID_client) AS month_clients
    FROM tx
    GROUP BY DATE_FORMAT(date_new, '%Y-%m')
)
SELECT
    ROUND(AVG(month_sum / month_ops), 2)     AS avg_of_monthly_avg_check,
    ROUND(AVG(month_ops), 2)                 AS avg_ops_per_month,
    ROUND(AVG(month_ops / month_clients), 2) AS avg_ops_per_client_per_month,
    ROUND(AVG(month_clients), 2)             AS avg_clients_per_month
FROM m;


-- 2 e. Соотношение M / F / NA по месяцам и доля затрат
WITH tx AS (
    SELECT t.*,
           COALESCE(NULLIF(TRIM(c.Gender), ''), 'NA') AS gender
    FROM Transactions t
    LEFT JOIN customers c ON c.Id_client = t.ID_client
    WHERE t.date_new >= '2015-06-01' AND t.date_new <= '2016-06-01'
),
g AS (
    SELECT DATE_FORMAT(date_new, '%Y-%m') AS ym,
           gender,
           COUNT(DISTINCT ID_client) AS clients,
           COUNT(DISTINCT Id_check)  AS ops,
           SUM(Sum_payment)          AS spend
    FROM tx
    GROUP BY DATE_FORMAT(date_new, '%Y-%m'), gender
)
SELECT
    ym,
    gender,
    clients,
    ROUND(clients * 100 / SUM(clients) OVER (PARTITION BY ym), 2) AS clients_share_pct,
    ops,
    ROUND(ops     * 100 / SUM(ops)     OVER (PARTITION BY ym), 2) AS ops_share_pct,
    ROUND(spend, 2)                                              AS spend,
    ROUND(spend   * 100 / SUM(spend)   OVER (PARTITION BY ym), 2) AS spend_share_pct
FROM g
ORDER BY ym, FIELD(gender, 'M', 'F', 'NA');


-- 3. Возрастные группы (шаг 10 лет) + клиенты без возраста
-- 3.1 За весь период
WITH tx AS (
    SELECT t.*,
           CASE WHEN NULLIF(c.Age, 0) IS NULL THEN 'Нет данных'
                ELSE CONCAT(FLOOR(c.Age / 10) * 10, '-', FLOOR(c.Age / 10) * 10 + 9)
           END AS age_group,
           CASE WHEN NULLIF(c.Age, 0) IS NULL THEN 999 ELSE FLOOR(c.Age / 10) END AS age_ord
    FROM Transactions t
    LEFT JOIN customers c ON c.Id_client = t.ID_client
    WHERE t.date_new >= '2015-06-01' AND t.date_new <= '2016-06-01'
),
a AS (
    SELECT age_group, age_ord,
           COUNT(DISTINCT ID_client) AS clients,
           SUM(Sum_payment)          AS total_sum,
           COUNT(DISTINCT Id_check)  AS ops
    FROM tx
    GROUP BY age_group, age_ord
)
SELECT
    age_group,
    clients,
    ROUND(total_sum, 2)                                   AS total_sum,
    ops,
    ROUND(total_sum * 100 / SUM(total_sum) OVER (), 2)    AS sum_share_pct,
    ROUND(ops * 100 / SUM(ops) OVER (), 2)                AS ops_share_pct,
    ROUND(total_sum / ops, 2)                             AS avg_check
FROM a
ORDER BY age_ord;

-- 3.2 Поквартально: средние показатели и доли
WITH tx AS (
    SELECT t.*,
           CONCAT(YEAR(t.date_new), '-Q', QUARTER(t.date_new)) AS yq,
           CASE WHEN NULLIF(c.Age, 0) IS NULL THEN 'Нет данных'
                ELSE CONCAT(FLOOR(c.Age / 10) * 10, '-', FLOOR(c.Age / 10) * 10 + 9)
           END AS age_group,
           CASE WHEN NULLIF(c.Age, 0) IS NULL THEN 999 ELSE FLOOR(c.Age / 10) END AS age_ord
    FROM Transactions t
    LEFT JOIN customers c ON c.Id_client = t.ID_client
    WHERE t.date_new >= '2015-06-01' AND t.date_new <= '2016-06-01'
),
qm AS (   																			-- сколько месяцев периода попадает в квартал
    SELECT yq, COUNT(DISTINCT DATE_FORMAT(date_new, '%Y-%m')) AS months_in_q
    FROM tx GROUP BY yq
),
q AS (
    SELECT yq, age_group, age_ord,
           COUNT(DISTINCT ID_client) AS clients,
           SUM(Sum_payment)          AS q_sum,
           COUNT(DISTINCT Id_check)  AS q_ops
    FROM tx
    GROUP BY yq, age_group, age_ord
)
SELECT
    q.yq,
    q.age_group,
    qm.months_in_q,
    q.clients,
    ROUND(q.q_sum, 2)                                                   AS q_sum,
    q.q_ops,
    ROUND(q.q_sum / q.q_ops, 2)                                         AS avg_check,
    ROUND(q.q_sum / qm.months_in_q, 2)                                  AS avg_month_sum,
    ROUND(q.q_ops / qm.months_in_q, 2)                                  AS avg_month_ops,
    ROUND(q.q_sum / q.clients, 2)                                       AS avg_sum_per_client,
    ROUND(q.q_ops / q.clients, 2)                                       AS avg_ops_per_client,
    ROUND(q.q_sum   * 100 / SUM(q.q_sum)   OVER (PARTITION BY q.yq), 2) AS sum_share_pct,
    ROUND(q.q_ops   * 100 / SUM(q.q_ops)   OVER (PARTITION BY q.yq), 2) AS ops_share_pct,
    ROUND(q.clients * 100 / SUM(q.clients) OVER (PARTITION BY q.yq), 2) AS clients_share_pct
FROM q
JOIN qm ON qm.yq = q.yq
ORDER BY q.yq, q.age_ord;

-- 3.2 Поквартально (сводный вид): средние показатели
-- по возрастным группам; 2015-Q2 = только июнь 2015
WITH tx AS (
    SELECT t.*,
           CONCAT(YEAR(t.date_new), '-Q', QUARTER(t.date_new)) AS yq,
           CASE WHEN NULLIF(c.Age, 0) IS NULL THEN 'Нет данных'
                ELSE CONCAT(FLOOR(c.Age / 10) * 10, '-', FLOOR(c.Age / 10) * 10 + 9)
           END AS age_group,
           CASE WHEN NULLIF(c.Age, 0) IS NULL THEN 999 ELSE FLOOR(c.Age / 10) END AS age_ord
    FROM Transactions t
    LEFT JOIN customers c ON c.Id_client = t.ID_client
    WHERE t.date_new >= '2015-06-01' AND t.date_new <= '2016-06-01'
),
g AS (   																				-- группа x квартал, группа x весь период, итоги
    SELECT age_group, age_ord, yq,
           SUM(Sum_payment) AS q_sum, COUNT(DISTINCT Id_check) AS q_ops, COUNT(DISTINCT ID_client) AS q_cl
    FROM tx GROUP BY age_group, age_ord, yq
    UNION ALL
    SELECT age_group, age_ord, 'ALL',
           SUM(Sum_payment), COUNT(DISTINCT Id_check), COUNT(DISTINCT ID_client)
    FROM tx GROUP BY age_group, age_ord
    UNION ALL
    SELECT 'Итого', 1000, yq,
           SUM(Sum_payment), COUNT(DISTINCT Id_check), COUNT(DISTINCT ID_client)
    FROM tx GROUP BY yq
    UNION ALL
    SELECT 'Итого', 1000, 'ALL',
           SUM(Sum_payment), COUNT(DISTINCT Id_check), COUNT(DISTINCT ID_client)
    FROM tx
),
qm AS (  																				-- месяцев в квартале / в периоде
    SELECT yq, COUNT(DISTINCT DATE_FORMAT(date_new, '%Y-%m')) AS months FROM tx GROUP BY yq
    UNION ALL
    SELECT 'ALL', COUNT(DISTINCT DATE_FORMAT(date_new, '%Y-%m')) FROM tx
),
tot AS (
    SELECT yq, q_sum AS t_sum, q_ops AS t_ops, q_cl AS t_cl FROM g WHERE age_group = 'Итого'
)
SELECT
    g.age_group AS `Возрастная группа`,
    ROUND(MAX(CASE WHEN g.yq = '2015-Q2' THEN g.q_sum / g.q_ops END), 2) AS `Средний чек 2015-Q2`,
    ROUND(MAX(CASE WHEN g.yq = '2015-Q3' THEN g.q_sum / g.q_ops END), 2) AS `Средний чек 2015-Q3`,
    ROUND(MAX(CASE WHEN g.yq = '2015-Q4' THEN g.q_sum / g.q_ops END), 2) AS `Средний чек 2015-Q4`,
    ROUND(MAX(CASE WHEN g.yq = '2016-Q1' THEN g.q_sum / g.q_ops END), 2) AS `Средний чек 2016-Q1`,
    ROUND(MAX(CASE WHEN g.yq = '2016-Q2' THEN g.q_sum / g.q_ops END), 2) AS `Средний чек 2016-Q2`,
    ROUND(MAX(CASE WHEN g.yq = 'ALL'     THEN g.q_sum / g.q_ops END), 2) AS `Средний чек весь период`,
    ROUND(MAX(CASE WHEN g.yq = '2015-Q2' THEN g.q_ops / g.q_cl END), 2) AS `Операций на клиента 2015-Q2`,
    ROUND(MAX(CASE WHEN g.yq = '2015-Q3' THEN g.q_ops / g.q_cl END), 2) AS `Операций на клиента 2015-Q3`,
    ROUND(MAX(CASE WHEN g.yq = '2015-Q4' THEN g.q_ops / g.q_cl END), 2) AS `Операций на клиента 2015-Q4`,
    ROUND(MAX(CASE WHEN g.yq = '2016-Q1' THEN g.q_ops / g.q_cl END), 2) AS `Операций на клиента 2016-Q1`,
    ROUND(MAX(CASE WHEN g.yq = '2016-Q2' THEN g.q_ops / g.q_cl END), 2) AS `Операций на клиента 2016-Q2`,
    ROUND(MAX(CASE WHEN g.yq = 'ALL'     THEN g.q_ops / g.q_cl END), 2) AS `Операций на клиента весь период`,
    ROUND(MAX(CASE WHEN g.yq = '2015-Q2' THEN g.q_sum / g.q_cl END), 2) AS `Сумма на клиента 2015-Q2`,
    ROUND(MAX(CASE WHEN g.yq = '2015-Q3' THEN g.q_sum / g.q_cl END), 2) AS `Сумма на клиента 2015-Q3`,
    ROUND(MAX(CASE WHEN g.yq = '2015-Q4' THEN g.q_sum / g.q_cl END), 2) AS `Сумма на клиента 2015-Q4`,
    ROUND(MAX(CASE WHEN g.yq = '2016-Q1' THEN g.q_sum / g.q_cl END), 2) AS `Сумма на клиента 2016-Q1`,
    ROUND(MAX(CASE WHEN g.yq = '2016-Q2' THEN g.q_sum / g.q_cl END), 2) AS `Сумма на клиента 2016-Q2`,
    ROUND(MAX(CASE WHEN g.yq = 'ALL'     THEN g.q_sum / g.q_cl END), 2) AS `Сумма на клиента весь период`,
    ROUND(MAX(CASE WHEN g.yq = '2015-Q2' THEN g.q_sum / qm.months END), 2) AS `Сумма в месяц 2015-Q2`,
    ROUND(MAX(CASE WHEN g.yq = '2015-Q3' THEN g.q_sum / qm.months END), 2) AS `Сумма в месяц 2015-Q3`,
    ROUND(MAX(CASE WHEN g.yq = '2015-Q4' THEN g.q_sum / qm.months END), 2) AS `Сумма в месяц 2015-Q4`,
    ROUND(MAX(CASE WHEN g.yq = '2016-Q1' THEN g.q_sum / qm.months END), 2) AS `Сумма в месяц 2016-Q1`,
    ROUND(MAX(CASE WHEN g.yq = '2016-Q2' THEN g.q_sum / qm.months END), 2) AS `Сумма в месяц 2016-Q2`,
    ROUND(MAX(CASE WHEN g.yq = 'ALL'     THEN g.q_sum / qm.months END), 2) AS `Сумма в месяц весь период`
FROM g
JOIN qm  ON qm.yq  = g.yq
JOIN tot ON tot.yq = g.yq
GROUP BY g.age_group, g.age_ord
ORDER BY g.age_ord;

-- 3.3 Поквартально (сводный вид): доли, %
WITH tx AS (
    SELECT t.*,
           CONCAT(YEAR(t.date_new), '-Q', QUARTER(t.date_new)) AS yq,
           CASE WHEN NULLIF(c.Age, 0) IS NULL THEN 'Нет данных'
                ELSE CONCAT(FLOOR(c.Age / 10) * 10, '-', FLOOR(c.Age / 10) * 10 + 9)
           END AS age_group,
           CASE WHEN NULLIF(c.Age, 0) IS NULL THEN 999 ELSE FLOOR(c.Age / 10) END AS age_ord
    FROM Transactions t
    LEFT JOIN customers c ON c.Id_client = t.ID_client
    WHERE t.date_new >= '2015-06-01' AND t.date_new <= '2016-06-01'
),
g AS (   -- группа x квартал, группа x весь период, итоги
    SELECT age_group, age_ord, yq,
           SUM(Sum_payment) AS q_sum, COUNT(DISTINCT Id_check) AS q_ops, COUNT(DISTINCT ID_client) AS q_cl
    FROM tx GROUP BY age_group, age_ord, yq
    UNION ALL
    SELECT age_group, age_ord, 'ALL',
           SUM(Sum_payment), COUNT(DISTINCT Id_check), COUNT(DISTINCT ID_client)
    FROM tx GROUP BY age_group, age_ord
    UNION ALL
    SELECT 'Итого', 1000, yq,
           SUM(Sum_payment), COUNT(DISTINCT Id_check), COUNT(DISTINCT ID_client)
    FROM tx GROUP BY yq
    UNION ALL
    SELECT 'Итого', 1000, 'ALL',
           SUM(Sum_payment), COUNT(DISTINCT Id_check), COUNT(DISTINCT ID_client)
    FROM tx
),
tot AS (
    SELECT yq, q_sum AS t_sum, q_ops AS t_ops, q_cl AS t_cl FROM g WHERE age_group = 'Итого'
)
SELECT
    g.age_group AS `Возрастная группа`,
    ROUND(MAX(CASE WHEN g.yq = '2015-Q2' THEN g.q_sum * 100 / tot.t_sum END), 2) AS `% суммы 2015-Q2`,
    ROUND(MAX(CASE WHEN g.yq = '2015-Q3' THEN g.q_sum * 100 / tot.t_sum END), 2) AS `% суммы 2015-Q3`,
    ROUND(MAX(CASE WHEN g.yq = '2015-Q4' THEN g.q_sum * 100 / tot.t_sum END), 2) AS `% суммы 2015-Q4`,
    ROUND(MAX(CASE WHEN g.yq = '2016-Q1' THEN g.q_sum * 100 / tot.t_sum END), 2) AS `% суммы 2016-Q1`,
    ROUND(MAX(CASE WHEN g.yq = '2016-Q2' THEN g.q_sum * 100 / tot.t_sum END), 2) AS `% суммы 2016-Q2`,
    ROUND(MAX(CASE WHEN g.yq = 'ALL'     THEN g.q_sum * 100 / tot.t_sum END), 2) AS `% суммы весь период`,
    ROUND(MAX(CASE WHEN g.yq = '2015-Q2' THEN g.q_ops * 100 / tot.t_ops END), 2) AS `% операций 2015-Q2`,
    ROUND(MAX(CASE WHEN g.yq = '2015-Q3' THEN g.q_ops * 100 / tot.t_ops END), 2) AS `% операций 2015-Q3`,
    ROUND(MAX(CASE WHEN g.yq = '2015-Q4' THEN g.q_ops * 100 / tot.t_ops END), 2) AS `% операций 2015-Q4`,
    ROUND(MAX(CASE WHEN g.yq = '2016-Q1' THEN g.q_ops * 100 / tot.t_ops END), 2) AS `% операций 2016-Q1`,
    ROUND(MAX(CASE WHEN g.yq = '2016-Q2' THEN g.q_ops * 100 / tot.t_ops END), 2) AS `% операций 2016-Q2`,
    ROUND(MAX(CASE WHEN g.yq = 'ALL'     THEN g.q_ops * 100 / tot.t_ops END), 2) AS `% операций весь период`,
    ROUND(MAX(CASE WHEN g.yq = '2015-Q2' THEN g.q_cl * 100 / tot.t_cl END), 2) AS `% клиентов 2015-Q2`,
    ROUND(MAX(CASE WHEN g.yq = '2015-Q3' THEN g.q_cl * 100 / tot.t_cl END), 2) AS `% клиентов 2015-Q3`,
    ROUND(MAX(CASE WHEN g.yq = '2015-Q4' THEN g.q_cl * 100 / tot.t_cl END), 2) AS `% клиентов 2015-Q4`,
    ROUND(MAX(CASE WHEN g.yq = '2016-Q1' THEN g.q_cl * 100 / tot.t_cl END), 2) AS `% клиентов 2016-Q1`,
    ROUND(MAX(CASE WHEN g.yq = '2016-Q2' THEN g.q_cl * 100 / tot.t_cl END), 2) AS `% клиентов 2016-Q2`,
    ROUND(MAX(CASE WHEN g.yq = 'ALL'     THEN g.q_cl * 100 / tot.t_cl END), 2) AS `% клиентов весь период`
FROM g
JOIN tot ON tot.yq = g.yq
GROUP BY g.age_group, g.age_ord
ORDER BY g.age_ord;