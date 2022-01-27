/* CLEANING

Skills Used: String Manipulation, Conditionals (IFNULL, CASE WHEN), Joins, Aggregate Functions

*/ 
-- 1. Adding a separate column with just the launch year, as I will not be looking at months and days.

alter table project_info
add column launched_date date;

update project_info
set launched_date = YEAR(launched);

/* 2. During the scraping process some country info was corrupted. I will populate missing data
as much as I can from currency */

-- First, settin corrupted data into Null which will allow me to use IFNULL later
UPDATE project_info 
SET 
    country = NULL
WHERE
    country = '"N';

-- Checking the query before updating the table
SELECT 
    pr.country,
    p.currency,
    IFNULL(pr.country, SUBSTRING(p.currency, 1, 2)) country_new
FROM
    pledge p
        JOIN
    project_info pr ON pr.ID = p.ID
WHERE
    pr.country IS NULL;

/* Updating the table. Some countries with corrupted values were using Euros, which makes it impossible to
know the coubtry for certain. I will leave it as 'Unknown' */

UPDATE project_info pr
        JOIN
    pledge p ON pr.ID = p.ID 
SET 
    pr.country = CASE
        WHEN p.currency <> 'EUR' THEN IFNULL(pr.country, SUBSTRING(p.currency, 1, 2))
        ELSE 'Unknown'
    END
WHERE
    pr.country IS NULL;

SELECT 
    country, 
    currency,
    COUNT(*) as project_count
FROM
    project_info pr
        JOIN
    pledge p ON pr.ID = p.ID
GROUP BY country, currency;

-- Looks good. There are 186 projects from unknown country in Europe.

-- 3. Now, I will merge "failed", "cancelled", and "suspended" categories into one "failed" and "live" plus "undefined" into "other".

alter table pledge
add column state_merged varchar(50);

update pledge
SET state_merged =
	CASE
		WHEN state IN ('failed', 'canceled', 'suspended') THEN 'failed'
        WHEN state IN ('undefined', 'live') THEN 'other'
        ELSE state
	END;