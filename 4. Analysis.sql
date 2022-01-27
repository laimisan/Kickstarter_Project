/* ANALYSIS

Skills used: Aggregate Functions, Views, Temp Tables, CTE's, Joins, Subqueries, Window Functions

I will start by answering the following general questions:
1. What are the top 5 categories that have the biggest number of succcessful projects in each country?
2. Is pledge length related to status (failed/successful)?
3. Is the goal size related to status (failed/successful)?

I then will proceed to extract data which will be used to create visualisations for deeper analysis.
 */

-- #1. What are the top 5 categories overall that have the most succcessful projects in each country?
SELECT
	a.country,
	a.main_category,
    a.no_of_projects,
    a.state_merged,
    a.row_no as top_no
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
		ROW_NUMBER() OVER (PARTITION BY country ORDER BY no_of_projects desc) as row_no
	FROM top_5_cte
	GROUP BY country, main_category
	ORDER BY country, no_of_projects desc) as a
WHERE a.row_no in (1,2,3,4,5)
ORDER BY country, top_no;

-- #2. Is the pledge length related to the state (failed/successful)?
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
-- the project length seems to be aproximately the same, which is not too surprising as Kickstarter does recommend to not exceed 30 days on average.

-- #3 What is the relationship between goal set, money received, and project status?
-- #3.1 In total
SELECT 
    state_merged,
    ROUND(AVG(usd_goal_real), 2) as avg_goal_usd,
    ROUND(AVG(usd_pledged_real) , 2) as avg_pledged_usd
FROM
    pledge
WHERE state_merged <> 'other'
GROUP BY state_merged;
-- on average, failed projects have a much larger goal

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

-- the pattern persists in all countries, failed projects tend to have higher goals.
/* For a deeper analysis I need to visualise the data. For this, I will store some of the
data in Views to be easilly accessed.*/

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

 /* Creating a 2nd table that will be stored as View for later visualisation. */
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

/* Alternative way - won't allow to create a View as is using temp tables for better readability
-- 1st Temp table - the previous query 
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
			CROSS JOIN (SELECT 'successful' as state union all select 'failed') s
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

-- Table 3 for visualisation. Comparing Goal Set (USD) vs Actually Pledged (USD), taking into account country, year, and main category. 

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