-- Seeds public.subjects with every course in the five STI Baliuag curricula
-- (BSIT-24-01, BSHM-22-01, BSTM-22-01, BSBA-24-01, BSAIS-24-01), so schedule
-- imports (Classes+Professor, CFL, Room Schedule) find an existing subject
-- instead of auto-creating an `AUTO-xxxxxxxx` one. Source of truth:
-- sample_data/curriculum/curriculum_seed.txt (transcribed from the printed
-- curriculum sheets; per-term unit totals were checked against the printed
-- totals). This file is generated from it.
--
--   * subjects.code is globally UNIQUE and many courses (GEDC/PHED/NSTP/…)
--     are shared by several programs at different year levels, so the
--     per-program placement lives in public.curriculum_entries instead of
--     on subjects.program/year_level (left as-is).
--   * year_level 0 / term 0 = the BSIT "List of Electives".
--   * Where two sheets spell the same code's title differently (only INSY1007:
--     "Systems" vs "System") one spelling is kept arbitrarily; harmless.
--   * Last step re-points class_sections that were attached to an
--     auto-generated `AUTO-…` subject whose title matches a real one, then
--     removes the orphaned AUTO subject.
--
-- Run in Supabase SQL Editor after add_subjects_enrollments_schema.sql.
-- Idempotent.

alter table public.subjects add column if not exists units numeric;

create table if not exists public.curriculum_entries (
  id uuid primary key default gen_random_uuid(),
  program text not null,
  year_level int not null,
  term int not null,
  subject_id uuid not null references public.subjects(id) on delete cascade,
  prerequisites text,
  created_at timestamptz not null default now(),
  unique (program, subject_id)
);

alter table public.curriculum_entries enable row level security;
drop policy if exists "curriculum_entries_select" on public.curriculum_entries;
create policy "curriculum_entries_select" on public.curriculum_entries
  for select to anon, authenticated using (true);

drop table if exists _curriculum_seed;
create temp table _curriculum_seed (
  program text, year_level int, term int, code text, title text,
  units numeric, prerequisites text
);

