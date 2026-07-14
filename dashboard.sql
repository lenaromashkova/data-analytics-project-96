-- 1. Сколько пользователей заходят на сайт?

SELECT COUNT(DISTINCT visitor_id) AS visitors_count
FROM sessions;


-- 1.1. Количество пользователей по дням

SELECT
    visit_date::date AS visit_date,
    COUNT(DISTINCT visitor_id) AS visitors_count
FROM sessions
GROUP BY visit_date::date
ORDER BY visit_date;


-- 2. Какие каналы приводят пользователей на сайт?

SELECT
    LOWER(TRIM(source)) AS utm_source,
    COUNT(DISTINCT visitor_id) AS visitors_count
FROM sessions
GROUP BY LOWER(TRIM(source))
ORDER BY
    visitors_count DESC,
    utm_source ASC;


-- 3. Трафик по каналам по дням

SELECT
    visit_date::date AS visit_date,
    LOWER(TRIM(source)) AS utm_source,
    COUNT(DISTINCT visitor_id) AS visitors_count
FROM sessions
GROUP BY
    visit_date::date,
    LOWER(TRIM(source))
ORDER BY
    visit_date ASC,
    visitors_count DESC;


-- 4. Трафик по каналам по неделям

SELECT
    DATE_TRUNC('week', visit_date)::date AS week_start,
    LOWER(TRIM(source)) AS utm_source,
    COUNT(DISTINCT visitor_id) AS visitors_count
FROM sessions
GROUP BY
    DATE_TRUNC('week', visit_date)::date,
    LOWER(TRIM(source))
ORDER BY
    week_start ASC,
    visitors_count DESC;


-- 5. Трафик по каналам по месяцам

SELECT
    DATE_TRUNC('month', visit_date)::date AS month_start,
    LOWER(TRIM(source)) AS utm_source,
    COUNT(DISTINCT visitor_id) AS visitors_count
FROM sessions
GROUP BY
    DATE_TRUNC('month', visit_date)::date,
    LOWER(TRIM(source))
ORDER BY
    month_start,
    visitors_count DESC;


-- 6. Сколько лидов приходит?

SELECT
    COUNT(DISTINCT lead_id) AS leads_count
FROM leads;


-- 7. Количество лидов по дням

SELECT
    created_at::date AS lead_date,
    COUNT(DISTINCT lead_id) AS leads_count
FROM leads
GROUP BY created_at::date
ORDER BY lead_date;


-- 8. Какая конверсия из клика в лид?
-- Какая конверсия из лида в оплату?

WITH visitors AS (
    SELECT COUNT(DISTINCT visitor_id) AS visitors_count
    FROM sessions
),

leads_data AS (
    SELECT COUNT(DISTINCT visitor_id) AS leads_count
    FROM leads
),

purchases AS (
    SELECT COUNT(DISTINCT visitor_id) AS purchases_count
    FROM leads
    WHERE
        status_id = 142
        OR closing_reason = 'Успешно реализовано'
)

SELECT
    v.visitors_count,
    l.leads_count,
    p.purchases_count,
    ROUND(
        l.leads_count::numeric
        / NULLIF(v.visitors_count, 0) * 100,
        2
    ) AS click_to_lead_conversion_pct,
    ROUND(
        p.purchases_count::numeric
        / NULLIF(l.leads_count, 0) * 100,
        2
    ) AS lead_to_purchase_conversion_pct
FROM visitors AS v
CROSS JOIN leads_data AS l
CROSS JOIN purchases AS p;


-- 9. Воронка для Preset

SELECT
    'Посетители сайта' AS stage,
    COUNT(DISTINCT visitor_id) AS users_count
FROM sessions

UNION ALL

SELECT
    'Оставили заявку' AS stage,
    COUNT(DISTINCT visitor_id) AS users_count
FROM leads

UNION ALL

SELECT
    'Совершили покупку' AS stage,
    COUNT(DISTINCT visitor_id) AS users_count
FROM leads
WHERE
    status_id = 142
    OR closing_reason = 'Успешно реализовано'

ORDER BY users_count DESC;


-- 10. Расходы по рекламным каналам в динамике

WITH ads AS (
    SELECT
        campaign_date::date AS spend_date,
        LOWER(TRIM(utm_source)) AS utm_source,
        daily_spent
    FROM vk_ads

    UNION ALL

    SELECT
        campaign_date::date AS spend_date,
        LOWER(TRIM(utm_source)) AS utm_source,
        daily_spent
    FROM ya_ads
)

SELECT
    spend_date,
    utm_source,
    SUM(daily_spent) AS total_cost
