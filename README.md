# OULAD learning analytics

![Python](https://img.shields.io/badge/Python-3.11-3776AB?style=flat&logo=python&logoColor=white)
![SQL](https://img.shields.io/badge/SQL-PostgreSQL-4169E1?style=flat&logo=postgresql&logoColor=white)
![Tableau](https://img.shields.io/badge/Tableau-Public-E97627?style=flat&logo=tableau&logoColor=white)
![Jupyter](https://img.shields.io/badge/Jupyter-Notebook-F37626?style=flat&logo=jupyter&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-green?style=flat)

Product analytics project using the Open University Learning Analytics Dataset — real behavioral data from 32,000 students across 22 online courses. I worked through the full analyst cycle: cleaning and merging seven source tables, building engagement funnels and cohort retention curves, estimating student LTV, running a quasi-experimental A/B test, and publishing a Tableau dashboard.

---

## Live dashboard

> [View on Tableau Public →](https://public.tableau.com/app/profile/aitugan.shagyr/viz/OULADLearningAnalyticsEngagementRetentionOutcomes/Dashboard1?publish=yes)

---

## Business questions

1. Where do students drop out, and which stage loses the most people?
2. Which enrollment cohorts retain well, and when do they fall off?
3. How much is a student worth at each level of engagement?
4. Did the later course presentation produce better outcomes than the earlier one?
5. Which content types and regions show the highest completion rates?

---

## What the data showed

About 30% of students withdraw before finishing their module — the biggest single drop-off event in the dataset. Students who interact with the platform in their first 14 days complete at roughly 2–3× the rate of those who don't, so week-1 activation is the most obvious place to intervene. The LTV gap between a high-engagement student and an inactive one works out to over £1,100, driven mostly by re-enrollment rather than referrals. Week 4 is where the steepest average retention drop happens across all cohorts. Assessment-type activities — TMAs and quizzes — show a much stronger relationship with completion than passive content like videos or reading materials.

---

## Project structure

```
oulad-analytics/
├── notebooks/
│   ├── 01_data_preparation.ipynb     # load, clean, merge all 7 tables; feature engineering
│   ├── 02_product_analytics.ipynb    # funnel, cohort retention heatmap, LTV + sensitivity
│   ├── 03_ab_test.ipynb              # quasi-experiment: t-test, Mann-Whitney, Cohen's d, bootstrap CI
│   └── 04_tableau_export.ipynb       # export Tableau-ready CSVs + step-by-step dashboard guide
├── sql/
│   ├── 01_setup_schema.sql           # PostgreSQL schema + \COPY data load commands
│   └── 02_queries.sql                # analytical query library (PostgreSQL 14+)
├── data/
│   ├── raw/                          # OULAD source CSVs (not committed — download separately)
│   └── processed/                    # cleaned & merged outputs
├── outputs/
│   └── tableau/                      # Tableau-ready CSVs
├── assets/                           # charts saved during notebook runs
├── requirements.txt
├── .gitignore
└── README.md
```

---

## Tech stack

| Tool | Purpose |
|------|---------|
| Python / Pandas / NumPy | Data wrangling, feature engineering |
| Matplotlib / Seaborn / Plotly | Visualisation |
| SciPy / Statsmodels | A/B testing, statistical inference |
| SQL (PostgreSQL 14+) | Schema design, indexing, analytical queries across all 7 tables |
| Tableau Public | Interactive dashboard |
| Jupyter Notebook | Reproducible analysis |
| Git / GitHub | Version control |

---

## Dataset

Open University Learning Analytics Dataset (OULAD), released by The Open University UK under CC BY 4.0.

| Table | Description | Rows |
|-------|-------------|------|
| `studentInfo` | Demographics, disability, prior education, final result | ~32,000 |
| `studentRegistration` | Enrollment and unregistration dates | ~32,000 |
| `studentAssessment` | Assessment scores and submission timestamps | ~173,000 |
| `studentVle` | Daily click interactions per student per resource | ~10.6M |
| `assessments` | Assessment metadata (type, weight, due date) | ~206 |
| `vle` | Virtual Learning Environment resource metadata | ~6,364 |
| `courses` | Module and presentation metadata | ~22 |

Download: https://analyse.kmi.open.ac.uk/open_dataset

---



---

## Statistical methods

| Method | Used for |
|--------|---------|
| Shapiro-Wilk | Normality check before choosing parametric vs non-parametric test |
| Welch's t-test | Comparing mean assessment scores between groups (unequal variance) |
| Mann-Whitney U | Non-parametric comparison of score distributions |
| Chi-square | Comparing completion rates (binary outcome) between groups |
| Cohen's d | Effect size of the observed difference |
| Bootstrap CI (10,000 iterations) | Distribution-free confidence intervals for the mean difference |
| Power analysis | Required sample size for future experiments |

---

## License

MIT License. The OULAD dataset is CC BY 4.0.  
Citation: Kuzilek J., Hlosta M., Zdrahal Z. (2017). *Open University Learning Analytics dataset*. Sci. Data 4:170171. doi:10.1038/sdata.2017.171