insert into _curriculum_seed values
('BS Information Technology',1,1,'CITE1004','Introduction to Computing',3,null),
('BS Information Technology',1,1,'CITE1003','Computer Programming 1',3,null),
('BS Information Technology',1,1,'GEDC1002','The Contemporary World',3,null),
('BS Information Technology',1,1,'STIC1002','Euthenics 1',1,null),
('BS Information Technology',1,1,'GEDC1016','Purposive Communication',3,null),
('BS Information Technology',1,1,'NSTP1008','National Service Training Program 1',3,null),
('BS Information Technology',1,1,'PHED1005','P.E./PATHFIT 1: Movement Competency Training',2,null),
('BS Information Technology',1,1,'GEDC1041','Philippine Popular Culture',3,null),
('BS Information Technology',1,1,'GEDC1008','Understanding the Self',3,null),
('BS Information Technology',1,2,'CITE1006','Computer Programming 2',3,'CITE1003'),
('BS Information Technology',1,2,'COSC1002','Discrete Structures 1 (Discrete Mathematics)',3,null),
('BS Information Technology',1,2,'GEDC1010','Art Appreciation',3,null),
('BS Information Technology',1,2,'NSTP1010','National Service Training Program 2',3,null),
('BS Information Technology',1,2,'PHED1006','P.E./PATHFIT 2: Exercise-based Fitness Activities',2,'PHED1005'),
('BS Information Technology',1,2,'GEDC1005','Mathematics in the Modern World',3,null),
('BS Information Technology',1,2,'GEDC1013','Science, Technology, and Society',3,null),
('BS Information Technology',1,2,'GEDC1009','Ethics',3,null),
('BS Information Technology',1,2,'INTE1006','Systems Administration and Maintenance',3,null),
('BS Information Technology',2,1,'COSC1003','Data Structures and Algorithms',3,'CITE1006'),
('BS Information Technology',2,1,'GEDC1006','Readings in Philippine History',3,null),
('BS Information Technology',2,1,'PHED1007','P.E./PATHFIT 3: Individual-Dual Sports',2,'PHED1006'),
('BS Information Technology',2,1,'GEDC1014','Rizal''s Life and Works',3,null),
('BS Information Technology',2,1,'COSC1007','Human-Computer Interaction',3,'CITE1004'),
('BS Information Technology',2,1,'INTE1015','IT Elective 1',3,null),
('BS Information Technology',2,1,'COSC1001','Principles of Communication',3,null),
('BS Information Technology',2,1,'COSC1008','Platform Technology (Operating Systems)',3,null),
('BS Information Technology',2,2,'CITE1011','Information Management',3,'COSC1003'),
('BS Information Technology',2,2,'GEDC1003','The Entrepreneurial Mind',3,null),
('BS Information Technology',2,2,'PHED1008','P.E./PATHFIT 4: Team Sports',2,'PHED1005;PHED1006'),
('BS Information Technology',2,2,'INTE1005','Network Technology 1',3,'CITE1004'),
('BS Information Technology',2,2,'INTE1020','Quantitative Methods',3,'COSC1002'),
('BS Information Technology',2,2,'BUSS1013','Technopreneurship',3,'PHED1001'),
('BS Information Technology',2,2,'INTE1021','Systems Integration and Architecture',3,null),
('BS Information Technology',2,2,'INTE1010','Integrative Programming',3,'CITE1006'),
('BS Information Technology',3,1,'CITE1008','Application Development and Emerging Technologies',3,'CITE1006'),
('BS Information Technology',3,1,'INSY1011','Advanced Database Systems',3,'CITE1011'),
('BS Information Technology',3,1,'INTE1024','Event-Driven Programming',3,'INTE1010'),
('BS Information Technology',3,1,'INTE1025','Data and Digital Communications (Data Communications)',3,'COSC1001'),
('BS Information Technology',3,1,'INSY1003','Professional Issues in Information Systems and Technology',3,'CITE1004'),
('BS Information Technology',3,1,'INTE1056','Advanced Systems Integration and Architecture',3,'INTE1021'),
('BS Information Technology',3,2,'INTE1083','Web Systems and Technologies',3,'CITE1008'),
('BS Information Technology',3,2,'INSY1007','Management Information Systems',3,null),
('BS Information Technology',3,2,'INTE1031','IT Capstone Project 1',3,'INSY1011'),
('BS Information Technology',3,2,'GEDC1045','Great Books',3,null),
('BS Information Technology',3,2,'INTE1027','IT Elective 3',3,'3rd year standing'),
('BS Information Technology',3,2,'INTE1084','Mobile Systems and Technologies',3,'CITE1008'),
('BS Information Technology',3,2,'INSY1010','Information Assurance and Security (Cybersecurity Fundamentals)',3,'CITE1011'),
('BS Information Technology',4,1,'STIC1007','Euthenics 2',1,'STIC1002'),
('BS Information Technology',4,1,'INTE1039','IT Capstone Project 2',3,'INTE1031'),
('BS Information Technology',4,1,'INTE1040','IT Elective 4',3,'4th year standing'),
('BS Information Technology',4,1,'INTE1041','Computer Graphics Programming',3,'CITE1006'),
('BS Information Technology',4,1,'INTE1013','IT Service Management',3,null),
('BS Information Technology',4,1,'INSY1005','Information Assurance and Security (Data Privacy)',3,'INSY1010'),
('BS Information Technology',4,1,'INTE1030','Network Technology 2',3,'INTE1005'),
('BS Information Technology',4,2,'INTE1043','IT Practicum (486 hours)',9,'Candidate for Graduation'),
('BS Information Technology',0,0,'INTE1044','Object-Oriented Programming',3,'CITE1006'),
('BS Information Technology',0,0,'INTE1086','Enterprise Architecture',3,'INTE1044'),
('BS Information Technology',0,0,'INTE1085','Programming Languages',3,'INTE1086'),
('BS Information Technology',0,0,'INTE1050','Game Development',3,'INTE1085'),
('BS Information Technology',0,0,'INTE1047','Introduction to Digital Graphics Design',3,'CITE1006'),
('BS Information Technology',0,0,'INTE1048','Introduction to Computer Animation',3,'INTE1047'),
('BS Information Technology',0,0,'INTE1054','Advanced Digital Graphics Design',3,'INTE1048'),
('BS Information Technology',0,0,'INTE1055','Advanced Computer Animation',3,'INTE1054'),
('BS Information Technology',0,0,'INTE1051','Computer Systems Architecture',3,'CITE1006'),
('BS Information Technology',0,0,'ENGR1035','Robot Dynamics Fundamentals',3,'INTE1051'),
('BS Information Technology',0,0,'INTE1049','Intermediate Human-Computer Interaction',3,'ENGR1035'),
('BS Information Technology',0,0,'ENGR1037','Robot Assembly and Programming',3,'INTE1049'),
('BS Hospitality Management',1,1,'STIC1002','Euthenics 1',1,null),
('BS Hospitality Management',1,1,'GEDC1005','Mathematics in the Modern World',3,null),
('BS Hospitality Management',1,1,'NSTP1008','National Service Training Program 1',3,null),
('BS Hospitality Management',1,1,'PHED1005','P.E./PATHFIT 1: Movement Competency Training',2,null),
('BS Hospitality Management',1,1,'GEDC1006','Readings in Philippine History',3,null),
('BS Hospitality Management',1,1,'GEDC1008','Understanding the Self',3,null),
('BS Hospitality Management',1,1,'CTHC1003','Macro Perspective of Tourism and Hospitality',3,null),
('BS Hospitality Management',1,1,'CTHC1004','Risk Management as Applied to Safety, Security, and Sanitation',3,null),
('BS Hospitality Management',1,2,'NSTP1010','National Service Training Program 2',3,null),
('BS Hospitality Management',1,2,'PHED1006','P.E./PATHFIT 2: Exercise-based Fitness Activities',2,'PHED1005'),
('BS Hospitality Management',1,2,'GEDC1016','Purposive Communication',3,null),
('BS Hospitality Management',1,2,'HOSP1002','Kitchen Essentials and Basic Food Preparation',3,'CTHC1004'),
('BS Hospitality Management',1,2,'STIC1003','Computer Productivity Tools',1,null),
('BS Hospitality Management',1,2,'CTHC1006','Philippine Culture and Tourism Geography',3,'CTHC1003'),
('BS Hospitality Management',1,2,'CTHC1007','Micro Perspective of Tourism and Hospitality',3,'CTHC1003'),
('BS Hospitality Management',2,1,'GEDC1010','Art Appreciation',3,null),
('BS Hospitality Management',2,1,'PHED1007','P.E./PATHFIT 3: Individual-Dual Sports',2,'PHED1005;PHED1006'),
('BS Hospitality Management',2,1,'HOSP1007','Hotel Front Office Operations Management',3,'CTHC1007'),
('BS Hospitality Management',2,1,'HOSP1005','Philippine Regional Cuisines with Food Styling and Design',2,'HOSP1002;CTHC1004'),
('BS Hospitality Management',2,1,'HOSP1008','Fundamentals in Lodging Operations',3,'CTHC1007'),
('BS Hospitality Management',2,1,'CTHC1010','Foreign Language 1',3,null),
('BS Hospitality Management',2,1,'CTHC1008','Quality Service Management in Tourism and Hospitality',3,null),
('BS Hospitality Management',2,2,'GEDC1009','Ethics',3,null),
('BS Hospitality Management',2,2,'PHED1008','P.E./PATHFIT 4: Team Sports',2,'PHED1005;PHED1006'),
('BS Hospitality Management',2,2,'GEDC1013','Science, Technology, and Society',3,null),
('BS Hospitality Management',2,2,'HOSP1009','International Cuisines with Food Styling and Design',2,'HOSP1005;HOSP1002;CTHC1004'),
('BS Hospitality Management',2,2,'HOSP1013','Supply Chain Management in Hospitality Industry',3,null),
('BS Hospitality Management',2,2,'HOSP1014','Fundamentals in Food Service Operations',3,'CTHC1004'),
('BS Hospitality Management',2,2,'CTHC1011','Introduction to Meetings Incentives, Conferences, and Events 3 Management (MICE)',3,null),
('BS Hospitality Management',2,2,'CTHC1012','Foreign Language 2',3,'CTHC1010'),
('BS Hospitality Management',3,1,'CBMC1001','Operations Management (TQM)',3,null),
('BS Hospitality Management',3,1,'GEDC1003','The Entrepreneurial Mind',3,null),
('BS Hospitality Management',3,1,'GEDC1045','Great Books',3,null),
('BS Hospitality Management',3,1,'HOSP1016','Pastry Arts and Bakery Management',2,'HOSP1002'),
('BS Hospitality Management',3,1,'HOSP1019','Applied Business Tools and Technologies in Hospitality',3,'STIC1003'),
('BS Hospitality Management',3,1,'CTHC1013','Professional Development and Applied Ethics',3,'GEDC1009'),
('BS Hospitality Management',3,1,'CTHC1014','Tourism and Hospitality Marketing',3,'CTHC1003;CTHC1007'),
('BS Hospitality Management',3,1,'CTHC1015','Multicultural Diversity in Workplace for the Tourism Professional',3,null),
('BS Hospitality Management',3,2,'CBMC1003','Strategic Management',3,'CBMC1001'),
('BS Hospitality Management',3,2,'GEDC1041','Philippine Popular Culture',3,null),
('BS Hospitality Management',3,2,'HOSP1021','Catering Operations Management',2,null),
('BS Hospitality Management',3,2,'HOSP1022','Modern Gastronomy with Fusion of Cuisines',2,null),
('BS Hospitality Management',3,2,'HOSP1023','Ergonomics and Facilities Planning for the Hospitality Industry',3,null),
('BS Hospitality Management',3,2,'CTHC1016','Legal Aspects in Tourism and Hospitality',3,null),
('BS Hospitality Management',3,2,'CTHC1017','Entrepreneurship in Tourism and Hospitality',3,'GEDC1003'),
('BS Hospitality Management',4,1,'GEDC1002','The Contemporary World',3,null),
('BS Hospitality Management',4,1,'STIC1007','Euthenics 2',1,'STIC1002'),
('BS Hospitality Management',4,1,'GEDC1014','Rizal''s Life and Works',3,null),
('BS Hospitality Management',4,1,'HOSP1024','Specialty Cuisine with Food Exhibit',2,null),
('BS Hospitality Management',4,1,'HOSP1025','Research in Hospitality',3,null),
('BS Hospitality Management',4,2,'OJTC1003','BSHM Practicum (600 hours)',6,'4th year standing'),
('BS Tourism Management',1,1,'STIC1002','Euthenics 1',1,null),
('BS Tourism Management',1,1,'GEDC1005','Mathematics in the Modern World',3,null),
('BS Tourism Management',1,1,'NSTP1008','National Service Training Program 1',3,null),
('BS Tourism Management',1,1,'PHED1005','P.E./PATHFIT 1: Movement Competency Training',2,null),
('BS Tourism Management',1,1,'GEDC1006','Readings in Philippine History',3,null),
('BS Tourism Management',1,1,'GEDC1008','Understanding the Self',3,null),
('BS Tourism Management',1,1,'CTHC1003','Macro Perspective of Tourism and Hospitality',3,null),
('BS Tourism Management',1,1,'CTHC1004','Risk Management as Applied to Safety, Security, and Sanitation',3,null),
('BS Tourism Management',1,2,'NSTP1010','National Service Training Program 2',3,null),
('BS Tourism Management',1,2,'PHED1006','P.E./PATHFIT 2: Exercise-based Fitness Activities',2,'PHED1005'),
('BS Tourism Management',1,2,'GEDC1016','Purposive Communication',3,null),
('BS Tourism Management',1,2,'STIC1003','Computer Productivity Tools',1,null),
('BS Tourism Management',1,2,'CTHC1006','Philippine Culture and Tourism Geography',3,'CTHC1003'),
('BS Tourism Management',1,2,'CTHC1007','Micro Perspective of Tourism and Hospitality',3,'CTHC1003'),
('BS Tourism Management',1,2,'TOUR1003','Global Culture and Tourism Geography',3,null),
('BS Tourism Management',2,1,'GEDC1010','Art Appreciation',3,null),
('BS Tourism Management',2,1,'PHED1007','P.E./PATHFIT 3: Individual-Dual Sports',2,'PHED1005;PHED1006'),
('BS Tourism Management',2,1,'CTHC1008','Quality Service Management in Tourism and Hospitality',3,null),
('BS Tourism Management',2,1,'TOUR1007','Accommodation Operations and Management',3,'CTHC1003;CTHC1004'),
('BS Tourism Management',2,1,'TOUR1008','Tour and Travel Management',3,null),
('BS Tourism Management',2,1,'CTHC1010','Foreign Language 1',3,null),
('BS Tourism Management',2,1,'TOUR1009','Sustainable Tourism',3,null),
('BS Tourism Management',2,2,'GEDC1009','Ethics',3,null),
('BS Tourism Management',2,2,'PHED1008','P.E./PATHFIT 4: Team Sports',2,'PHED1005;PHED1006'),
('BS Tourism Management',2,2,'GEDC1013','Science, Technology, and Society',3,null),
('BS Tourism Management',2,2,'TOUR1012','Tour Planning, Packaging, and Pricing',3,'TOUR1008'),
('BS Tourism Management',2,2,'TOUR1014','Tourism Policy Planning and Development',3,null),
('BS Tourism Management',2,2,'CTHC1011','Introduction to Meetings Incentives, Conferences, and Events 3 Management (MICE)',3,null),
('BS Tourism Management',2,2,'CTHC1012','Foreign Language 2',3,'CTHC1010'),
('BS Tourism Management',3,1,'CBMC1001','Operations Management (TQM)',3,null),
('BS Tourism Management',3,1,'GEDC1003','The Entrepreneurial Mind',3,null),
('BS Tourism Management',3,1,'GEDC1045','Great Books',3,null),
('BS Tourism Management',3,1,'CTHC1013','Professional Development and Applied Ethics',3,'GEDC1009'),
('BS Tourism Management',3,1,'CTHC1014','Tourism and Hospitality Marketing',3,'CTHC1003;CTHC1007'),
('BS Tourism Management',3,1,'CTHC1015','Multicultural Diversity in Workplace for the Tourism Professional',3,null),
('BS Tourism Management',3,1,'TOUR1016','Applied Business Tools and Technologies in Tourism',3,'STIC1003'),
('BS Tourism Management',3,2,'CBMC1003','Strategic Management',3,'CBMC1001'),
('BS Tourism Management',3,2,'GEDC1041','Philippine Popular Culture',3,null),
('BS Tourism Management',3,2,'CTHC1016','Legal Aspects in Tourism and Hospitality',3,null),
('BS Tourism Management',3,2,'CTHC1017','Entrepreneurship in Tourism and Hospitality',3,'GEDC1003'),
('BS Tourism Management',3,2,'TOUR1022','Travel Writing and Photography',3,'GEDC1016'),
('BS Tourism Management',3,2,'TOUR1018','Professional Tour Guiding',3,'CTHC1006;TOUR1003'),
('BS Tourism Management',3,2,'TOUR1019','Transportation Management',3,'TOUR1008'),
('BS Tourism Management',4,1,'GEDC1002','The Contemporary World',3,null),
('BS Tourism Management',4,1,'STIC1007','Euthenics 2',1,'STIC1002'),
('BS Tourism Management',4,1,'GEDC1014','Rizal''s Life and Works',3,null),
('BS Tourism Management',4,1,'TOUR1020','Airline/Flight Operations Management',3,'4th year standing'),
('BS Tourism Management',4,1,'TOUR1021','Research in Tourism',3,null),
('BS Tourism Management',4,2,'OJTC1004','BSTM Practicum (600 hours)',6,'4th year standing'),
('BS Business Administration',1,1,'BUSS1001','Basic Microeconomics',3,null),
('BS Business Administration',1,1,'GEDC1002','The Contemporary World',3,null),
('BS Business Administration',1,1,'STIC1002','Euthenics 1',1,null),
('BS Business Administration',1,1,'NSTP1008','National Service Training Program 1',3,null),
('BS Business Administration',1,1,'PHED1005','P.E./PATHFIT 1: Movement Competency Training',2,null),
('BS Business Administration',1,1,'GEDC1006','Readings in Philippine History',3,null),
('BS Business Administration',1,1,'GEDC1008','Understanding the Self',3,null),
('BS Business Administration',1,2,'GEDC1009','Ethics',3,null),
('BS Business Administration',1,2,'NSTP1010','National Service Training Program 2',3,null),
('BS Business Administration',1,2,'PHED1006','P.E./PATHFIT 2: Exercise-based Fitness Activities',2,'PHED1005'),
('BS Business Administration',1,2,'GEDC1005','Mathematics in the Modern World',3,null),
('BS Business Administration',1,2,'GEDC1013','Science, Technology, and Society',3,null),
('BS Business Administration',1,2,'STIC1003','Computer Productivity Tools',1,null),
('BS Business Administration',1,2,'BUSS1004','Productivity and Quality Tools',3,null),
('BS Business Administration',2,1,'GEDC1041','Philippine Popular Culture',3,null),
('BS Business Administration',2,1,'GEDC1014','Rizal''s Life and Works',3,null),
('BS Business Administration',2,1,'GEDC1016','Purposive Communication',3,null),
('BS Business Administration',2,1,'PHED1007','P.E./PATHFIT 3: Individual-Dual Sports',2,'PHED1005;PHED1006'),
('BS Business Administration',2,1,'BUSS1005','Costing and Pricing',3,null),
('BS Business Administration',2,1,'BUSS1007','Facilities Management',3,null),
('BS Business Administration',2,2,'BUSS1008','Business Law (Obligations and Contracts)',3,null),
('BS Business Administration',2,2,'BUSS1011','Taxation (Income Taxation)',3,null),
('BS Business Administration',2,2,'GEDC1003','The Entrepreneurial Mind',3,null),
('BS Business Administration',2,2,'GEDC1010','Art Appreciation',3,null),
('BS Business Administration',2,2,'PHED1008','P.E./PATHFIT 4: Team Sports',2,'PHED1005;PHED1006'),
('BS Business Administration',2,2,'BUSS1014','Logistics Management',3,null),
('BS Business Administration',3,1,'BUSS1015','Business Research',3,null),
('BS Business Administration',3,1,'BUSS1016','Good Governance and Social Responsibility',3,'GEDC1009'),
('BS Business Administration',3,1,'BUSS1017','International Business and Trade',3,null),
('BS Business Administration',3,1,'CBMC1001','Operations Management (TQM)',3,null),
('BS Business Administration',3,1,'BUSS1019','Managerial Accounting',3,'BUSS1005'),
('BS Business Administration',3,1,'GEDC1045','Great Books',3,null),
('BS Business Administration',3,2,'BUSS1009','Human Resource Management',3,null),
('BS Business Administration',3,2,'CBMC1002','Strategic Management',3,null),
('BS Business Administration',3,2,'INSY1007','Management Information System',3,null),
('BS Business Administration',3,2,'BUSS1021','Environmental Management System',3,null),
('BS Business Administration',3,2,'BUSS1022','Inventory Management and Control',3,'BUSS1005;BUSS1014'),
('BS Business Administration',3,2,'INTE1035','Project Management',3,null),
('BS Business Administration',4,1,'BUSS1024','Feasibility Study',3,'INTE1035'),
('BS Business Administration',4,1,'BUSS1025','Entrepreneurial Management',3,null),
('BS Business Administration',4,1,'BUSS1020','Financial Management',3,null),
('BS Business Administration',4,1,'BUSS1026','Marketing Management',3,null),
('BS Business Administration',4,1,'STIC1007','Euthenics 2',1,'STIC1002'),
('BS Business Administration',4,1,'BUSS1027','Special Topics in Operations Management',3,'CBMC1001'),
('BS Business Administration',4,2,'OJTC1005','Practicum (600 hours)',6,'4th year standing'),
('BS Accounting Information System',1,1,'ACCT1001','Basic Accounting',6,null),
('BS Accounting Information System',1,1,'GEDC1002','The Contemporary World',3,null),
('BS Accounting Information System',1,1,'STIC1002','Euthenics 1',1,null),
('BS Accounting Information System',1,1,'GEDC1041','Philippine Popular Culture',3,null),
('BS Accounting Information System',1,1,'NSTP1008','National Service Training Program 1',3,null),
('BS Accounting Information System',1,1,'PHED1005','P.E./PATHFIT 1: Movement Competency Training',2,null),
('BS Accounting Information System',1,1,'GEDC1006','Readings in Philippine History',3,null),
('BS Accounting Information System',1,1,'GEDC1013','Science, Technology, and Society',3,null),
('BS Accounting Information System',1,1,'GEDC1008','Understanding the Self',3,null),
('BS Accounting Information System',1,2,'ACCT1002','Conceptual Framework and Accounting Standards',3,null),
('BS Accounting Information System',1,2,'ACCT1003','Financial Accounting and Reporting',3,'ACCT1001'),
('BS Accounting Information System',1,2,'BUSS1002','Income Taxation',3,null),
('BS Accounting Information System',1,2,'BUSS1003','Law on Obligations and Contracts',3,null),
('BS Accounting Information System',1,2,'CBMC1001','Operations Management (TQM)',3,null),
('BS Accounting Information System',1,2,'GEDC1009','Ethics',3,null),
('BS Accounting Information System',1,2,'NSTP1010','National Service Training Program 2',3,null),
('BS Accounting Information System',1,2,'PHED1006','P.E./PATHFIT 2: Exercise-based Fitness Activities',2,'PHED1005'),
('BS Accounting Information System',1,2,'GEDC1005','Mathematics in the Modern World',3,null),
('BS Accounting Information System',1,2,'STIC1003','Computer Productivity Tools',1,null),
('BS Accounting Information System',2,1,'ACCT1004','Business Laws and Regulations',3,'BUSS1003'),
('BS Accounting Information System',2,1,'GEDC1045','Great Books',3,null),
('BS Accounting Information System',2,1,'ACCT1005','Intermediate Accounting 1',3,'ACCT1003'),
('BS Accounting Information System',2,1,'INTE1011','IT Application Tools in Business',3,'STIC1003'),
('BS Accounting Information System',2,1,'ACCT1006','Managerial Economics',3,null),
('BS Accounting Information System',2,1,'CBMC1002','Strategic Management',3,null),
('BS Accounting Information System',2,1,'GEDC1014','Rizal''s Life and Works',3,null),
('BS Accounting Information System',2,1,'GEDC1016','Purposive Communication',3,null),
('BS Accounting Information System',2,1,'PHED1007','P.E./PATHFIT 3: Individual-Dual Sports',2,'PHED1005;PHED1006'),
('BS Accounting Information System',2,2,'ACCT1007','Accounting Information System',3,'INTE1011'),
('BS Accounting Information System',2,2,'ACCT1008','Business Taxation',3,'BUSS1002'),
('BS Accounting Information System',2,2,'BUSS1012','Financial Management',3,'ACCT1003'),
('BS Accounting Information System',2,2,'ACCT1009','Intermediate Accounting 2',3,'ACCT1005'),
('BS Accounting Information System',2,2,'ACCT1010','Regulatory Framework and Legal Issues in Business',3,'ACCT1004'),
('BS Accounting Information System',2,2,'GEDC1003','The Entrepreneurial Mind',3,null),
('BS Accounting Information System',2,2,'GEDC1010','Art Appreciation',3,null),
('BS Accounting Information System',2,2,'PHED1008','P.E./PATHFIT 4: Team Sports',2,'PHED1005;PHED1006'),
('BS Accounting Information System',2,2,'INTE1022','Managing Information and Technology',3,null),
('BS Accounting Information System',3,1,'ACCT1013','Cost Accounting and Control',3,'ACCT1001'),
('BS Accounting Information System',3,1,'ACCT1014','Economic Development',3,'ACCT1006'),
('BS Accounting Information System',3,1,'ACCT1015','Financial Markets',3,null),
('BS Accounting Information System',3,1,'ACCT1016','Governance, Business Ethics, Risk Management, and Internal Control',3,'GEDC1009'),
('BS Accounting Information System',3,1,'ACCT1017','Intermediate Accounting 3',3,'ACCT1009'),
('BS Accounting Information System',3,1,'BUSS1017','International Business and Trade',3,null),
('BS Accounting Information System',3,1,'ACCT1018','Statistical Analysis with Software Application',3,'STIC1003'),
('BS Accounting Information System',3,1,'INTE1028','Information Systems Analysis and Design',3,null),
('BS Accounting Information System',3,2,'ACCT1021','Accounting Research Methods',3,'ACCT1018'),
('BS Accounting Information System',3,2,'ACCT1022','Strategic Cost Management',3,'CBMC1002'),
('BS Accounting Information System',3,2,'INTE1032','Data Warehousing and Management',3,'INTE1028'),
('BS Accounting Information System',3,2,'INTE1033','Enterprise Resource Planning and Management',3,null),
('BS Accounting Information System',3,2,'INTE1036','Information Systems Operations and Maintenance',3,null),
('BS Accounting Information System',3,2,'INSY1007','Management Information System',3,null),
('BS Accounting Information System',3,2,'INTE1035','Project Management',3,null),
('BS Accounting Information System',4,1,'ACCT1030','Management Science',3,null),
('BS Accounting Information System',4,1,'ACCT1031','Strategic Business Analysis',3,'CBMC1002'),
('BS Accounting Information System',4,1,'ACCT1032','Business Analytics',3,null),
('BS Accounting Information System',4,1,'ACCT1033','Financial Modeling',3,'STIC1003'),
('BS Accounting Information System',4,1,'BUSS1009','Human Resource Management',3,null),
('BS Accounting Information System',4,1,'ACCT1034','Management Reporting',3,null),
('BS Accounting Information System',4,1,'STIC1007','Euthenics 2',1,'STIC1002'),
('BS Accounting Information System',4,1,'INTE1042','Information Security and Management',3,'INTE1036'),
('BS Accounting Information System',4,2,'ACCT1037','Accounting Research',3,'4th year standing'),
('BS Accounting Information System',4,2,'OJTC1007','Accounting Internship (600 hours)',6,'4th year standing');

