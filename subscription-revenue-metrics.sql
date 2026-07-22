WITH payments_deduplicated AS (
    SELECT DISTINCT
        user_id,
        game_name,
        payment_date::date AS payment_date,
        DATE_TRUNC('month', payment_date::date)::date AS payment_month,
        CAST(revenue_amount_usd AS numeric(18,4)) AS revenue_amount_usd
    FROM project.games_payments
),

user_month_revenue AS (
    SELECT
        user_id,
        payment_month,
        SUM(revenue_amount_usd) AS mrr
    FROM payments_deduplicated
    GROUP BY
        user_id,
        payment_month
),

revenue_metrics AS (
    SELECT
        umr.user_id,
        umr.payment_month,
        umr.mrr,

        LAG(umr.payment_month) OVER (
            PARTITION BY umr.user_id
            ORDER BY umr.payment_month
        ) AS prev_payment_month,

        LEAD(umr.payment_month) OVER (
            PARTITION BY umr.user_id
            ORDER BY umr.payment_month
        ) AS next_payment_month,

        LAG(umr.mrr) OVER (
            PARTITION BY umr.user_id
            ORDER BY umr.payment_month
        ) AS prev_mrr
    FROM user_month_revenue umr
),

gpu_user_attrs AS (
    SELECT
        user_id,
        MAX(language) AS language,
        BOOL_OR(has_older_device_model) AS has_older_device_model,
        MAX(age) AS age
    FROM (
        SELECT DISTINCT
            user_id,
            language,
            has_older_device_model,
            age
        FROM project.games_paid_users
    ) gpu
    GROUP BY user_id
)

SELECT
    rm.user_id,
    rm.payment_month,
    gpu.language,
    gpu.has_older_device_model,
    gpu.age,

    ROUND(rm.mrr, 2) AS total_revenue,
    ROUND(rm.mrr, 2) AS mrr,

    1 AS paid_user,

    CASE
        WHEN rm.prev_payment_month IS NULL THEN 1
        ELSE 0
    END AS new_paid_user,

    CASE
        WHEN rm.prev_payment_month IS NULL THEN ROUND(rm.mrr, 2)
        ELSE 0
    END AS new_mrr,

    CASE
        WHEN rm.prev_payment_month IS NOT NULL
         AND rm.prev_payment_month <> (rm.payment_month - INTERVAL '1 month')::date
        THEN 1
        ELSE 0
    END AS returned_user,

    CASE
        WHEN rm.prev_payment_month IS NOT NULL
         AND rm.prev_payment_month <> (rm.payment_month - INTERVAL '1 month')::date
        THEN ROUND(rm.mrr, 2)
        ELSE 0
    END AS returned_mrr,

    CASE
        WHEN rm.next_payment_month IS NULL
          OR rm.next_payment_month <> (rm.payment_month + INTERVAL '1 month')::date
        THEN 1
        ELSE 0
    END AS churned_user,

    CASE
        WHEN rm.next_payment_month IS NULL
          OR rm.next_payment_month <> (rm.payment_month + INTERVAL '1 month')::date
        THEN (rm.payment_month + INTERVAL '1 month')::date
        ELSE NULL
    END AS churn_month,

    CASE
        WHEN rm.next_payment_month IS NULL
          OR rm.next_payment_month <> (rm.payment_month + INTERVAL '1 month')::date
        THEN ROUND(rm.mrr, 2)
        ELSE 0
    END AS churned_revenue,

    CASE
        WHEN rm.prev_payment_month = (rm.payment_month - INTERVAL '1 month')::date
         AND rm.mrr > COALESCE(rm.prev_mrr, 0)
        THEN ROUND(rm.mrr - COALESCE(rm.prev_mrr, 0), 2)
        ELSE 0
    END AS expansion_mrr,

    CASE
        WHEN rm.prev_payment_month = (rm.payment_month - INTERVAL '1 month')::date
         AND rm.mrr < COALESCE(rm.prev_mrr, 0)
        THEN ROUND(rm.mrr - COALESCE(rm.prev_mrr, 0), 2)
        ELSE 0
    END AS contraction_mrr

FROM revenue_metrics rm
LEFT JOIN gpu_user_attrs gpu
    USING (user_id)
ORDER BY
    rm.payment_month,
    rm.user_id;