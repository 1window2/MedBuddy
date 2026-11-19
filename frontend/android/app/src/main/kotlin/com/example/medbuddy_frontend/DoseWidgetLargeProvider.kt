// File Name: DoseWidgetLargeProvider.kt
// Role: Exposes the 4x3 launcher entry while sharing state and validated actions with 4x1.
package com.example.medbuddy_frontend

// Class Name: DoseWidgetLargeProvider
// Responsibilities: Retain a distinct launcher identity; delegate all lifecycle and action handling.
// Attributes: None. Per-instance selections remain keyed by Android widget ID in the base provider.
class DoseWidgetLargeProvider : DoseWidgetProvider()
