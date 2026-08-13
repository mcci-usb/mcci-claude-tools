#!/usr/bin/env python3
# /// script
# dependencies = ["extract-msg>=0.50"]
# ///
"""Dump an Outlook .msg file as JSON: headers, body, attachments, and any embedded message thread.

Output fields used downstream:
  body              -- full plain-text body, including any quoted thread.
  embedded_offset   -- byte offset into body of the first embedded message
                       header block (the From/Sent/To/Subject quartet),
                       or null if the body has no quoted thread.
  body_new          -- body[:embedded_offset].rstrip(), or full body if
                       embedded_offset is null. Convenience for callers
                       that want only the sender's new content (the typical
                       reply-trim case).
  embedded_messages -- list of parsed quoted-thread blocks (one per embed).
"""
import json
import re
import sys
from pathlib import Path

import extract_msg


def _safe(fn, default=None):
    try:
        return fn()
    except Exception:
        return default


def parse_recipients(s):
    if not s:
        return []
    parts = re.split(r"[;,]\s*", s.strip())
    out = []
    for p in parts:
        p = p.strip().strip("'\"")
        if not p:
            continue
        m = re.match(r"^(.*?)\s*<([^>]+)>\s*$", p)
        if m:
            out.append({"name": m.group(1).strip().strip("'\""), "email": m.group(2).strip()})
        elif "@" in p:
            out.append({"name": "", "email": p})
        else:
            out.append({"name": p, "email": ""})
    return out


HEADER_RE = re.compile(
    r"^From:\s*(?P<from>.+?)\s*$\n"
    r"(?:Sent:\s*(?P<sent>.+?)\s*$\n)?"
    r"To:\s*(?P<to>.+?)\s*$\n"
    r"(?:Cc:\s*(?P<cc>.+?)\s*$\n)?"
    r"(?:Bcc:\s*(?P<bcc>.+?)\s*$\n)?"
    r"Subject:\s*(?P<subject>.+?)\s*$",
    re.MULTILINE,
)


def split_thread(body):
    """Find every embedded message header block. Return (first_offset, segments).

    first_offset is the start byte offset of the first matched header block
    in `body`, or None if no embedded thread is present. segments is the
    parsed list of quoted-message blocks (one dict per embed).
    """
    matches = list(HEADER_RE.finditer(body))
    if not matches:
        return None, []
    first_offset = matches[0].start()
    segments = []
    for i, m in enumerate(matches):
        body_start = m.end()
        body_end = matches[i + 1].start() if i + 1 < len(matches) else len(body)
        segments.append({
            "from_raw": m.group("from"),
            "sent": (m.group("sent") or "").strip(),
            "to": m.group("to"),
            "cc": (m.group("cc") or ""),
            "bcc": (m.group("bcc") or ""),
            "subject": m.group("subject"),
            "body": body[body_start:body_end].strip(),
        })
    return first_offset, segments


def attachment_size(data):
    """Length of an attachment payload, in bytes.

    A message attached to a message arrives as an extract_msg Message, not as
    bytes, and has no len(). Its exported form gives a real size where the
    installed extract_msg offers one; otherwise report 0 rather than raising,
    because one such attachment used to abort a whole batch (#40).
    """
    if data is None:
        return 0
    if isinstance(data, (bytes, bytearray)):
        return len(data)
    export = getattr(data, "export", None)
    if callable(export):
        try:
            blob = export()
            if isinstance(blob, (bytes, bytearray)):
                return len(blob)
        except Exception:
            pass
    return 0


def attachment_name(a):
    """The attachment's filename, or one built from an attached message's
    subject. Outlook sets neither filename property on an attached .msg."""
    name = a.longFilename or a.shortFilename
    if name:
        return name
    subject = getattr(getattr(a, "data", None), "subject", None)
    if not subject:
        return None
    return re.sub(r'[\\/:*?"<>|]+', "_", subject).strip() + ".msg"


def dump_msg(path):
    import hashlib
    msg = extract_msg.Message(str(path))
    raw_msgid = getattr(msg, "messageId", None) or ""
    if not raw_msgid and msg.header:
        raw_msgid = msg.header.get("Message-ID") or msg.header.get("Message-Id") or ""
    msg_id = raw_msgid.strip().strip("<>")
    msg_id_source = "messageId" if getattr(msg, "messageId", None) else ("header" if raw_msgid else "")
    if not msg_id:
        # Stable hash fallback for drafts where Message-Id was never assigned.
        seed = f"{msg.subject}|{msg.date}|{msg.sender}|{path.name}"
        msg_id = "draft-" + hashlib.sha1(seed.encode("utf-8", "replace")).hexdigest()[:16]
        msg_id_source = "fallback-hash"

    body = msg.body or ""
    embedded_offset, embedded_messages = split_thread(body)
    if embedded_offset is not None:
        body_new = body[:embedded_offset].rstrip()
    else:
        body_new = body

    out = {
        "path": str(path),
        "message_id": msg_id,
        "message_id_source": msg_id_source,
        "in_reply_to": (getattr(msg, "inReplyTo", "") or "").strip().strip("<>") or None,
        "subject": msg.subject,
        "sender_name": msg.sender,
        "from_raw": (msg.header.get("From") if msg.header else None) or msg.sender,
        "from_email": (lambda h: (re.search(r"<([^>]+)>", h or "") or [None, None])[1] if h else None)(msg.header.get("From") if msg.header else "") or msg.sender,
        "sent_date": msg.date.isoformat() if msg.date else None,
        "to": msg.to,
        "cc": msg.cc,
        "bcc": msg.bcc,
        "to_parsed": parse_recipients(msg.to),
        "cc_parsed": parse_recipients(msg.cc),
        "bcc_parsed": parse_recipients(msg.bcc),
        "headers": dict(msg.header) if msg.header else {},
        "body": body,
        "embedded_offset": embedded_offset,
        "body_new": body_new,
        "html_present": _safe(lambda: bool(msg.htmlBody)),
        "rtf_present": _safe(lambda: bool(msg.rtfBody)),
        "attachments": [
            {
                "filename": attachment_name(a),
                "size": attachment_size(a.data),
                "mime": getattr(a, "mimetype", None),
                "embedded": not isinstance(a.data, (bytes, bytearray)) and a.data is not None,
            }
            for a in msg.attachments
        ],
        "embedded_messages": embedded_messages,
    }
    return out


if __name__ == "__main__":
    args = sys.argv[1:]
    out_dir = None
    paths = []
    i = 0
    while i < len(args):
        if args[i] in ("-o", "--out") and i + 1 < len(args):
            out_dir = Path(args[i + 1])
            i += 2
        else:
            paths.append(args[i])
            i += 1
    if out_dir:
        out_dir.mkdir(parents=True, exist_ok=True)
    for p in paths:
        d = dump_msg(Path(p))
        if out_dir:
            mid = d.get("message_id") or Path(p).stem
            safe = re.sub(r"[^A-Za-z0-9._@-]", "_", mid)[:200] or Path(p).stem
            target = out_dir / f"{safe}.json"
            target.write_text(json.dumps(d, indent=2, default=str))
            print(f"wrote {target}")
        else:
            print(json.dumps(d, indent=2, default=str))
            print("\n---FILE-BOUNDARY---\n")
