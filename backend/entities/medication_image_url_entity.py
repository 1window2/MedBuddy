# File Name: medication_image_url_entity.py
# Role: Defines the backend trust policy for remotely loaded medication images.

from urllib.parse import urlsplit


TRUSTED_MEDICATION_IMAGE_HOSTS = frozenset({"nedrug.mfds.go.kr"})
MAX_MEDICATION_IMAGE_URL_LENGTH = 2_048


# Function Name: safe_medication_image_url
# Description:
# - Normalizes a public medication image URL and returns it only when it uses
#   HTTPS on the documented MFDS image host.
# - Rejects credentials, alternate ports, local endpoints, and arbitrary
#   third-party tracking hosts before the value is stored or returned.
# Parameters:
# - value: Untrusted URL value received from a client, catalog, or database.
# Returns:
# - The trusted normalized URL, or an empty string when validation fails.
def safe_medication_image_url(value: object) -> str:
    text = str(value).strip() if value is not None else ""
    if text.startswith("//"):
        text = f"https:{text}"
    if not text or len(text) > MAX_MEDICATION_IMAGE_URL_LENGTH:
        return ""

    try:
        parsed_url = urlsplit(text)
        hostname = (parsed_url.hostname or "").rstrip(".").casefold()
        port = parsed_url.port
    except ValueError:
        return ""

    if (
        parsed_url.scheme.casefold() != "https"
        or not hostname
        or parsed_url.username is not None
        or parsed_url.password is not None
        or (port is not None and port != 443)
        or hostname not in TRUSTED_MEDICATION_IMAGE_HOSTS
    ):
        return ""
    return text
