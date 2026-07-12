WITH last_paid_click AS (
    SELECT
        visitor_id,
        visit_date,
        source AS utm_source,
        medium AS utm_medium,
        campaign AS utm_campaign,
        lead_id,
        amount,
        closing_reason,
        status_id
    FROM (
        SELECT
            s.visitor_id,
            s.visit_date,
            s.source,
            s.medium,
            s.campaign,
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
        WHERE s.medium IN (
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
    ) AS paid_sessions
    WHERE rn = 1
),

stats AS (
    SELECT
        visit_date::date AS visit_date,
        utm_source,
        utm_medium,
        utm_campaign,
        COUNT(visitor_id) AS visitors_count,
        COUNT(lead_id) AS leads_count,
        COUNT(*) FILTER (
            WHERE closing_reason = 'Успешно реализовано'
            OR status_id = 142
        ) AS purchases_count,
        SUM(amount) FILTER (
            WHERE closing_reason = 'Успешно реализовано'
            OR status_id = 142
        ) AS revenue
    FROM last_paid_click
    GROUP BY
        visit_date::date,
        utm_source,
        utm_medium,
        utm_campaign
),

ads_costs AS (
    SELECT
        campaign_date::date AS visit_date,
        utm_source,
        utm_medium,
        utm_campaign,
        daily_spent
    FROM vk_ads

    UNION ALL

    SELECT
        campaign_date::date AS visit_date,
        utm_source,
        utm_medium,
        utm_campaign,
        daily_spent
    FROM ya_ads
)

SELECT
    s.visit_date,
    s.visitors_count,
    s.utm_source,
    s.utm_medium,
    s.utm_campaign,
    s.leads_count,
    s.purchases_count,
    s.revenue,
    COALESCE(SUM(a.daily_spent), 0) AS total_cost
FROM stats AS s
LEFT JOIN ads_costs AS a
    ON
        s.visit_date = a.visit_date
        AND s.utm_source = a.utm_source
        AND s.utm_medium = a.utm_medium
        AND s.utm_campaign = a.utm_campaign
GROUP BY
    s.visit_date,
    s.visitors_count,
    s.utm_source,
    s.utm_medium,
    s.utm_campaign,
    s.leads_count,
    s.purchases_count,
    s.revenue
ORDER BY
    s.revenue DESC NULLS LAST,
    s.visit_date ASC,
    s.visitors_count DESC,
    s.utm_source ASC,
    s.utm_medium ASC,
    s.utm_campaign ASC;
