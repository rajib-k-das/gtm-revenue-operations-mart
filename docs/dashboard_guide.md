# Building the Tableau Public dashboard

Everything is done in the browser (Tableau Public web authoring); nothing is installed.
Tableau occasionally renames buttons, so if a label differs slightly, look for the closest match.

## 0. Produce the data (in the codespace)

```bash
source .venv/bin/activate
python generate/generate_crm.py
python ingest/load_crm.py
dbt build
python scripts/export_for_tableau.py
```

This writes five files to `exports/`. In the codespace Explorer, right-click each one and choose **Download**.
Save them in a new, empty folder (e.g. `Documents/kestrel-dashboard`) so no other file is uploaded by mistake.

| File | One row per | Used for |
|---|---|---|
| `pipeline_waterfall.csv` | quarter, region, segment, waterfall step | View 1: pipeline waterfall |
| `deal_timing.csv` | event, week of the quarter | View 2: when deals close and slip |
| `forecast_accuracy.csv` | rep, quarter, week of the quarter | View 3: forecast accuracy |
| `rep_quarters.csv` | rep, quarter | View 4: coverage vs attainment |
| `arr_bridge.csv` | quarter, region, ARR movement | View 5: ARR bridge |

All five are synthetic (the fictional company Kestrel Cloud), so they can be published.

## 1. Start a workbook

1. Go to **public.tableau.com**, sign in with your personal account, click **Create → Web Authoring**.
2. Upload **pipeline_waterfall.csv**. Wait until the data preview shows rows.
3. Add the other four **one at a time**: **Data → New Data Source → Files → Upload from computer**. Wait for each to
   load before adding the next. (Adding several at once caused the red "!" in Project 2.)
4. Each view uses one data source; there are no joins. At the top of the Data pane, a dropdown picks the data source.

**Before each view, check the field types** in the Data pane. Fields above the line are dimensions (blue), below it
measures (green). If a field listed below as a dimension sits among the measures, drag it up above the line
(or click its dropdown → **Convert to Dimension**).

## 2. View 1 — "Pipeline Waterfall" (data source: pipeline_waterfall)

How this quarter's pipeline moved, from what was due at the start to what is still open at the end.

1. Rename the sheet: **Pipeline Waterfall**.
2. Make **Step Order** a dimension (it is a number, so Tableau treats it as a measure).
3. Drag **Step** to **Rows**. Click the **Step** pill → **Sort** → **Sort By: Field**, **Field Name: Step Order**,
   **Aggregation: Minimum**, **Ascending**. The bars now run Opening → Created → … → Closing.
4. Drag **Bar Start** to **Columns** (SUM).
5. Marks card: change **Automatic** to **Gantt Bar**.
6. Drag **Bar Size** to **Size** (SUM). The bars now float: decreases extend to the left, increases to the right.
7. Drag **Step Type** to **Color**. Colors: Total = dark grey, Increase = blue, Decrease = orange, Change = light grey.
8. Drag **Amount** to **Label** (SUM). Format it: click the pill → **Format** (or right-click **Amount** in the Data
   pane → **Default Properties → Number Format**) → **Currency (Custom)**, 1 decimal, **Display Units: Millions (M)**.
   Format **Bar Start** the same way so the axis reads in $M.
9. Drag **Quarter** to **Filters** → choose only **2025 Q4** → OK. Click the pill → **Show Filter**, then on the filter
   card's menu choose **Single Value (dropdown)**.
10. Drag **Region** to **Filters** → **All** → OK → **Show Filter** (multiple values). Do the same for **Segment**.
11. Title: *Pipeline due this quarter: how it moved (Quarter filter at right)*.

Check: for 2025 Q4, all regions, Opening ≈ $7.7M and Closing ≈ $0.7M. The steps between must land exactly on the
Closing bar; if they don't, Bar Size or Bar Start is not on SUM.

## 3. View 2 — "When Deals Close and Slip" (data source: deal_timing)

1. New sheet, rename it **Deal Timing**.
2. Make **Week Of Quarter** a dimension (see section 1).
3. Drag **Week Of Quarter** to **Columns** and **Event** to **Rows**. You get two panels.
4. Drag **Share Of Events** to **Rows**, to the right of Event (SUM). Marks: **Bar**.
5. Create a calculated field (**Analysis → Create Calculated Field**), name **Last Three Weeks**:
   ```
   [Week Of Quarter] >= 11
   ```
   Drag it to **Color**: True = orange, False = grey.
6. Drag **Share Of Events** to **Label**; format **Percentage**, 0 decimals.
7. Title: *Deals won and close dates pushed out, by week of the quarter*.

The two shapes are the finding: a spike of wins in week 13 (the hockey stick) and most pushes in weeks 11–12
(the end-of-quarter scrub).

