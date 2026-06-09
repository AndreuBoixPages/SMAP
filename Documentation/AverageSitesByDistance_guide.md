# Averaging Sites by Distance — Step-by-Step Guide

**Plugin:** `ROIManager → Analyze → AverageSitesByDistance`  
**Purpose:** Average super-resolution sites (e.g. endocytic pits) grouped by a physical
distance rather than by site index. Designed for two-colour experiments where one marker
labels a ring structure (e.g. Sla2) and the other labels a cap (e.g. Myo5), and you want
to average sites binned by the ring-to-cap distance (a proxy for invagination depth).

---

## Prerequisites

- SMAP installed and working
- A `.mat` data file with sites already marked, rotated and saved
- The LocMoFit model settings file for your experiment
  (e.g. `Myo5_Sla2_settings_ver2_LocMoFit.mat`)
- The `AverageSitesByDistance.m` plugin present in
  `SMAP/plugins/+ROIManager/+Analyze/`

### One-time fixes required on installations without the Statistics / Optimization Toolboxes

If MATLAB lacks the **Statistics and Machine Learning Toolbox** and/or the
**Global Optimization Toolbox**, two small patches are needed in LocMoFit:

1. **`range()` shim** — file already present at
   `SMAP/LocMoFit/helperFcn/range.m`
   *(replaces the toolbox `range()` with `max−min`; no action needed if the file exists)*

2. **`grpstats()` replacement** — already patched in
   `SMAP/LocMoFit/@LocMoFit/LocMoFit.m` (search for "grpstats replacement")
   *(replaced with an `arrayfun`+`median` one-liner)*

3. **Optimizer** — in the LocMoFitGUI panel change the **Optimizer** dropdown from
   `particleswarm` (requires Global Optimization Toolbox) to **`fminsearchbnd`**
   (built into SMAP, no toolbox needed). Do this once and re-save the settings file.

---

## Step 1 — Load your data in SMAP

1. Start SMAP (`>> SMAP` in the MATLAB console, or double-click the app).
2. Load your `.mat` file via **File → Open** (or drag-and-drop).
3. Confirm sites appear in the **ROI Manager** (site explorer panel on the right).

---

## Step 2 — Run LocMoFit to get fitted distances

LocMoFit fits a geometric model (ring + cap) to each site and stores the fitted
parameters — including the positions of both model components — in
`site.evaluation.LocMoFitGUI.allParsArg`.

1. In the main SMAP window, go to the **Evaluate** tab of the ROI Manager.
2. You should see a small modules table at the top. **LocMoFitGUI** should be listed
   with its checkbox ticked. If not, click **"add module"** and select LocMoFitGUI.
3. In the LocMoFitGUI panel, go to **Settings → load** and load your model file
   (`Myo5_Sla2_settings_ver2_LocMoFit.mat` or equivalent).
4. Make sure **"Review only"** is **unchecked**.
5. Set the **Optimizer** to **`fminsearchbnd`** (no extra toolbox required).
6. Make sure **"evaluate on"** is ticked.
7. Click **"redraw all"** — SMAP loops through every site and fits the model.
   Progress is shown in the status bar ("redrawall: site X of Y").
   This may take several minutes.

> **Verify:** Click any site in the list, then in the MATLAB console run:
> ```matlab
> global se
> fieldnames(se.sites(1).evaluation.LocMoFitGUI)
> ```
> You should see `allParsArg` in the list.

---

## Step 3 — Open AverageSitesByDistance

Go to **Plugins → ROIManager → Analyze → AverageSitesByDistance**.
A small window appears with these fields:

| Field | Description |
|-------|-------------|
| Distance field | Path or formula that returns the per-site distance in nm |
| Bin edges (nm) | Single number = uniform bin width; comma-separated = custom edges |
| Sites to use | "all" or only sites marked with "use" |
| Name | Label for the output dataset |
| Add averages as new datasets | Tick to store results back in SMAP |
| Bins per row / all in one file | Layout of the averaged output |

---

## Step 4 — Set the distance field

The ring-to-cap distance is **not stored as a single parameter** — it must be computed
from the fitted positions of the two model components.

For the **Myo5 + Sla2 model** the relevant parameters are:

| Index | Name | Model | Description |
|-------|------|-------|-------------|
| 1 | x | Ring (Sla2) | Ring x-position in site frame |
| 2 | y | Ring (Sla2) | Ring y-position in site frame |
| 14 | y | Cap (Myo5) | Cap y-position in site frame (x is fixed at 0) |

**Euclidean distance formula:**

```
@sqrt(v(1)^2+(v(2)-v(14))^2)
```

Type this **directly into the Distance field box**.
The `@` prefix tells the plugin to evaluate the expression, where:
- `v` = `allParsArg.value` (the vector of all fitted parameter values)
- `s` = the full site struct
- `ap` = `site.evaluation.LocMoFitGUI.allParsArg`

> **Note on parameter indices:** indices 1, 2, and 14 are correct for the
> `Myo5_Sla2_settings_ver2_LocMoFit.mat` model. If a different model file is used,
> verify the indices with:
> ```matlab
> global se
> ap = se.sites(1).evaluation.LocMoFitGUI.allParsArg;
> for k=1:length(ap.value)
>     fprintf('%2d  fix=%d  %-20s  value=%.4g\n', k, ap.fix(k), ap.name{k}, ap.value(k))
> end
> ```
> Look for the **free** (`fix=0`) x and y parameters of each model component.

---

## Step 5 — Set bin edges and preview

- **Bin edges:** type `20` for uniform 20 nm bins, or e.g. `10,30,60` for custom
  bins (< 10 nm, 10–30 nm, 30–60 nm, > 60 nm).
- Click **"preview"** to see how many sites fall in each bin without running the
  full averaging. Adjust bin width until the distribution looks sensible.

Expected: more sites at small distances (early/shallow invaginations) and fewer
at large distances (deep invaginations).

---

## Step 6 — Run

1. Tick **"add averages as new datasets"** if you want the output stored in SMAP.
2. Click **Run**.
3. A scatter plot and radial distribution plot appear for the last non-empty bin.
4. The averaged localizations for each bin are added as new datasets (if ticked).

---

## Troubleshooting

| Error | Cause | Fix |
|-------|-------|-----|
| `Undefined function 'optimoptions'` | Global Optimization Toolbox missing | Switch Optimizer to `fminsearchbnd` |
| `Unrecognized parameter 'UseVectorized'` | Old solver options saved in settings file | Delete that row from the optimizer parameters table |
| `Undefined function 'grpstats'` | Statistics Toolbox missing | Already patched in `LocMoFit.m` |
| `Undefined function 'range'` | Statistics Toolbox missing | Already patched via `helperFcn/range.m` |
| `allParsArg` missing from evaluation | LocMoFit didn't run or failed | Check "Review only" is off; re-run "redraw all" |
| All distances are 0 or negative | Wrong parameter index | Re-check indices with the console snippet above |

---

*Guide written for the Myo5/Sla2 endocytosis experiment setup.*
*Plugin file: `SMAP/plugins/+ROIManager/+Analyze/AverageSitesByDistance.m`*
