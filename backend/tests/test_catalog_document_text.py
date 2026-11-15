# File Name: test_catalog_document_text.py
# Role: Verifies deterministic, bounded rendering of approval source documents.

import pytest

from services.catalog_document_text import (
    MAX_DOCUMENT_CHARACTERS,
    MAX_DOCUMENT_DEPTH,
    MAX_DOCUMENT_ELEMENTS,
    read_catalog_document,
)


def test_structured_approval_xml_preserves_titles_paragraphs_cdata_and_order() -> None:
    # Representative MFDS-shaped source, not a sample from the empty local catalog.
    document = '''<?xml version="1.0" encoding="UTF-8"?>
<DOC title="Usage" type="UD">
  <SECTION title="Administration">
    <ARTICLE title="1. First group">
      <PARAGRAPH tagName="p" textIndent="0" marginLeft="0"><![CDATA[First paragraph.]]></PARAGRAPH>
      <PARAGRAPH tagName="p"><![CDATA[Second <b>important</b> paragraph.<br>Next line.]]></PARAGRAPH>
    </ARTICLE>
    <ARTICLE title="2. Second group"><PARAGRAPH>Preserve &amp; compare &lt; 5.</PARAGRAPH></ARTICLE>
  </SECTION>
</DOC>'''
    assert read_catalog_document(document) == (
        "Administration\n\n1. First group\n\nFirst paragraph.\n\n"
        "Second important paragraph.\nNext line.\n\n2. Second group\n\nPreserve & compare < 5."
    )


def test_html_fragments_and_tables_keep_separate_text() -> None:
    assert read_catalog_document("<p>First&nbsp;paragraph.</p><p>Second<br>line.</p>") == (
        "First paragraph.\n\nSecond\nline."
    )
    assert read_catalog_document("<table><tr><th>Group</th><th>Amount</th></tr>"
                                 "<tr><td>A</td><td>Source amount</td></tr></table>") == (
        "Group Amount\n\nA Source amount"
    )


@pytest.mark.parametrize("document", [
    None, "", " ", "https://nedrug.mfds.go.kr/doc.pdf", "//example.com/doc",
    "file:///private/document", "data:text/plain,Not guidance", "javascript:alert(1)",
    '<DOC><PARAGRAPH>https://nedrug.mfds.go.kr/doc.pdf</PARAGRAPH></DOC>',
    '<a href="https://example.com/doc">https://example.com/doc</a>',
    '<DOC><ARTICLE>Broken XML', '<DOC>&unknown;</DOC>', '<DOC', '<p>Text</broken',
    '<p>Text</p></broken', '<p>Text</p><broken', '<p>Text</p><',
    '<DOC><![CDATA[<p>Text</broken]]></DOC>',
    '&lt;DOC&gt;&lt;PARAGRAPH&gt;Unrendered&lt;/PARAGRAPH&gt;&lt;/DOC&gt;',
    '<!DOCTYPE DOC [<!ENTITY x "expanded">]><DOC>&x;</DOC>',
    '<!DOCTYPE DOC SYSTEM "https://example.com/remote.dtd"><DOC>Text</DOC>',
    '<!DOCTYPE DOC [<!ENTITY x SYSTEM "file:///private/file">]><DOC>&x;</DOC>',
    '<!DOCTYPE html><p>Text</p>', '<script>Hidden content</script>',
    '<DOC><![CDATA[<script>Hidden content</script>]]></DOC>',
    '<DOC><?remote https://example.com?><PARAGRAPH>Text</PARAGRAPH></DOC>',
])
def test_unusable_documents_fail_closed_without_returning_markup_or_links(document: str | None) -> None:
    assert read_catalog_document(document) == ""


@pytest.mark.parametrize("document", [
    "x" * (MAX_DOCUMENT_CHARACTERS + 1),
    "<DOC>" + "<P>" * MAX_DOCUMENT_DEPTH + "text" + "</P>" * MAX_DOCUMENT_DEPTH + "</DOC>",
    "<DOC>" + "<P/>" * MAX_DOCUMENT_ELEMENTS + "</DOC>",
], ids=["character-limit", "depth-limit", "element-limit"])
def test_limits_reject_whole_document_instead_of_truncating_warnings(document: str) -> None:
    assert read_catalog_document(document) == ""


def test_plain_text_and_inline_comparisons_are_not_rewritten() -> None:
    assert read_catalog_document("First source line.\n\nSecond source line.") == (
        "First source line.\n\nSecond source line."
    )
    assert read_catalog_document("Source says < 5 and > 1.") == "Source says < 5 and > 1."