FROM ads
GROUP BY
    spend_date,
    utm_source
ORDER BY
    spend_date,
    total_cost DESC;


-- 11. Расчёт метрик по utm_source

WITH paid_sessions AS (
    SELECT
        s.visitor_id,
        s.visit_date,
        LOWER(TRIM(s.source)) AS utm_source,
        l.lead_id,
        l.amount,
        l.closing_reason,
        l.status_id,
        ROW_NUMBER() OVER (
            PARTITION BY s.visitor_id
            ORDER BY s.visit_date DESC
        ) AS rn
    FROM sessions AS s
    LEFT JOIN leads AS l
        ON s.visitor_id = l.visitor_id
    WHERE
        s.medium IN (
            'cpc',
            'cpm',
            'cpa',
            'youtube',
            'cpp',
            'tg',
            'social'
        )
        AND (
            l.lead_id IS NULL
            OR s.visit_date <= l.created_at
        )
),

traffic AS (
    SELECT
        visit_date::date AS visit_date,
        utm_source,
        COUNT(visitor_id) AS visitors_count,
        COUNT(lead_id) AS leads_count,
        COUNT(*) FILTER (
            WHERE
                status_id = 142
                OR closing_reason = 'Успешно реализовано'
        ) AS purchases_count,
        COALESCE(
            SUM(amount) FILTER (
                WHERE
                    status_id = 142
                    OR closing_reason = 'Успешно реализовано'
            ),
            0
        ) AS revenue
    FROM paid_sessions
    WHERE rn = 1
    GROUP BY
        visit_date::date,
        utm_source
),

ads AS (
    SELECT
        campaign_date::date AS visit_date,
        LOWER(TRIM(utm_source)) AS utm_source,
        SUM(daily_spent) AS total_cost
    FROM (
        SELECT
            campaign_date,
            utm_source,
            daily_spent
        FROM vk_ads

        UNION ALL

        SELECT
            campaign_date,
            utm_source,
            daily_spent
        FROM ya_ads
    ) AS ads_data
    GROUP BY
        campaign_date::date,
        LOWER(TRIM(utm_source))
)

SELECT
    a.utm_source,
    COALESCE(SUM(t.visitors_count), 0) AS visitors_count,
    SUM(a.total_cost) AS total_cost,
    COALESCE(SUM(t.leads_count), 0) AS leads_count,
    COALESCE(SUM(t.purchases_count), 0) AS purchases_count,
    COALESCE(SUM(t.revenue), 0) AS revenue,
    ROUND(
        SUM(a.total_cost)::numeric
        / NULLIF(SUM(t.visitors_count), 0),
        2
    ) AS cpu,
    ROUND(
        SUM(a.total_cost)::numeric
        / NULLIF(SUM(t.leads_count), 0),
        2
    ) AS cpl,
    ROUND(
        SUM(a.total_cost)::numeric
        / NULLIF(SUM(t.purchases_count), 0),
        2
    ) AS cppu,
    ROUND(
        (
            COALESCE(SUM(t.revenue), 0) - SUM(a.total_cost)
        )::numeric
        / NULLIF(SUM(a.total_cost), 0) * 100,
        2
    ) AS roi
FROM ads AS a
LEFT JOIN traffic AS t
    ON a.visit_date = t.visit_date
    AND a.utm_source = t.utm_source
GROUP BY a.utm_source
ORDER BY
    roi DESC NULLS LAST,
    a.utm_source;


-- 12. Данные для итоговой таблицы дашборда
-- по utm_source, utm_medium и utm_campaign

WITH paid_sessions AS (
    SELECT
        s.visitor_id,
        s.visit_date,
        LOWER(TRIM(s.source)) AS utm_source,
        LOWER(TRIM(s.medium)) AS utm_medium,
        LOWER(TRIM(s.campaign)) AS utm_campaign,
        l.lead_id,
        l.amount,
        l.closing_reason,
        l.status_id,
        ROW_NUMBER() OVER (
            PARTITION BY s.visitor_id
            ORDER BY s.visit_date DESC
        ) AS rn
    FROM sessions AS s
    LEFT JOIN leads AS l
        ON s.visitor_id = l.visitor_id
    WHERE
        s.medium IN (
            'cpc',
            'cpm',
            'cpa',
            'youtube',
            'cpp',
            'tg',
            'social'
        )
        AND (
            l.lead_id IS NULL
            OR s.visit_date <= l.created_at
        )
),

