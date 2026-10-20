# Why retraining lowered the "Critical" students

## What happened

After the model was retrained on a very small amount of data, students who
had been marked Critical showed lower levels.

## What the app code does (verified by reading it)

- **A retrain never edits stored assessments.** Retraining only calls the model
  service (`POST /retrain`). Every row in `risk_assessments` is inserted by
  "Analyze" or "Batch Analyze" and never updated afterwards, other than the
  `reviewed` flag. Nothing in the app rewrites old levels.
- **But dashboards show each student's latest assessment.** The Overview and the
  student portal read the newest `risk_assessments` row per student. So the
  moment a student is analyzed again after the retrain, the new (retrained)
  model's answer replaces the old one on screen. Running Batch Analyze for the
  whole roster re-scores everyone at once, which is why it looked as if every
  past Critical student was lowered together.
- **A retrain on tiny data can still become the live model.** The service
  decides this ("promoted") and the app only displayed "Promoted · ROC-AUC".
  A model trained and tested on a few dozen students can score well on its tiny
  test set and then rate the real population very differently.

## What changed in the app

- The Retrain card now shows **how many students the model was trained and
  tested on**, and a **"Small sample" warning** (under 200 trained / 50 tested)
  that says the run replaced the live model and that levels change only when
  students are analyzed again.
- **Retraining now asks for confirmation** and states that risk levels can change
  the next time students are analyzed.

## What has to change in the model service (not in this repo)

The service lives in `Behavioral AI Model/`, which is not checked in here. Its
`/retrain` endpoint should:

1. refuse (or never promote) a run below a minimum number of labeled students
   and a minimum number of each class in the test split;
2. promote a challenger only if it beats the champion **on the same held-out
   test set**, by a margin, not just on its own set;
3. return a model version with `/predict` so each stored assessment can record
   which model produced it, and the dashboard can show "model changed" rather
   than a silent drop.

Until then, avoid running Batch Analyze right after a retrain that shows the
Small sample warning.