## 4. View 3 — "Forecast Accuracy" (data source: forecast_accuracy)

How far each group's commit forecast sat from the final bookings, week by week.

1. New sheet, rename it **Forecast Accuracy**.
2. Make **Week Of Quarter** a dimension, then drag it to **Columns**.
3. Drag **Commit Error** to **Rows**. Click the pill → **Measure** → **Median**.
4. Format **Commit Error** as **Percentage**, 0 decimals.
5. Marks: **Line**. Drag **Forecast Style** to **Color**: Optimistic = orange, Accurate = blue, Conservative = purple.
6. Analytics pane (tab next to Data): drag **Constant Line** onto the chart, drop it on the **Commit Error** axis,
   value **0**. This is "forecast = actual".
7. Drag **Region** to **Filters** → All → **Show Filter**.
8. Title: *Median commit forecast error by week of the quarter (0% = forecast matched bookings)*.
9. Caption or subtitle: *Forecast style is the generator's answer key, shown so the recovery can be judged.*

## 5. View 4 — "Coverage vs Attainment" (data source: rep_quarters)

Does more pipeline mean more bookings? One dot per rep.

1. New sheet, rename it **Coverage vs Attainment**.
2. Create two calculated fields:
   - **Pipeline Coverage**: `SUM([Opening Pipeline]) / SUM([Quota Amount])` — format **Number (Custom)**, 1 decimal,
     suffix `x`.
   - **Quota Attainment**: `SUM([Bookings]) / SUM([Quota Amount])` — format **Percentage**, 0 decimals.
   (Sum first, then divide, so a rep's whole history is weighted correctly.)
3. Drag **Pipeline Coverage** to **Columns** and **Quota Attainment** to **Rows**.
4. Drag **Rep Name** to **Detail**. You now have 24 dots.
5. Drag **Region** to **Color**: APAC = orange, EMEA = teal, North America = blue.
6. Marks: **Shape**. Drag **Segment** to **Shape** (e.g. circle = Mid-Market, square = Enterprise). Size: one step up.
7. Analytics pane: drag **Constant Line** to the **Quota Attainment** axis, value **1** (100% of quota).
8. Drag **Quarter** to **Filters** → All → **Show Filter** (multiple values).
9. Title: *Opening pipeline coverage vs quota attainment, by rep*.

What to look for: the APAC dots sit to the right (plenty of pipeline) but low (attainment well under 100%).

## 6. View 5 — "ARR Bridge" (data source: arr_bridge)

1. New sheet, rename it **ARR Bridge**.
2. Drag **Quarter** to **Columns** and **Amount** to **Rows** (SUM). Marks: **Bar**.
3. Make **Component Order** a dimension. Drag **Component** to **Color**, then sort it: click the **Component** pill on
   the Marks card → **Sort** → **Field: Component Order**, Minimum, Ascending.
   Colors: New logo = blue, Expansion = teal, Renewal uplift = green, Churn = red. Churn sits below zero.
4. Format **Amount** as **Currency (Custom)**, 1 decimal, **Millions (M)**.
5. Drag **Region** to **Filters** → All → **Show Filter**.
6. Title: *ARR added and lost each quarter (ARR grew from $0.6M to $20.7M)*.

## 7. The dashboard

1. **New Dashboard**. Size: **Fixed**, **1400 × 1350**.
2. Text at the top:
   - Title: **B2B Pipeline Analytics: Waterfall, Slippage, Forecast Accuracy and ARR**
   - Subtitle: *Kestrel Cloud, a fictional B2B SaaS company: 24 reps, 3,000 accounts, ~4,000 opportunities, 2023–2025.
     Synthetic CRM data with five planted behaviours the analysis has to find.*
3. Layout (drag sheets in; use a **Horizontal** container for each row):
   - Row 1: **Pipeline Waterfall** (about 60% width) | **Deal Timing**
   - Row 2: **Forecast Accuracy** | **Coverage vs Attainment**
   - Row 3: **ARR Bridge**, full width
4. Filters stay with their own sheet (each view uses its own data source). Move each filter card next to its chart
   or delete any duplicates Tableau adds on the right.
5. Footer text: *Built with Python, dbt and DuckDB; every number reconciles in tested SQL. Code and methodology:
   github.com/rajib-k-das/gtm-revenue-operations-mart. All data is synthetic.*

## 8. Publish

1. **File → Save** (or **Publish**). Name: **B2B Pipeline Analytics**. Make sure the **dashboard** tab is the active
   tab when you publish, so the link opens on it.
2. Open the published viz from your profile and check it in a private browser window.
3. Copy its link (the `/app/profile/.../viz/...` address) and send it over: it goes in the README, and a screenshot
   saved as `docs/dashboard.png` goes at the top of the README.