traffic AS (
    SELECT
        visit_date::date AS visit_date,
        utm_source,
        utm_medium,
        utm_campaign,
        COUNT(visitor_id) AS visitors_count,
        COUNT(lead_id) AS leads_count,
        COUNT(*) FILTER (
            WHERE
                status_id = 142
                OR closing_reason = 'Успешно реализовано'
        ) AS purchases_count,
        COALESCE(
            SUM(amount) FILTER (
                WHERE
                    status_id = 142
                    OR closing_reason = 'Успешно реализовано'
            ),
            0
        ) AS revenue
    FROM paid_sessions
    WHERE rn = 1
    GROUP BY
        visit_date::date,
        utm_source,
        utm_medium,
        utm_campaign
),

ads AS (
    SELECT
        campaign_date::date AS visit_date,
        LOWER(TRIM(utm_source)) AS utm_source,
        LOWER(TRIM(utm_medium)) AS utm_medium,
        LOWER(TRIM(utm_campaign)) AS utm_campaign,
        SUM(daily_spent) AS total_cost
    FROM (
        SELECT
            campaign_date,
            utm_source,
            utm_medium,
            utm_campaign,
            daily_spent
        FROM vk_ads

        UNION ALL

        SELECT
            campaign_date,
            utm_source,
            utm_medium,
            utm_campaign,
            daily_spent
        FROM ya_ads
    ) AS ads_data
    GROUP BY
        campaign_date::date,
        LOWER(TRIM(utm_source)),
        LOWER(TRIM(utm_medium)),
        LOWER(TRIM(utm_campaign))
)

SELECT
    COALESCE(t.visit_date, a.visit_date) AS visit_date,
    COALESCE(t.utm_source, a.utm_source) AS utm_source,
    COALESCE(t.utm_medium, a.utm_medium) AS utm_medium,
    COALESCE(t.utm_campaign, a.utm_campaign) AS utm_campaign,
    COALESCE(t.visitors_count, 0) AS visitors_count,
    COALESCE(a.total_cost, 0) AS total_cost,
    COALESCE(t.leads_count, 0) AS leads_count,
    COALESCE(t.purchases_count, 0) AS purchases_count,
    COALESCE(t.revenue, 0) AS revenue
FROM traffic AS t
FULL JOIN ads AS a
    ON t.visit_date = a.visit_date
    AND t.utm_source = a.utm_source
    AND t.utm_medium = a.utm_medium
    AND t.utm_campaign = a.utm_campaign
ORDER BY
    visit_date,
    utm_source,
    utm_medium,
    utm_campaign;


-- Есть ли заметная корреляция между запуском
-- рекламной компании и ростом органики?
WITH ads AS (
    SELECT
        campaign_date::date AS visit_date,
        SUM(daily_spent) AS total_cost
    FROM (
        SELECT
            campaign_date,
            daily_spent
        FROM vk_ads

        UNION ALL

        SELECT
            campaign_date,
            daily_spent
        FROM ya_ads
    ) AS ad_data
    GROUP BY campaign_date::date
),

organic AS (
    SELECT
        visit_date::date AS visit_date,
        COUNT(DISTINCT visitor_id) AS organic_visitors
    FROM sessions
    WHERE LOWER(TRIM(medium)) = 'organic'
    GROUP BY visit_date::date
)

SELECT
    COALESCE(a.visit_date, o.visit_date) AS visit_date,
    COALESCE(total_cost, 0) AS total_cost,
    COALESCE(organic_visitors, 0) AS organic_visitors
FROM ads AS a
FULL JOIN organic AS o
    ON a.visit_date = o.visit_date
ORDER BY visit_date;


-- За сколько дней после первого рекламного визита
-- формируется 90% успешных продаж

WITH sales AS (
    SELECT
        l.lead_id,
        l.created_at::date - MIN(s.visit_date::date) AS days_to_sale
    FROM leads AS l
    JOIN sessions AS s
        ON l.visitor_id = s.visitor_id
        AND s.visit_date <= l.created_at
    WHERE
        l.status_id = 142
        AND s.medium IN (
            'cpc',
            'cpm',
            'cpa',
            'youtube',
            'cpp',
            'tg',
            'social'
        )
    GROUP BY
        l.lead_id,
        l.created_at::date
),

distribution AS (
    SELECT
        days_to_sale,
        COUNT(*) AS sales_count
    FROM sales
    GROUP BY days_to_sale
)

SELECT
    days_to_sale,
    sales_count,
    SUM(sales_count) OVER (
        ORDER BY days_to_sale
    ) AS cumulative_sales,
    ROUND(
        100.0 * SUM(sales_count) OVER (
            ORDER BY days_to_sale
        ) / SUM(sales_count) OVER (),
        2
    ) AS cumulative_percent
FROM distribution
ORDER BY days_to_sale;
