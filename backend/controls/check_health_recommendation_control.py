# File Name: check_health_recommendation_control.py
# Role: UML-compatible control wrapper for health recommendation requests.

from controls.request_health_recommendation_control import RequestHealthRecommendation


# Class Name: CheckHealthRecommendation
# Role: Routes health recommendation requests through the implemented backend control.
# Responsibilities:
#   - Preserve the UML/control class name used by the sequence and class diagrams.
#   - Delegate recommendation generation, scoping, and caching to RequestHealthRecommendation.
class CheckHealthRecommendation(RequestHealthRecommendation):
    # Function Name: requestHealthRecommendation
    # Description:
    # - Class diagram compatible wrapper for health recommendation lookup.
    # Parameters:
    # - patient_hash: Patient scope for recommendation lookup.
    # - user_hash: Optional guardian user hash.
    # - role: Requesting user role.
    # - language: Recommendation language code.
    # Returns:
    # - API-compatible health recommendation dictionary.
    async def requestHealthRecommendation(
        self,
        patient_hash: str,
        user_hash: str | None = None,
        role: str = "patient",
        language: str = "ko",
    ) -> dict[str, object]:
        return await self.request_health_recommendation(
            patient_hash,
            user_hash,
            role,
            language,
        )
