---
name: AI / OCR Data Issue
about: Report incorrect text extraction or AI summarization errors
title: "[AI/OCR]"
labels: ai-model, data
assignees: ''

---

**Type of Issue (Check all that apply)**
- [ ] OCR Failed to read text correctly (e.g., Typo in drug name)
- [ ] AI Pharmacist generated incorrect/weird summary
- [ ] Drug was not found in the Public DB even though it exists
- [ ] Masking failed (Sensitive data was exposed)

**Input Data**
What did you input into the app? (Please provide the extracted text from the image, or the original drug name you tried to search).
> e.g., "The OCR extracted '파모터' instead of '파모티딘'"

**Output Data**
What did the AI or the App return?
> e.g., "The app said 'Drug not found'."

**Expected Output**
What should have been the correct result?
> e.g., "It should have automatically corrected to '파모티딘' and showed the summary."

**Additional context**
Add any other context, such as the quality of the image uploaded or specific Gemini API error logs if available.
