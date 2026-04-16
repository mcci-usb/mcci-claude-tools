# /// script
# requires-python = ">=3.10"
# dependencies = [
#     "markdown-it-py[plugins,linkify]",
#     "premailer",
# ]
# ///
# ORIGINAL SOURCE -- install to ~/.claude/scripts/ using install.sh
"""Convert Markdown to inline-styled HTML suitable for Outlook email.

Usage:
    uv run md-to-email-html.py INPUT.md > output.html
    uv run md-to-email-html.py - < input.md > output.html

Uses markdown-it-py (same engine as VS Code markdown preview) for
conversion, then premailer to inline all CSS for Outlook compatibility.
"""

import sys
import copy
import re
from markdown_it import MarkdownIt
from mdit_py_plugins.front_matter import front_matter_plugin
from mdit_py_plugins.footnote import footnote_plugin
from premailer import transform
from lxml import etree

CSS_TEMPLATE = """\
body {
    font-size: 11pt;
    color: #000000;
    margin: 0;
    padding: 0;
}
p {
    margin: 0 0 10px 0;
}
h1 {
    font-size: 16pt;
    font-weight: bold;
    margin: 0 0 10px 0;
}
h2 {
    font-size: 14pt;
    font-weight: bold;
    margin: 0 0 8px 0;
}
h3 {
    font-size: 12pt;
    font-weight: bold;
    margin: 0 0 6px 0;
}
ul, ol {
    margin: 0 0 10px 0;
    padding-left: 24px;
}
li {
    margin: 0 0 4px 0;
}
pre {
    font-family: Consolas, monospace;
    font-size: 10pt;
    background-color: #f5f5f5;
    padding: 8px 12px;
    border: 1px solid #e0e0e0;
    white-space: pre;
    margin: 0 0 10px 0;
}
code {
    font-family: Consolas, monospace;
    font-size: 10pt;
    background-color: #f0f0f0;
    padding: 1px 4px;
}
pre code {
    background-color: transparent;
    padding: 0;
}
blockquote {
    border-left: 3px solid #cccccc;
    padding-left: 12px;
    margin: 0 0 10px 0;
    color: #555555;
}
table {
    border-collapse: collapse;
    margin: 0 0 10px 0;
}
th, td {
    border: 1px solid #cccccc;
    padding: 4px 8px;
}
th {
    background-color: #f0f0f0;
    font-weight: bold;
}
a {
    color: #0563C1;
}
hr {
    border: none;
    border-top: 1px solid #cccccc;
    margin: 10px 0;
}
"""

HTML_TEMPLATE = """\
<html>
<head><style>{css}</style></head>
<body>
{body}
</body>
</html>
"""


def _pre_to_code_paragraphs(pre_elem, code_style, margin_left=None):
    """Convert a <pre><code> element to a list of <p><code> elements.

    Outlook/Word doesn't handle <pre> well (especially inside lists).
    Word's own HTML represents code blocks as <p><code> per line with
    explicit margin and font styling.  This function does the same.

    Returns a list of etree Elements (<p> tags, including spacers).
    """
    # Extract text content from <pre><code> or <pre>
    code_elem = pre_elem.find("code")
    if code_elem is not None:
        text = code_elem.text or ""
    else:
        text = pre_elem.text or ""

    lines = text.split("\n")
    # Remove trailing empty line (common from markdown rendering)
    if lines and lines[-1].strip() == "":
        lines = lines[:-1]

    p_style = code_style
    if margin_left:
        p_style += f" margin-left:{margin_left};"

    result = []

    for line in lines:
        p = etree.Element("p")
        p.set("style", p_style)
        code = etree.SubElement(p, "code")
        code.text = line if line else " "
        result.append(p)

    # Add bottom margin to last element for spacing after code block
    if result:
        last_style = result[-1].get("style", "")
        result[-1].set("style", last_style + " margin-bottom:10px;")

    return result


