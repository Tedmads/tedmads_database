-- =====================================================
-- Лабораторная работа 8: SQL Indexes (PostgreSQL)
-- =====================================================

-- ===== PART 1: Настройка БД =====
CREATE TABLE departments (
    dept_id   INT PRIMARY KEY,
    dept_name VARCHAR(50),
    location  VARCHAR(50)
);

CREATE TABLE employees (
    emp_id   INT PRIMARY KEY,
    emp_name VARCHAR(100),
    dept_id  INT,
    salary   DECIMAL(10,2),
    FOREIGN KEY (dept_id) REFERENCES departments(dept_id)
);

CREATE TABLE projects (
    proj_id   INT PRIMARY KEY,
    proj_name VARCHAR(100),
    budget    DECIMAL(12,2),
    dept_id   INT,
    FOREIGN KEY (dept_id) REFERENCES departments(dept_id)
);

INSERT INTO departments VALUES
(101, 'IT', 'Building A'),
(102, 'HR', 'Building B'),
(103, 'Operations', 'Building C');

INSERT INTO employees VALUES
(1, 'John Smith', 101, 50000),
(2, 'Jane Doe', 101, 55000),
(3, 'Mike Johnson', 102, 48000),
(4, 'Sarah Williams', 102, 52000),
(5, 'Tom Brown', 103, 60000);

INSERT INTO projects VALUES
(201, 'Website Redesign', 75000, 101),
(202, 'Database Migration', 120000, 101),
(203, 'HR System Upgrade', 50000, 102);

-- ===== PART 2: Базовые индексы =====

-- 2.1
CREATE INDEX emp_salary_idx ON employees(salary);

SELECT indexname, indexdef
FROM pg_indexes
WHERE tablename = 'employees';

-- ОТВЕТ 2.1: 2 индекса: employees_pkey (создан автоматически для PRIMARY KEY)
-- и emp_salary_idx.

-- 2.2
CREATE INDEX emp_dept_idx ON employees(dept_id);

SELECT * FROM employees WHERE dept_id = 101;

-- ОТВЕТ 2.2: PostgreSQL НЕ создаёт индексы на внешние ключи автоматически.
-- Индекс на FK ускоряет JOIN по этому столбцу, поиск дочерних строк по родителю
-- и проверки целостности: при DELETE/UPDATE в родительской таблице СУБД должна
-- найти связанные строки в дочерней, а без индекса это полный перебор таблицы.

-- 2.3
SELECT tablename, indexname, indexdef
FROM pg_indexes
WHERE schemaname = 'public'
ORDER BY tablename, indexname;

-- ОТВЕТ 2.3: индексы на этом этапе:
--   departments: departments_pkey            (автоматически, PK)
--   employees:   employees_pkey              (автоматически, PK)
--                emp_salary_idx              (вручную)
--                emp_dept_idx                (вручную)
--   projects:    projects_pkey               (автоматически, PK)
-- Автоматически созданы только *_pkey.

-- ===== PART 3: Составные индексы =====

-- 3.1
CREATE INDEX emp_dept_salary_idx ON employees(dept_id, salary);

SELECT emp_name, salary
FROM employees
WHERE dept_id = 101 AND salary > 52000;

-- ОТВЕТ 3.1: Для запроса только по salary индекс (dept_id, salary) почти бесполезен.
-- B-tree отсортирован сначала по первому столбцу (dept_id), затем по второму.
-- Без условия на ведущий столбец нельзя быстро перейти к нужному диапазону
-- salary: значения salary разбросаны по всем группам dept_id.
-- Планировщик обычно выберет другой индекс, например emp_salary_idx.

-- 3.2
CREATE INDEX emp_salary_dept_idx ON employees(salary, dept_id);

-- Запрос 1
SELECT * FROM employees WHERE dept_id = 102 AND salary > 50000;
-- Запрос 2
SELECT * FROM employees WHERE salary > 50000 AND dept_id = 102;

-- ОТВЕТ 3.2: Порядок столбцов в индексе важен, порядок условий в WHERE - нет.
-- Запросы 1 и 2 логически идентичны, планировщик их нормализует.
-- Для индекса важно, какой столбец ведущий:
--   (dept_id, salary) - эффективен при равенстве по dept_id + диапазон по salary;
--   (salary, dept_id) - при диапазоне по salary первый столбец ограничивает
--   поиск диапазоном, а dept_id приходится проверять внутри него.
-- Правило: сначала столбцы с условием равенства, затем с диапазоном.

-- ===== PART 4: Уникальные индексы =====

