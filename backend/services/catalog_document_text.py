# File Name: catalog_document_text.py
# Role: Extracts bounded readable catalog text without resolving document links or entities.

from html.parser import HTMLParser
from xml.parsers import expat

MAX_DOCUMENT_CHARACTERS = 256_000
MAX_DOCUMENT_ELEMENTS = 10_000
MAX_DOCUMENT_DEPTH = 64

_BLOCKS = frozenset({
    "DOC", "SECTION", "ARTICLE", "PARAGRAPH", "P", "DIV", "LI", "UL", "OL",
    "TABLE", "TR", "H1", "H2", "H3", "H4", "H5", "H6", "BLOCKQUOTE",
})
_HTML_TAGS = frozenset({
    "HTML", "BODY", "P", "DIV", "SPAN", "BR", "B", "I", "U", "EM", "STRONG",
    "SUP", "SUB", "UL", "OL", "LI", "TABLE", "THEAD", "TBODY", "TFOOT", "TR",
    "TD", "TH", "H1", "H2", "H3", "H4", "H5", "H6", "BLOCKQUOTE", "A",
})
_LOCATOR_PREFIXES = ("http://", "https://", "ftp://", "file:", "data:", "javascript:", "//", "www.")


class _InvalidDocument(ValueError):
    pass


class _Text:
    def __init__(self) -> None:
        self.parts: list[str] = []
        self.size = 0

    def append(self, value: str) -> None:
        self.size += len(value)
        if self.size > MAX_DOCUMENT_CHARACTERS:
            raise _InvalidDocument("Document text is too large")
        self.parts.append(value)

    def boundary(self, tag: str) -> None:
        if tag in _BLOCKS:
            self.append("\n\n")
        elif tag == "BR":
            self.append("\n")
        elif tag in {"TD", "TH"}:
            self.append("\t")

    def text(self) -> str:
        return "".join(self.parts)


class _HTMLText(HTMLParser):
    """Handles embedded CDATA HTML and plain HTML fragments; never loads resources."""

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.output = _Text()
        self.elements = 0
        self.depth = 0

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        tag = tag.upper()
        self.elements += 1
        if tag not in _HTML_TAGS or self.elements > MAX_DOCUMENT_ELEMENTS:
            raise _InvalidDocument("Unsupported HTML element")
        if tag != "BR":
            self.depth += 1
        if self.depth > MAX_DOCUMENT_DEPTH:
            raise _InvalidDocument("HTML is too deep")
        self.output.boundary(tag)

    def handle_endtag(self, tag: str) -> None:
        if tag.upper() not in _HTML_TAGS:
            raise _InvalidDocument("Unsupported HTML element")
        if tag.upper() != "BR":
            self.depth = max(0, self.depth - 1)
        self.output.boundary(tag.upper())

    def handle_data(self, data: str) -> None:
        self.output.append(data)

    def handle_decl(self, decl: str) -> None:
        raise _InvalidDocument("Document declarations are not allowed")

    def unknown_decl(self, data: str) -> None:
        raise _InvalidDocument("Document declarations are not allowed")

    def handle_pi(self, data: str) -> None:
        raise _InvalidDocument("Processing instructions are not allowed")


def _xml_text(document: str) -> str:
    output = _Text()
    depth = 0
    elements = 0
    parser = expat.ParserCreate(namespace_separator="}")

    def start(name: str, attributes: dict[str, str]) -> None:
        nonlocal depth, elements
        depth += 1
        elements += 1
        tag = name.rsplit("}", 1)[-1].upper()
        if depth > MAX_DOCUMENT_DEPTH or elements > MAX_DOCUMENT_ELEMENTS:
            raise _InvalidDocument("XML structure exceeds limits")
        if tag in {"SCRIPT", "STYLE"}:
            raise _InvalidDocument("Executable document content")
        output.boundary(tag)
        if tag in {"SECTION", "ARTICLE"}:
            title = attributes.get("title", attributes.get("TITLE", "")).strip()
            if title:
                output.append(title)
                output.append("\n\n")

    def end(name: str) -> None:
        nonlocal depth
        output.boundary(name.rsplit("}", 1)[-1].upper())
        depth -= 1

    def reject_declaration(*args: object) -> None:
        raise _InvalidDocument("DTD, entities and processing instructions are not allowed")

    parser.StartElementHandler = start
    parser.EndElementHandler = end
    parser.CharacterDataHandler = output.append
    parser.StartDoctypeDeclHandler = reject_declaration
    parser.EntityDeclHandler = reject_declaration
    parser.ExternalEntityRefHandler = reject_declaration
    parser.ProcessingInstructionHandler = reject_declaration
    parser.Parse(document, True)
    return output.text()


def read_catalog_document(value: str | None) -> str:
    """Return source text only, or empty for missing/unsafe/unreadable documents.

    XML titles and paragraphs retain source order. CDATA HTML is parsed structurally,
    not stripped with a regex. Oversize documents are rejected, never truncated mid-warning.
    """
    if not isinstance(value, str) or len(value) > MAX_DOCUMENT_CHARACTERS:
        return ""
    document = value.strip()
    if not document or document.lower().startswith(_LOCATOR_PREFIXES):
        return ""
    try:
        if document.startswith("<"):
            try:
                document = _xml_text(document)
            except expat.ExpatError:
                # HTML fragments can have multiple roots, <br> and named HTML entities.
                # Unknown XML tags and declarations still fail closed in the HTML parser.
                pass
        if "<" in document or "&" in document:
            parser = _HTMLText()
            parser.feed(document)
            # Some Python patch releases discard unfinished end tags on close.
            # Reject pending markup before that recovery can hide a broken source.
            if "<" in parser.rawdata:
                raise _InvalidDocument("Incomplete HTML element")
            parser.close()
            document = parser.output.text()
        lines: list[str] = []
        for line in document.splitlines():
            line = " ".join(line.split())
            if line or (lines and lines[-1]):
                lines.append(line)
        result = "\n".join(lines).strip()
        # Incomplete/escaped tags can arrive in separate HTML data callbacks. Inspect
        # the assembled text; numeric comparisons such as "< 5" remain source text.
        if any(
            part[:1].isalpha() or part.startswith(("/", "!", "?"))
            for part in result.split("<")[1:]
        ):
            return ""
        if result.lower().startswith(_LOCATOR_PREFIXES):
            return ""
        return result
    except (_InvalidDocument, expat.ExpatError, ValueError):
        return ""
