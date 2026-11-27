"""Galla WhatsApp bill delivery - reference rules (plan Section 23). Pure functions."""
import re
from urllib.parse import quote
import phonenumbers
from phonenumbers import PhoneNumberFormat, PhoneNumberType

E164 = re.compile(r"^\+[1-9][0-9]{6,14}$")

def normalize_phone(raw, default_region):
    """Returns (e164 | None, warning | None). Never guesses: invalid -> (None, 'INVALID_PHONE_NUMBER')."""
    try:
        n = phonenumbers.parse(raw, None if raw.strip().startswith("+") else default_region)
    except phonenumbers.NumberParseException:
        return None, "INVALID_PHONE_NUMBER"
    if not phonenumbers.is_valid_number(n):
        return None, "INVALID_PHONE_NUMBER"
    e164 = phonenumbers.format_number(n, PhoneNumberFormat.E164)
    if not E164.match(e164): return None, "INVALID_PHONE_NUMBER"
    t = phonenumbers.number_type(n)
    warn = None if t in (PhoneNumberType.MOBILE, PhoneNumberType.FIXED_LINE_OR_MOBILE) else "NOT_A_MOBILE_NUMBER"
    return e164, warn

def wa_me_url(e164, text):
    """Click-to-chat link: digits only (no '+'), message URL-encoded."""
    return f"https://wa.me/{e164.lstrip('+')}?text={quote(text, safe='')}"

def clean_param(value, max_len=40, fallback="Guest"):
    """Template variables: no newlines/tabs, collapse runs of spaces (defensive - Meta rejects such values), trim, truncate."""
    v = re.sub(r"[\r\n\t]+", " ", value or "")
    v = re.sub(r" {2,}", " ", v).strip()
    v = v[:max_len].rstrip()
    return v or fallback

def bill_template_params(customer_name, outlet_name, bill_number, currency_symbol, grand_total):
    return [clean_param(customer_name), clean_param(outlet_name, 60, "Restaurant"), clean_param(bill_number, 40, "-"),
            f"{currency_symbol} {grand_total}"]

# ---- consent: append-only history, newest row wins
def current_consent(history, phone, purpose):
    rows = [h for h in history if h["phone"] == phone and h["purpose"] == purpose]
    if not rows: return "NONE"
    return max(rows, key=lambda h: (h["at"], h["seq"]))["status"]
def may_send(history, phone, purpose): return current_consent(history, phone, purpose) == "OPTED_IN"
STOP_WORDS = {"stop", "unsubscribe", "cancel", "opt out", "optout"}
def is_stop_message(text): return re.sub(r"[^a-z ]", "", (text or "").lower()).strip() in STOP_WORDS

# ---- delivery status merge (webhooks can arrive out of order or twice)
RANK = {"QUEUED": 0, "SENT": 1, "DELIVERED": 2, "READ": 3}
def merge_status(current, incoming):
    if current == "FAILED":
        return "FAILED" if incoming == "FAILED" else (incoming if RANK.get(incoming, -1) >= RANK["DELIVERED"] else "FAILED")   # a later delivered/read proves delivery
    if incoming == "FAILED":
        return current if RANK[current] >= RANK["DELIVERED"] else "FAILED"      # never downgrade a delivered message
    return incoming if RANK[incoming] > RANK[current] else current

# ---- failure classification (codes from published error lists; 131026 is deliberately ambiguous)
def classify_failure(code):
    c = str(code)
    if c == "131026": return dict(kind="UNDELIVERABLE", retry=False, ui="NOT_ON_WHATSAPP_OR_BLOCKED", alert_admin=False)
    if c == "130429": return dict(kind="RATE_LIMIT", retry=True, ui="TEMPORARY", alert_admin=False)
    if c in ("132001", "132000"): return dict(kind="TEMPLATE_CONFIG", retry=False, ui="TEMPLATE_PROBLEM", alert_admin=True)
    if c == "131048": return dict(kind="ACCOUNT_RESTRICTED", retry=False, ui="ACCOUNT_RESTRICTED", alert_admin=True)
    if c == "131047": return dict(kind="WINDOW_CLOSED", retry=False, ui="TEMPLATE_PROBLEM", alert_admin=True)   # means we sent free text outside the window: a bug
    return dict(kind="UNKNOWN", retry=True, ui="TEMPORARY", alert_admin=False)
MAX_ATTEMPTS = 3

# ---- daily unique-recipient budget (rolling 24h) - warn before the account's messaging limit
def unique_recipients_24h(messages, now_s):
    return len({m["to"] for m in messages if now_s - 86400 < m["at"] <= now_s and m["status"] != "FAILED"})
def limit_state(used, limit, warn_ratio=0.8):
    if limit is None: return "UNKNOWN"
    if used >= limit: return "AT_LIMIT"
    return "WARN" if used >= limit * warn_ratio else "OK"
TIERS = {"TIER_250": 250, "TIER_2K": 2000, "TIER_10K": 10000, "TIER_100K": 100000, "TIER_UNLIMITED": None}

# ---- resend control
def can_resend(sent_count_for_bill_phone, max_sends=5): return sent_count_for_bill_phone < max_sends