-- 4.1
ALTER TABLE employees ADD COLUMN email VARCHAR(100);
UPDATE employees SET email = 'john.smith@company.com'     WHERE emp_id = 1;
UPDATE employees SET email = 'jane.doe@company.com'       WHERE emp_id = 2;
UPDATE employees SET email = 'mike.johnson@company.com'   WHERE emp_id = 3;
UPDATE employees SET email = 'sarah.williams@company.com' WHERE emp_id = 4;
UPDATE employees SET email = 'tom.brown@company.com'      WHERE emp_id = 5;

CREATE UNIQUE INDEX emp_email_unique_idx ON employees(email);

-- Ожидаемая ошибка (так и должно быть):
INSERT INTO employees (emp_id, emp_name, dept_id, salary, email)
VALUES (6, 'New Employee', 101, 55000, 'john.smith@company.com');

-- ОТВЕТ 4.1:
-- ERROR:  duplicate key value violates unique constraint "emp_email_unique_idx"
-- DETAIL: Key (email)=(john.smith@company.com) already exists.

-- 4.2
ALTER TABLE employees ADD COLUMN phone VARCHAR(20) UNIQUE;

SELECT indexname, indexdef
FROM pg_indexes
WHERE tablename = 'employees' AND indexname LIKE '%phone%';

-- ОТВЕТ 4.2: Да, PostgreSQL автоматически создал уникальный B-tree индекс
-- employees_phone_key (CREATE UNIQUE INDEX ... USING btree (phone)).
-- UNIQUE-ограничение реализуется через уникальный индекс.

-- ===== PART 5: Индексы и сортировка =====

-- 5.1
CREATE INDEX emp_salary_desc_idx ON employees(salary DESC);

SELECT emp_name, salary
FROM employees
ORDER BY salary DESC;

-- ОТВЕТ 5.1: Индекс хранит значения уже в порядке убывания, поэтому СУБД читает
-- строки в готовом порядке и не выполняет отдельную сортировку (Sort).
-- Для одностолбцового индекса это почти не отличается от обычного B-tree
-- (он читается и в обратном направлении), но DESC важен в составных индексах
-- со смешанным порядком, например (a ASC, b DESC).

-- 5.2
CREATE INDEX proj_budget_nulls_first_idx ON projects(budget NULLS FIRST);

SELECT proj_name, budget
FROM projects
ORDER BY budget NULLS FIRST;

-- (Индекс задаёт, что NULL идут в начале, и ORDER BY ... NULLS FIRST может
-- использовать его без дополнительной сортировки.)

-- ===== PART 6: Индексы на выражениях =====

-- 6.1
CREATE INDEX emp_name_lower_idx ON employees(LOWER(emp_name));

SELECT * FROM employees WHERE LOWER(emp_name) = 'john smith';

-- ОТВЕТ 6.1: Без индекса PostgreSQL выполняет Seq Scan: читает каждую строку,
-- вычисляет LOWER(emp_name) и сравнивает с 'john smith'. Обычный индекс по
-- emp_name здесь не помогает, так как условие применяется к выражению, а не
-- к самому столбцу.

-- 6.2
ALTER TABLE employees ADD COLUMN hire_date DATE;
UPDATE employees SET hire_date = '2020-01-15' WHERE emp_id = 1;
UPDATE employees SET hire_date = '2019-06-20' WHERE emp_id = 2;
UPDATE employees SET hire_date = '2021-03-10' WHERE emp_id = 3;
UPDATE employees SET hire_date = '2020-11-05' WHERE emp_id = 4;
UPDATE employees SET hire_date = '2018-08-25' WHERE emp_id = 5;

CREATE INDEX emp_hire_year_idx ON employees(EXTRACT(YEAR FROM hire_date));

SELECT emp_name, hire_date
FROM employees
WHERE EXTRACT(YEAR FROM hire_date) = 2020;

-- ===== PART 7: Управление индексами =====

-- 7.1
ALTER INDEX emp_salary_idx RENAME TO employees_salary_index;

SELECT indexname FROM pg_indexes WHERE tablename = 'employees';

-- 7.2
DROP INDEX emp_salary_dept_idx;

-- ОТВЕТ 7.2: Индекс стоит удалить, если он: не используется; дублирует другой
-- индекс (избыточен); замедляет INSERT/UPDATE/DELETE; занимает много места;
-- раздут (bloat) и дешевле пересоздать.

-- 7.3
REINDEX INDEX employees_salary_index;

-- REINDEX полезен: после массовых вставок/обновлений/удалений, при раздутии
-- индекса, при под
