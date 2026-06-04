# OULAD learning analytics

Can early activity help decide which enrollments to review for withdrawal risk? In the held-out October intake, logistic regression identified **388 future withdrawals in 905 reviews**, compared with **229** using the early-inactivity rule. The model underestimated absolute risk. A separate analysis of course completion found a larger adjusted October–February difference in 2014 than in 2013. Both analyses use anonymized Open University records. [Withdrawal evaluation](notebooks/05_withdrawal_risk.ipynb) · [Completion analysis](notebooks/03_ab_test.ipynb) · [Dataset paper](https://doi.org/10.1038/sdata.2017.171)

## Results and where to reproduce them

An enrollment is a student–module–presentation record. Students can appear more than once. Cell references below are the execution numbers visible in the saved notebooks. Intervals are 95% intervals. The risk analysis resamples students with all their enrollments. The seasonal comparisons use student-clustered standard errors.

| Measure | Executed result | Notebook and cell |
| --- | --- | --- |
| Dataset size | 32,593 enrollments, 28,785 student IDs, 10,655,280 VLE event rows | [Preparation](notebooks/01_data_preparation.ipynb), In [2] |
| Share of all enrollments at each milestone | 89.7% clicked, 79.2% had a scored assessment, 47.2% earned Pass or Distinction, 31.2% withdrew | [Funnel](notebooks/02_product_analytics.ipynb), In [2] · [Outcomes](notebooks/01_data_preparation.ipynb), In [4] |
| Completion by early activity, all enrollments | 55.3% with a positive click on days 0–13 vs 12.4% without one | [Early activity](notebooks/01_data_preparation.ipynb), In [17] |
| Largest average weekly drop in the retention index | Week 10, −10.1 percentage points | [Retention](notebooks/02_product_analytics.ipynb), In [7] |
| Illustrative gross lifetime revenue per enrollment | £3,537 in the High click tier and £2,507 in the Inactive tier | [Revenue scenario](notebooks/02_product_analytics.ipynb), In [9] |
| Adjusted completion difference, October minus February | 2013 **+1.05 pp** [−0.75, +2.85]. 2014 **+3.79 pp** [+1.95, +5.62] | [Seasonal contrasts](notebooks/03_ab_test.ipynb), In [2] |
| Change in that seasonal difference | **+2.74 pp** [+0.18, +5.29] across the common modules BBB, DDD and FFF | [Panel and interaction](notebooks/03_ab_test.ipynb), In [1–2] |
| Validation ROC-AUC of the full logistic model, common 2014B origin | Day 14 **0.5265**. Day 28 **0.5812**. Day 42 **0.6155**. Day 42 won the two-fold selection with mean average precision **0.2389** | [Temporal validation](notebooks/05_withdrawal_risk.ipynb), In [4–5] |
| Final 2014J evaluation population, start of day 42 | 9,041 eligible enrollments, 1,611 official withdrawals (17.82%). Top 10% review budget rounded up to 905 | [Holdout](notebooks/05_withdrawal_risk.ipynb), In [6] |
| Logistic regression, ranking | ROC-AUC **0.6883** [0.6740, 0.7031]. Average precision **0.3488** [0.3253, 0.3740] | [Ranking and bootstrap](notebooks/05_withdrawal_risk.ipynb), In [6–7] |
| Logistic regression, review queue | **388/905**, precision **42.87%** [39.53%, 46.47%], lift **2.4060×** [2.2409, 2.5756] | [Review queue](notebooks/05_withdrawal_risk.ipynb), In [6–7] |
| Rule and gradient boosting at the same budget | No click on days 0–13 identified **229/905**. Boosting identified **362/905**. Logistic minus rule average precision was **+0.1608** [+0.1393, +0.1822] | [Paired comparison](notebooks/05_withdrawal_risk.ipynb), In [6–7] |
| Logistic calibration | Mean predicted risk **16.16%**, observed **17.82%**. Brier score **0.1355** [0.1305, 0.1406] | [Calibration](notebooks/05_withdrawal_risk.ipynb), In [6–8] |
| Published vs corrected retention, 2013B week 1 | **96.8% → 93.6%**. Across **104** cohort-week cells the published extract had **3** above 100%. The refresh had **0** | [Tableau reconciliation](notebooks/04_tableau_export.ipynb), In [4] |

### Interpreting the results

**Withdrawal risk.** The large early-click gap describes completion among everyone who enrolled. By the time a support team can act, many inactive students have already withdrawn. Among remaining enrollments, early inactivity separates future withdrawals much less clearly. Weekly click counts, recency, activity types, the first assessment and entry information add signal. Waiting for more activity also shortens the intervention window. The notebook lists each feature, its cutoff and the registrations that can contribute to prior history. [Risk sets and feature audit](notebooks/05_withdrawal_risk.ipynb)

**Temporal validity.** Only dated registrations still at risk enter the queue. Earlier modules must have finished before training labels can be used. Overlapping terms leave the same February training intake for both development origins. Day 14 has a common-origin diagnostic after outcomes mature, but lacks two usable selection folds. The source has no timestamp for final-result publication. Training therefore reconstructs known withdrawals from dated exits and audits agreement with the official label. One final intake measures ranking and calibration; intervention effectiveness would require a separate study. [Validation protocol and label audit](notebooks/05_withdrawal_risk.ipynb)

**Seasonality.** The pooled analysis uses modules offered in every season and year and adjusts for module and entry characteristics. The notebook also gives the same-season year comparisons, every available within-module pair, the original cross-year BBB comparison, and risk-ratio E-values for sensitivity to unmeasured confounding. Student mix, assessment design and other calendar changes can explain some of the association. Mean marks apply only to enrollments with a recorded mark. [Design and sensitivity analysis](notebooks/03_ab_test.ipynb)

**Engagement and revenue.** Funnel milestones are counted independently. Weekly retention is an activity index with an early-peak denominator. The lifetime revenue scenario uses assumed fees, repeat enrollment and referrals. OULAD records learning activity and outcomes and supplies no observed revenue for this calculation. [Product analytics](notebooks/02_product_analytics.ipynb)

## Reproduce locally

Extract the seven source CSVs into `data/raw/`. Use Python 3.12 and run the notebooks in filename order. Notebook 01 builds the enrollment table, notebook 02 saves weekly retention, and notebook 04 reads both. Plotly figures use its CDN. [Dataset download](https://www.kaggle.com/datasets/anlgrbz/student-demographics-online-education-dataoulad)

```bash
python3.12 -m venv env
source env/bin/activate
python -m pip install -r requirements.txt
python -m ipykernel install --sys-prefix --name oulad
OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 VECLIB_MAXIMUM_THREADS=1 \
  jupyter nbconvert --to notebook --execute --inplace --ExecutePreprocessor.kernel_name=oulad \
  --ExecutePreprocessor.timeout=450 notebooks/0*.ipynb
```

The schema and complete query library ran on PostgreSQL with the original CSVs. The enrollment counts, funnel, early-click completion, balanced-panel totals, weekly retention and revenue scenario were cross-checked against notebook results. Run the schema in a fresh database from the repository root. [Schema and load](sql/01_setup_schema.sql) · [Analytical queries](sql/02_queries.sql)

```bash
createdb oulad
psql -X -d oulad -v ON_ERROR_STOP=1 -f sql/01_setup_schema.sql
psql -X -d oulad -v ON_ERROR_STOP=1 -f sql/02_queries.sql
```

## Tableau workbook refresh

The published heatmap divides each week's distinct active IDs by Week 0 and allows percentages above 100. Notebook 02 counts distinct IDs with a positive click across modules within each presentation. Its denominator is the peak weekly count in weeks 0–2. It caps the ratio at one and gives presentations equal weight when calculating the weekly change. [Published dashboard](https://public.tableau.com/app/profile/aitugan.shagyr/viz/OULADLearningAnalyticsEngagementRetentionOutcomes/Dashboard1?publish=yes) · [Export comparison](notebooks/04_tableau_export.ipynb)

- Replace the workbook data sources with the matching CSVs generated in `data/processed/tableau/`. The checked-in files in `outputs/tableau/` are the archived published extracts.
- For the heatmap use `cohort` and `week` as dimensions. Use `MIN([retention_rate])` for color and labels at that grain. The export stores percentage points; use a numeric format with a literal percent suffix. Remove the Week 0 table calculation. Check the example and upper bound in the results table before republishing.
- Label funnel counts **Enrollments**, the assessment milestone **At least one scored assessment**, and the final completion milestone **Pass or Distinction**. Label the regional score **Mean among scored enrollments**. Republish the workbook from the owner's Tableau account.

The proposed GitHub description and topics are ready to copy. [Repository metadata](REPOSITORY_METADATA.md)