insert into public.subjects (code, title, units)
select distinct on (code) code, title, units
from _curriculum_seed
order by code
on conflict (code) do update
  set title = excluded.title,
      units = excluded.units;

insert into public.curriculum_entries (program, year_level, term, subject_id, prerequisites)
select s.program, s.year_level, s.term, sub.id, s.prerequisites
from _curriculum_seed s
join public.subjects sub on sub.code = s.code
on conflict (program, subject_id) do update
  set year_level = excluded.year_level,
      term = excluded.term,
      prerequisites = excluded.prerequisites;

-- Fold earlier auto-generated subjects into the real ones (same title,
-- ignoring case/punctuation/spaces and any trailing "(...)" qualifier).
do $$
declare
  r record;
begin
  for r in
    select a.id as auto_id, real.id as real_id
    from public.subjects a
    join public.subjects real
      on real.code not like 'AUTO-%'
     and regexp_replace(lower(regexp_replace(a.title, '\s*\(.*\)\s*$', '')), '[^a-z0-9]', '', 'g')
       = regexp_replace(lower(regexp_replace(real.title, '\s*\(.*\)\s*$', '')), '[^a-z0-9]', '', 'g')
    where a.code like 'AUTO-%'
  loop
    update public.class_sections set subject_id = r.real_id where subject_id = r.auto_id;
    delete from public.subjects
      where id = r.auto_id
        and not exists (select 1 from public.class_sections where subject_id = r.auto_id);
  end loop;
end $$;
drop table if exists _curriculum_seed;
