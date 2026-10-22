-- Дата і країна
WITH session_data AS (
  SELECT
    account_session.account_id,
    session.date,
    session_params.country
  FROM `data-analytics-mate.DA.account_session` account_session
  JOIN `data-analytics-mate.DA.session` session
    ON account_session.ga_session_id = session.ga_session_id
  JOIN `data-analytics-mate.DA.session_params` session_params
    ON account_session.ga_session_id = session_params.ga_session_id
  JOIN `data-analytics-mate.DA.account` account
    ON account_session.account_id = account.id
),

-- Метрики по акаунтах
account_metrics AS (
  SELECT
    DATE(session_data.date) AS date,
    session_data.country,
    account.send_interval,
    account.is_verified,
    account.is_unsubscribed,
    COUNT(DISTINCT account.id) AS account_cnt,
    0 AS sent_msg,
    0 AS open_msg,
    0 AS visit_msg
  FROM `data-analytics-mate.DA.account` account
  JOIN session_data
    ON account.id = session_data.account_id
  GROUP BY
    DATE(session_data.date),
    session_data.country,
    account.send_interval,
    account.is_verified,
    account.is_unsubscribed
),

-- Метрики по емейлах
email_metrics AS (
  SELECT
    date_add(session_data.date, INTERVAL sent_date DAY) AS date,
    session_data.country,
    account.send_interval,
    account.is_verified,
    account.is_unsubscribed,
    0 AS account_cnt,
    COUNT(DISTINCT email_sent.id_message) AS sent_msg,
    COUNT(DISTINCT email_open.id_message) AS open_msg,
    COUNT(DISTINCT email_visit.id_message) AS visit_msg
  FROM `data-analytics-mate.DA.email_sent` email_sent
  LEFT JOIN `data-analytics-mate.DA.email_open` email_open
    ON email_sent.id_message = email_open.id_message
  LEFT JOIN `data-analytics-mate.DA.email_visit` email_visit
    ON email_sent.id_message = email_visit.id_message
  JOIN `data-analytics-mate.DA.account` account
    ON email_sent.id_account = account.id
  JOIN session_data
    ON account.id = session_data.account_id
  GROUP BY
    date_add(session_data.date, INTERVAL sent_date DAY),
    session_data.country,
    account.send_interval,
    account.is_verified,
    account.is_unsubscribed
),

combined AS (
  SELECT * FROM account_metrics
  UNION ALL
  SELECT * FROM email_metrics
),

-- Агрегація по розрізах
aggregated AS (
  SELECT
    date,
    country,
    send_interval,
    is_verified,
    is_unsubscribed,
    SUM(account_cnt) AS account_cnt,
    SUM(sent_msg) AS sent_msg,
    SUM(open_msg) AS open_msg,
    SUM(visit_msg) AS visit_msg
  FROM combined
  GROUP BY
    date,
    country,
    send_interval,
    is_verified,
    is_unsubscribed
),

-- Тотали по країнах
country_totals AS (
  SELECT
    *,
    SUM(account_cnt) OVER (PARTITION BY country) AS total_country_account_cnt,
    SUM(sent_msg) OVER (PARTITION BY country) AS total_country_sent_cnt
  FROM aggregated
),

-- Ранги
ranked AS (
  SELECT
    *,
    DENSE_RANK() OVER (ORDER BY total_country_account_cnt DESC) AS rank_total_country_account_cnt,
    DENSE_RANK() OVER (ORDER BY total_country_sent_cnt DESC) AS rank_total_country_sent_cnt
  FROM country_totals
)

-- Фінал
SELECT
  date,
  country,
  send_interval,
  is_verified,
  is_unsubscribed,
  account_cnt,
  sent_msg,
  open_msg,
  visit_msg,
  total_country_account_cnt,
  total_country_sent_cnt,
  rank_total_country_account_cnt,
  rank_total_country_sent_cnt
FROM ranked
WHERE rank_total_country_account_cnt <= 10
   OR rank_total_country_sent_cnt <= 10
ORDER BY country, date;
