# RSNA Knee Abnormality Detection – plan (not executable in this session)

**Status:** planning only. This session has no GPU, ~30 GB of disk and no Kaggle credentials,
while the competition data is ~570 GB of DICOM plus radiology reports and inference must run
in a Kaggle code notebook. Everything below is what to run in a Kaggle GPU notebook.

## Facts gathered

| Item | Value | Source |
|---|---|---|
| Task | 12 binary findings per knee MRI study (multilabel) | competition page, community repo |
| Metric | macro ROC-AUC across the 12 labels | community repo README |
| Studies | 4,407 training studies; **only 58 carry expert labels**, 4,349 have reports only | community repo README |
| Sites / languages | 16-19 sites, reports in 9-12 languages | RSNA site, RuntimeWire |
| Data size | ~570 GB, ~819k DICOM files | community repo README |
| Format | Code competition: ≤ 9 h runtime, internet off, Tesla T4 GPU | community repo README |
| Rules | Report text must not be sent to hosted LLM APIs; open-weight models only | community repo README |
| Timeline | Entry Oct 15 2026, final submission Oct 22 2026, winners Nov 5 2026 | RuntimeWire |
| Prize | $77,000 incl. an efficiency track | RSNA |

Sources: https://www.rsna.org/artificial-intelligence/ai-image-challenge/knee-mri-ai-challenge ,
https://runtimewire.com/article/rsna-knee-mri-ai-challenge-2026 ,
https://github.com/homeshwarnelakurthi/RSNA-Knee-Abnormality-Detection

## Why this is the hardest of the three

Only 58 labeled studies means direct supervised training on expert labels is hopeless; the
signal is in the 4,349 reports. This is a **weak supervision / report-mining** problem first
and an imaging problem second. The multilingual reports must be turned into per-study pseudo
labels with a local open-weight model, and then an image model is trained on those pseudo
labels and calibrated on the 58 gold studies.

## Proposed pipeline

1. **Report → pseudo-labels (CPU/GPU notebook, one pass)**
   - Normalize reports: detect language (fastText lid), keep original text.
   - Zero-shot multilabel extraction with an open-weight multilingual instruct model
     (e.g. Qwen2.5-7B-Instruct or Gemma-2-9B in 4-bit on a T4), prompting per finding with
     a fixed rubric (present / absent / not mentioned). Store probabilities, not just labels.
   - Alternative cheap baseline: multilingual-E5 embeddings + logistic regression fit on the
     58 gold studies, plus keyword dictionaries per language for the most frequent findings
     (ACL tear, meniscal tear, cartilage defect, effusion, bone marrow edema, ...).
   - Validate the extractor on the 58 gold studies (macro AUC of text-only predictions).
     Text-only is likely already a strong leaderboard entry if the test set has reports; check
     the data page for whether reports are available at inference time.
2. **Imaging model**
   - Parse DICOM headers to identify planes (sagittal / coronal / axial) and sequences
     (PD-FS, T2-FS, T1). Resample each series to a fixed volume, e.g. 24 slices × 256².
   - Per-series 2.5D encoder (EfficientNet/ConvNeXt-tiny on slice triplets) with attention
     pooling over slices, one head per finding; fuse planes late (concat pooled features).
   - Train on pseudo-labels with soft targets (BCE on extractor probabilities), then fine-tune
     the heads on the 58 gold studies with heavy regularization; use 5-fold CV on gold for
     model selection only.
   - Mixed precision, gradient checkpointing; keep inference under the 9 h budget
     (≈ 1-2 s per study on a T4 is plenty).
3. **Fusion and calibration**: average text and image logits with weights chosen on the gold
   set; macro AUC is rank-based so per-label calibration is not required.
4. **Efficiency track**: report FLOPs/latency; a single 2.5D model with 256² inputs is a good
   candidate.

## Skeleton to create in the Kaggle notebook

```
rsna_knee/
  data/parse_dicom.py      # series discovery, plane/sequence tagging, resampling
  text/extract_labels.py   # multilingual zero-shot extraction to pseudo-labels
  train/train_25d.py       # per-series encoder with attention pooling, soft BCE
  infer/predict.py         # offline inference, writes submission.csv
```

## Local work possible without data

- Unit-test the DICOM parsing and resampling on public sample knee MRIs.
- Prototype the text extractor prompts on synthetic multilingual report snippets.
