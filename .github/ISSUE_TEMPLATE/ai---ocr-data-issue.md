---
name: AI / OCR Data Issue
about: Report incorrect text extraction or AI summarization errors
title: "[AI/OCR]"
labels: ai-model, data
assignees: ''

---

> **Privacy and security:** Do not attach real medical or personal data,
> prescription images, names, identifiers, credentials, or raw logs. Use only
> synthetic or fully redacted examples. Report vulnerabilities or real-data
> masking failures privately through the process in [SECURITY.md](../../SECURITY.md).

**Type of Issue (Check all that apply)**
- [ ] OCR Failed to read text correctly (e.g., Typo in drug name)
- [ ] AI Pharmacist generated incorrect/weird summary
- [ ] Drug was not found in the Public DB even though it exists
- [ ] Masking failed (Sensitive data was exposed)

**Input Data**
What synthetic or fully redacted input did you use? Do not paste text copied from a real prescription.
> e.g., "The OCR extracted '파모터' instead of '파모티딘'"

**Output Data**
What did the AI or the App return?
> e.g., "The app said 'Drug not found'."

**Expected Output**
What should have been the correct result?
> e.g., "It should have automatically corrected to '파모티딘' and showed the summary."

**Additional context**
Describe the synthetic image quality or a redacted error category. Do not paste API keys, authentication tokens, or raw service logs.
