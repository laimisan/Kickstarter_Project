/* DATA EXPLORATION PART 2

Skills used: Aggregate Functions, Views, Temp Tables, CTE's, Joins, Subqueries, Window Functions, Stored Functions

I will start by answering a few general questions.
I will then proceed to extract data which will be used to create visualisations for deeper analysis.
 */

/* #1. What are the top 5 categories overall in each country with the highest number of successful projects?

This query has 3 layers: 
1. Innermost layer is a CTE which counts the number of projects per main category per country.
2. Middle layer queries the CTE and uses a window function to assign ranks to categories based
on a numebr of projects in it, partitioned by coutry. This allows us to know the top 5 (or more, in case
of identical numbers) most popular categories per country.
3. Outer layer filter the table and returns only top 5 categories per country. */

SELECT
    a.country,
    a.main_category,
    a.no_of_projects,
    a.state_merged,
    a.ranking as top_no
FROM
    (WITH top_5_cte AS (
    
        SELECT 
	    IFNULL(c.countryname, pr.country) AS country,
	    pr.main_category,
	    p.state_merged, 
	    COUNT(p.ID) as no_of_projects
	FROM project_info pr
	JOIN pledge p on p.ID = pr.ID
	LEFT JOIN country c on c.code = pr.country
	WHERE state_merged = 'successful'
	GROUP BY country, pr.main_category, p.state_merged
	ORDER BY country, p.state_merged, no_of_projects desc)
		
    SELECT
	country,
	main_category,
	no_of_projects,
	state_merged,
	DENSE_RANK() OVER (PARTITION BY country ORDER BY no_of_projects desc) as ranking
    FROM top_5_cte
    GROUP BY country, main_category
    ORDER BY country, no_of_projects desc) as a
WHERE ranking in (1,2,3,4,5)
ORDER BY country, top_no;

-- #2. Is the pledge length related to the project state (failed/successful)?

SELECT 
    IFNULL(c.countryname, pr.country) AS country,
    AVG(DATEDIFF(pr.deadline, pr.launched_date)) AS avg_project_length,
    p.state_merged
FROM
    project_info pr
        JOIN
    pledge p ON p.ID = pr.ID
        LEFT JOIN
    country c ON c.code = pr.country
WHERE
    YEAR(launched_date) <> '1970' AND state_merged <> 'other'
GROUP BY country, state_merged
HAVING state_merged <> 'other'
ORDER BY country, state_merged;

/* The project length seems to be aproximately the same, around a month, which is not too surprising,
as Kickstarter does recommend to not exceed 30 days on average. */

/* #3 What is the relationship between goal set, money received, and project status?
     #3.1 In total */

SELECT 
    state_merged,
    ROUND(AVG(usd_goal_real), 2) as avg_goal_usd,
    ROUND(AVG(usd_pledged_real) , 2) as avg_pledged_usd
FROM
    pledge
WHERE state_merged <> 'other'
GROUP BY state_merged;

/*  - On average, failed projects set a much larger goal but receive only a fraction of it
    - Successful projects set an averge goal under 10k, and receive double that amount */

-- #3.2 By country
SELECT 
    IFNULL(c.countryname, pr.country) AS country,
    p.state_merged,
    ROUND(AVG(p.usd_goal_real), 2) AS avg_goal_usd,
    ROUND(AVG(usd_pledged_real) , 2) as avg_pledged_usd
FROM
    pledge p
        JOIN
    project_info pr ON pr.ID = p.ID
        LEFT JOIN
    country c ON c.code = pr.country
GROUP BY pr.country , p.state_merged
HAVING state_merged <> 'other'
ORDER BY avg_goal_usd desc;

-- The pattern noted above seems to persist in all countries.

/* 4. A function that will take category name, start year and end year as parameters, and will return growth rate.

This function:
    1. Selects the total number of projects per main category (1st paramter) during the start year (2nd parameter)
    into a variable v_start_no,
    2. Selects the total number of projects per main category (1st parameter) during the end year (3rd parameter)
    into a variable v_end_no,
    3. Performs a simple calcutation with the two variables and returns growth rate (how many times the number of projects
    changed between the two years) */

DROP FUNCTION IF EXISTS growth_rate;
DELIMITER $$
CREATE FUNCTION growth_rate(p_category varchar(25), p_start_year integer, p_end_year integer) RETURNS DECIMAL(10,2)
DETERMINISTIC

BEGIN

DECLARE v_start_no integer;
DECLARE v_end_no integer;

SELECT
    no_of_projects
INTO
    v_start_no
FROM
    (SELECT
	YEAR(pr.launched_date) as year,
	pr.main_category,
	COUNT(*) as no_of_projects
    FROM
	project_info pr
    JOIN
	pledge p ON pr.ID = p.ID
    GROUP BY year, pr.main_category
    HAVING YEAR <> 1970
    ORDER BY year, pr.main_category) a
WHERE year = p_start_year AND main_category = p_category;

SELECT
    no_of_projects
INTO
    v_end_no
