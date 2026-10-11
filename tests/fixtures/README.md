# Test company

Five hand-built opportunities for one rep. Expected pipeline waterfall for Q1 2024 (close dates in Jan–Mar 2024):

| Opportunity | Story | Waterfall effect |
|---|---|---|
| 006FIXTURE0001 | In pipeline at $10,000 on Jan 1; won on Mar 28 at $12,000 | opening 10,000; won 12,000; amount change +2,000 |
| 006FIXTURE0002 | Due Feb 29 at $20,000; close date pushed to Apr 30 on Feb 20 | opening 20,000; moved out 20,000 |
| 006FIXTURE0003 | Created Jan 15 at $5,000, raised to $6,000; still open | created 6,000; closing 6,000 |
| 006FIXTURE0004 | Due in Q2; pulled into March on Jan 20; lost Mar 15 | pulled in 30,000; lost 30,000 |
| 006FIXTURE0005 | Due Jan 31 at $8,000; never updated, still open | opening 8,000; closing 8,000 |

Opening 38,000 + created 6,000 + pulled in 30,000 − won 12,000 − lost 30,000 − moved out 20,000 + amount change 2,000
= closing 14,000. Asserted in tests/data_tests/assert_fixture_known_answers.sql.
