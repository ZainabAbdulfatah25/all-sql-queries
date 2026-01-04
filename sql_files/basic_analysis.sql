-- 1. Total Sales by Business Unit and Scenario
SELECT [Business Unit], Scenario, SUM(Sales) AS total_sales
FROM financial_data
GROUP BY [Business Unit], Scenario
ORDER BY total_sales DESC;

-- 2. Total Expenses by Account and Business Unit
SELECT [Business Unit], Account,
       SUM([Cost of Goods Sold] + [Commissions Expense] + [Payroll Expense] +
           [Travel & Entertainment Expense] + [R&D Expense] + [Consulting Expense] +
           [Software/Hardware Expense] + [Marketing Expense]) AS total_expenses
FROM financial_data
GROUP BY [Business Unit], Account
ORDER BY total_expenses DESC;

-- 3. Monthly Sales Trend for Actuals
SELECT Month, SUM(Sales) AS total_sales
FROM financial_data
WHERE Scenario = 'Actuals'
GROUP BY Month
ORDER BY Month;

-- 4. Net Profit by Business Unit for Actuals
SELECT [Business Unit],
       SUM(Sales) - SUM([Cost of Goods Sold] + [Commissions Expense] + [Payroll Expense] +
                         [Travel & Entertainment Expense] + [R&D Expense] + [Consulting Expense] +
                         [Software/Hardware Expense] + [Marketing Expense]) AS net_profit
FROM financial_data
WHERE Scenario = 'Actuals'
GROUP BY [Business Unit]
ORDER BY net_profit DESC;