FROM
    (SELECT
	YEAR(pr.launched_date) as year,
	pr.main_category,
	COUNT(*) as no_of_projects
    FROM
	project_info pr
    JOIN
	pledge p ON pr.ID = p.ID
    GROUP BY year, pr.main_category
    HAVING YEAR <> 1970
    ORDER BY year, pr.main_category) a
WHERE year = p_end_year AND main_category = p_category;

RETURN (v_end_no - v_start_no) / v_start_no;
END$$

DELIMITER ;

SELECT growth_rate('Games', '2009', '2017');

/* Comparing all the categories, 'Games' has had the highest growth overall - 
it grew over 148 times by number of projects between 2009 and 2017.

Moving on, for a deeper analysis I need to visualise the data. For this, I will store some of it
 in Views to be easilly accessed.*/
 
/* This first View shows the percentage of successful projects per main category per country.

1. In the innermost layer we create a CTE showing how many failed and successful projects were in each country
by main category each year.
2. We then add another column using a window function which shows how many projects there were in each country
by main category each year disregarding its status (i.e. failed and successful added together).
3. We finally add another column showing what percentage of projects failed or were successful.
*/

CREATE VIEW v_success_rate AS
SELECT
    a.country,
    a.year,
    a.main_category,
    a.state_merged,
    a.no_of_projects,
    a.total_no,
    ROUND(((no_of_projects / total_no) *100), 2) as percentage
FROM
    (WITH prc_cte AS
	(SELECT
	    IFNULL(c.countryname, pr.country) AS country,
	    YEAR(pr.launched_date) as year,
	    pr.main_category,
	    p.state_merged,
	    COUNT(*) as no_of_projects
	FROM
	    project_info pr
		JOIN
	    pledge p ON pr.ID = p.ID
		LEFT JOIN
	    country c ON pr.country = c.code
	WHERE state_merged IN ('successful', 'failed')
	GROUP BY pr.country, year, pr.main_category, p.state_merged
	ORDER BY pr.country, year, pr.main_category, p.state_merged)

    SELECT
	country,
	year,
	main_category,
	state_merged,
	no_of_projects,
	SUM(no_of_projects) OVER (PARTITION BY country, year, main_category ORDER BY country, year, main_category) as total_no
    FROM prc_cte
    ORDER BY country, year, main_category, state_merged) a
    
ORDER BY country, year, main_category, state_merged;

/* The View created above has a problem which is not initially apparent - some project categories have either 100%
success, or failure. It means that a corresponding row with a 0% rate does not exist. This will make the future visualisation
difficult. I will solve this by adding another layer to the query.

1. As above, I create a table (alias 'part_1') that shows percentages of success and failure per category per country per year;
2. I then use a cross-join to create a table which has a row for both failed and successful projects, 
whether there were any or not (alias part_2)
3. Finally, I used a right join to join both tables, ensuring that each category has "failed" and "successful" rows,
and replacing Null values with 0 values. */

CREATE VIEW success_rate_full AS
SELECT
    part_2.country,
    part_2.year,
    part_2.main_category,
    part_2.state,
    IFNULL(part_1.total_no, 0) as total_no,
    IFNULL(part_1.percentage, 0) as percentage,
    part_1.year as test
FROM
    (SELECT
	a.country,
	a.year,
	a.main_category,
	a.state_merged,
	a.no_of_projects,
	a.total_no,
	ROUND(((no_of_projects / total_no) *100), 2) as percentage
    FROM
	(WITH prc_cte AS
	    (SELECT
	        IFNULL(c.countryname, pr.country) AS country,
	        YEAR(pr.launched_date) as year,
	        pr.main_category,
	        p.state_merged,
	        COUNT(*) as no_of_projects
	    FROM
	        project_info pr
		    JOIN
	        pledge p ON pr.ID = p.ID
		    LEFT JOIN
	        country c ON pr.country = c.code
	    WHERE state_merged IN ('successful', 'failed')
	    GROUP BY pr.country, year, pr.main_category, p.state_merged
	    ORDER BY pr.country, year, pr.main_category, p.state_merged)

	SELECT
			country,
			year,
			main_category,
			state_merged,
			no_of_projects,
			SUM(no_of_projects) OVER (PARTITION BY country, year, main_category ORDER BY country, year, main_category) as total_no
		FROM prc_cte
		ORDER BY country, year, main_category, state_merged) a
		
	ORDER BY country, year, main_category, state_merged) part_1
RIGHT JOIN 
    (SELECT
	IFNULL(c.countryname, pr.country) AS country,
	YEAR(pr.launched_date) as year,
	pr.main_category,
	s.state
    FROM
	project_info pr
	    JOIN
	pledge p ON pr.ID = p.ID
	    LEFT JOIN
	country c ON pr.country = c.code
	    CROSS JOIN (SELECT 'successful' as state union all select 'failed') s
    WHERE state_merged <> 'other'
    GROUP BY country, year, main_category, state
    ORDER BY country, year, main_category, state) part_2 ON part_1.country = part_2.country AND part_1.year = part_2.year AND part_1.main_category = part_2.main_category AND part_1.state_merged = part_2.state;