def _fix_for_outlook(html: str) -> str:
    """Fix HTML quirks for Outlook's Word-based rendering engine.

    Outlook (Word's HTML engine) has several issues:
    1. <pre> rendering is broken (especially inside lists).
    2. Container margins on <ul>/<ol> are ignored; only <li> margins
       are honored.  This causes uneven spacing around lists because
       the last <li>'s margin-bottom (small, for inter-item spacing)
       becomes the gap after the list, while the gap before the list
       comes from the preceding <p>'s margin-bottom (larger).

    Fixes applied:
    - <pre> inside <li>: extract, split list with start= attributes,
      convert to <p><code> with margin-left matching list indent.
    - <pre> outside lists: convert to <p><code>.
    - Last <li> in each list: set margin-bottom to match <p> spacing
      (10px) so the gap after the list equals the gap before it.
    """
    CODE_STYLE = "font-family:Consolas, monospace; font-size:10pt; background-color:#f5f5f5; margin:0;"
    LIST_INDENT = ".5in"
    # Must match the <p> margin-bottom so list-to-paragraph spacing is even.
    PARAGRAPH_MARGIN_BOTTOM = "10px"

    parser = etree.HTMLParser()
    tree = etree.fromstring(html, parser)

    # --- Fix last <li> margin in each list ---
    # Outlook ignores <ul>/<ol> container margins and only uses <li>
    # margins.  Set the last <li>'s margin-bottom to match <p> spacing.
    # Use both standard margin-bottom AND mso-margin-bottom-alt for
    # Outlook/Word compatibility (Word's engine reads the mso- property
    # for <ol> lists even when it ignores standard margin-bottom).
    for list_tag in tree.iter("ol", "ul"):
        li_items = [child for child in list_tag if child.tag == "li"]
        if not li_items:
            continue
        last_li = li_items[-1]
        style = last_li.get("style", "")
        # Replace existing margin-bottom or append it
        if "margin-bottom" in style:
            style = re.sub(
                r"margin-bottom:\s*[^;]+",
                f"margin-bottom:{PARAGRAPH_MARGIN_BOTTOM}",
                style,
            )
        elif "margin:" in style:
            # Replace the full margin shorthand's bottom value
            # margin: T R B L -> margin: T R newB L
            style = re.sub(
                r"margin:\s*(\S+)\s+(\S+)\s+\S+\s+(\S+)",
                rf"margin:\1 \2 {PARAGRAPH_MARGIN_BOTTOM} \3",
                style,
            )
        else:
            style = style.rstrip("; ") + f"; margin-bottom:{PARAGRAPH_MARGIN_BOTTOM};"
        # Add MSO-specific margin property for Outlook/Word engine
        if "mso-margin-bottom-alt" not in style:
            style = style.rstrip("; ") + f"; mso-margin-bottom-alt:{PARAGRAPH_MARGIN_BOTTOM};"
        last_li.set("style", style)

    # --- Handle <pre> inside list items ---
    for list_tag in tree.iter("ol", "ul"):
        items = list(list_tag)
        if not any(
            li.tag == "li" and li.find(".//pre") is not None
            for li in items
        ):
            continue

        parent = list_tag.getparent()
        if parent is None:
            continue

        list_attrib = dict(list_tag.attrib)
        tag_name = list_tag.tag
        start_num = int(list_attrib.get("start", "1"))

        fragments = []
        current_items = []
        current_start = start_num
        item_count = 0

        for li in items:
            if li.tag != "li":
                continue

            pre_elem = li.find(".//pre")
            if pre_elem is None:
                current_items.append(copy.deepcopy(li))
                item_count += 1
            else:
                # Strip <pre> from <li>, keep the text portion
                li_copy = copy.deepcopy(li)
                for pre_in_copy in li_copy.findall(".//pre"):
                    pre_parent = pre_in_copy.getparent()
                    if pre_parent is not None:
                        prev = pre_in_copy.getprevious()
                        if prev is not None:
                            prev.tail = (prev.tail or "") + (pre_in_copy.tail or "")
                        else:
                            pre_parent.text = (pre_parent.text or "") + (pre_in_copy.tail or "")
                        pre_parent.remove(pre_in_copy)

                has_text = (li_copy.text and li_copy.text.strip()) or len(li_copy) > 0
                if has_text:
                    current_items.append(li_copy)
                    item_count += 1

                # Flush current list segment
                if current_items:
                    new_list = etree.Element(tag_name)
                    for attr_name, attr_val in list_attrib.items():
                        if attr_name != "start":
                            new_list.set(attr_name, attr_val)
                    if tag_name == "ol" and current_start != 1:
                        new_list.set("start", str(current_start))
                    for item in current_items:
                        new_list.append(item)
                    fragments.append(new_list)
                    current_items = []

                # Convert <pre> to <p><code> elements
                for pre_in_li in li.findall(".//pre"):
                    code_paras = _pre_to_code_paragraphs(
                        pre_in_li, CODE_STYLE, margin_left=LIST_INDENT
                    )
                    fragments.extend(code_paras)

                current_start = start_num + item_count

        # Flush remaining items
        if current_items:
            new_list = etree.Element(tag_name)
            for attr_name, attr_val in list_attrib.items():
                if attr_name != "start":
                    new_list.set(attr_name, attr_val)
            if tag_name == "ol" and current_start != 1:
                new_list.set("start", str(current_start))
            for item in current_items:
                new_list.append(item)
            fragments.append(new_list)

        # Replace original list with fragments
        for i, frag in enumerate(fragments):
            if i == 0:
                parent.replace(list_tag, frag)
            else:
                prev_idx = list(parent).index(fragments[i - 1])
                parent.insert(prev_idx + 1, frag)

    # --- Handle <pre> outside lists (top-level) ---
    for pre in list(tree.iter("pre")):
        parent = pre.getparent()
        if parent is None:
            continue
        # Skip if inside a list item (already handled above)
        in_list = False
        p = parent
        while p is not None:
            if p.tag in ("li", "ol", "ul"):
                in_list = True
                break
            p = p.getparent()
        if in_list:
            continue

        code_paras = _pre_to_code_paragraphs(pre, CODE_STYLE)
        idx = list(parent).index(pre)
        for i, cp in enumerate(code_paras):
            parent.insert(idx + i, cp)
        parent.remove(pre)

    result = etree.tostring(tree, encoding="unicode", method="html")
    return result


def convert(markdown_text: str) -> str:
    """Convert markdown to inline-styled HTML."""
    md = MarkdownIt("commonmark", {"typographer": True, "linkify": True})
    md.enable("linkify")
    md.enable(["table", "strikethrough"])
    front_matter_plugin(md)
    footnote_plugin(md)

    html_body = md.render(markdown_text)

    full_html = HTML_TEMPLATE.format(css=CSS_TEMPLATE, body=html_body)

    # Inline all CSS for Outlook compatibility
    result = transform(
        full_html,
        keep_style_tags=False,
        strip_important=True,
    )

    # Fix Outlook rendering quirks (<pre> blocks, list spacing)
    result = _fix_for_outlook(result)

    return result


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    if len(sys.argv) < 2 or sys.argv[1] == "-":
        sys.stdin.reconfigure(encoding="utf-8")
        markdown_text = sys.stdin.read()
    else:
        with open(sys.argv[1], encoding="utf-8") as f:
            markdown_text = f.read()

    result = convert(markdown_text)
    sys.stdout.write(result)


if __name__ == "__main__":
    main()
