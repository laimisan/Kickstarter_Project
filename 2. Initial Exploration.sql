-- DATA EXPLORATION Part 1

-- What state can a project be in?
SELECT 
    state,
    COUNT(state) as project_count
FROM
    pledge
GROUP BY state
ORDER BY project_count;

/* My analysis will concern failed and successful projects. I will merge:
 1. 'failed', 'cancelled', and ' suspended' into one 'failed' category,
 2. 'live', 'undefined' into 'other' which will be excluded from analysis
 3. 'successful' will be left as it is */

-- finding a total number of projects per country
SELECT 
    country,
    COUNT(country) AS country_count
FROM
    project_info
GROUP BY country
ORDER BY country_count;

/* I can see from this that some data regarding countries was lost when data was scrapd.
I will later use currency to populate missing data as much as possible */

-- finding a number of distinct countries in the dataset

SELECT
	count(distinct country)
FROM project_info;

-- finding how many projects there are per main category

SELECT 
    main_category,
    COUNT(main_category) AS project_count
FROM
    project_info
GROUP BY main_category
ORDER BY project_count DESC;

-- finding the number of main categories
SELECT 
    COUNT(DISTINCT main_category) as main_category_count
FROM
    project_info;
    
-- finding the number of projects per sub-category

SELECT 
    category,
    COUNT(category) AS project_count
FROM
    project_info
GROUP BY category
ORDER BY project_count DESC;

-- finding how many sub-categories there are

SELECT 
    COUNT(DISTINCT category) as subcategory_count
FROM
    project_info;

/* clearly there are too many sub-categories for general overview. I will continue using main categories for now. */

-- checking the time period of the data
SELECT 
    MIN(launched) as start_date,
    MAX(launched) as end_date
FROM
    project_info;
 
 -- 1970 looks suspicious. Let's see the distinct years we have data for.
 
SELECT DISTINCT
    (YEAR(cast(launched as date))) AS year
FROM
    project_info
ORDER BY year;

/* In general, data runs from 2009 until beginning of 2018.
'1970' seems to be an error again */

SELECT 
    *
FROM
    project_info
WHERE
    (YEAR(launched_date)) = '1970';
    
/* Most of the data seems intact, but year is definitely wrong. I will keep the records,
but will exclude the '1970' data when analysis is date-sensitive */

SELECT 
    YEAR(pr.launched_date) as year_launched,
    YEAR(pr.deadline) as year_deadline,
    COUNT(*) as project_count
FROM
    project_info pr
JOIN pledge p on p.Id = pr.ID
WHERE
    state = 'live'
GROUP BY year_launched, year_deadline;

/* As expected, there is a significant number of projects still live
at the end of 2017 - beginning of 2018.*/

-- checking the types of currency used

SELECT 
    currency,
    ROW_NUMBER() OVER (ORDER BY currency) as currency_count
FROM
    pledge
GROUP BY currency;

/* 14 types of currency for 23 countries. Since I want to populate missing country data from
the currency, I will check which currency is used in more than one country */

SELECT
	currency,
    count(distinct(country)) as countries_per_currency
FROM
	pledge p
JOIN project_info pr on p.ID = pr.ID
GROUP BY currency
ORDER BY currency;

-- seems like all currencies except for Euros are safe to use to populate missing country data.
-- goal range in USD

SELECT
    MIN(usd_goal_real) as min_goal_usd,
    AVG(usd_goal_real) as avg_goal_usd,
    MAX(usd_goal_real) as max_goal_usd
FROM
	pledge;