/* An alternative way using temp tables, which might have a better readability. Could be used if we don't need to store
the result as a View. 

-- 1st Temp table - as in the previous query 
DROP TABLE IF EXISTS success_rate;
CREATE TEMPORARY TABLE success_rate
SELECT
    a.country,
    a.year,
    a.main_category,
    a.state_merged,
    a.no_of_projects,
    a.total_no,
    ROUND(((no_of_projects / total_no) *100), 2) as percentage
FROM
    (WITH prc_cte AS
        (SELECT
	    IFNULL(c.countryname, pr.country) AS country,
	    YEAR(pr.launched_date) as year,
	    pr.main_category,
	    p.state_merged,
	    COUNT(*) as no_of_projects
	FROM
	    project_info pr
	        JOIN
	    pledge p ON pr.ID = p.ID
	        LEFT JOIN
	    country c ON pr.country = c.code
	WHERE state_merged IN ('successful', 'failed')
	GROUP BY pr.country, year, pr.main_category, p.state_merged
	ORDER BY pr.country, year, pr.main_category, p.state_merged)

	SELECT
	    country,
	    year,
	    main_category,
	    state_merged,
	    no_of_projects,
	    SUM(no_of_projects) OVER (PARTITION BY country, year, main_category ORDER BY country, year, main_category) as total_no
	FROM prc_cte
	ORDER BY country, year, main_category, state_merged) a
    
ORDER BY country, year, main_category, state_merged;
 
-- 2nd temp table - making sure that all countries, years, and categories have a 'failed' and 'successful' categories
DROP TABLE IF EXISTS state_cross_join;    
CREATE TEMPORARY TABLE state_cross_join
    SELECT
	IFNULL(c.countryname, pr.country) AS country,
	YEAR(pr.launched_date) as year,
	pr.main_category,
	s.state
    FROM
	project_info pr
	    JOIN
	pledge p ON pr.ID = p.ID
	    LEFT JOIN
	country c ON pr.country = c.code
	    CROSS JOIN 
		(SELECT 'successful' as state union all select 'failed') s
    WHERE state_merged <> 'other'
    GROUP BY country, year, main_category, state
    ORDER BY country, year, main_category, state;
 
 -- Joining the two tables as creating a View
 CREATE VIEW success_rate_full AS
 SELECT
	scj.country,
    scj.year,
    scj.main_category,
    scj.state,
    IFNULL(sr.total_no, 0) as total_no,
    IFNULL(sr.percentage, 0) as percentage,
    sr.year as test -- this column helps me quickly locate rows that had null values and check if they have been transformed as intedned
FROM
    state_cross_join scj
LEFT JOIN 
    success_rate sr ON sr.country = scj.country AND sr.year = scj.year AND sr.main_category = scj.main_category AND sr.state_merged = scj.state
ORDER BY country, year, main_category, state; */

/* Table 3 for visualisation. Comparing Goal Set (USD) vs Actually Pledged (USD), taking into account country,
year, and main category. */

CREATE VIEW goal_vs_pledge AS
SELECT
    pr.ID,
    IFNULL(c.countryname, pr.country) AS country,
    pr.main_category,
    p.state_merged,
    pr.launched_date,
    p.usd_goal_real,
    p.usd_pledged_real
FROM
    project_info pr
JOIN
    pledge p ON pr.ID = p.ID
LEFT JOIN
    country c ON pr.country = c.code
WHERE state_merged <> 'other'
ORDER BY country, main_category, state_merged, launched_date;

/* Querying one of the views regarding success rates:
   average success rate overall */
   
SELECT 
    AVG(percentage) as avg_success_rate
FROM
    success_rate_full
WHERE state = 'successful';

-- Average success rathe is 29%.

-- Which categories have the highest percentage of success overall / per country / per year?

SELECT 
    main_category,
    state_merged,
    AVG(cast(percentage as float)) as avg_success_rate,
    SUM(cast(total_no as float)) as project_count
FROM
    v_success_rate
WHERE
    state_merged = 'successful'
    AND year <> 1970
    AND year <> 2018
    -- AND country = 'United Kingdom'
    -- AND year = '2017'
GROUP BY main_category
ORDER BY avg_success_rate DESC;

/* - Technology has the lowest success rate
   - Dance has the highest
   - Categories with biggest success rates tend to be the less popular ones (by number of total projects) - theater, comics, and dace
   - ...while most popolar groups (film, publishing,  games, technology) have lower success rates (18%-27%).
   - Music seems to be in-between - one of the most populars, and above-average success rate (35%). */
   
/* I will continue the project by exporting the data to Tableu and bulding interactive visualisation dashboard.

NOTE: Due to some of these queries being rather large and complicated, if the only reason for creating them
was to have a data extract to import into Tableu, I would instead resort to a simpler query and
create calculated fields in Tableu instead of window functions in SQL. */
