"""Delivery charge rules (plan Section 20). Pure, Decimal only."""
from decimal import Decimal as D, ROUND_HALF_UP
from math import radians, sin, cos, asin, sqrt
R_KM = 6371.0
def haversine_km(lat1, lon1, lat2, lon2):
    p1, p2 = radians(lat1), radians(lat2); dphi = p2 - p1; dl = radians(lon2 - lon1)
    a = sin(dphi/2)**2 + cos(p1)*cos(p2)*sin(dl/2)**2
    return 2 * R_KM * asin(sqrt(a))
def distance_km(o_lat, o_lng, d_lat, d_lng, factor=D("1.00")):
    raw = D(repr(haversine_km(o_lat, o_lng, d_lat, d_lng))) * factor
    return raw.quantize(D("0.01"), ROUND_HALF_UP)
class ChargeError(Exception): pass
def delivery_charge(mode, *, distance=None, subtotal_after_discount=D("0"), flat=D("0"), slabs=(),
                    free_above=None, max_radius=None, override=None):
    """slabs: [(from_km, to_km, charge)] meaning from < d <= to. override: Decimal charge set by a manager (needs reason+PIN upstream)."""
    if override is not None:
        if override < 0: raise ChargeError("VALIDATION_ERROR")
        return override
    if mode == "NONE": return D("0.00")
    if max_radius is not None and distance is not None and distance > max_radius: raise ChargeError("OUT_OF_DELIVERY_RANGE")
    if free_above is not None and subtotal_after_discount >= free_above: return D("0.00")
    if mode == "FLAT": return flat
    if mode == "DISTANCE_SLABS":
        if distance is None: raise ChargeError("DELIVERY_DISTANCE_UNKNOWN")
        for lo, hi, ch in slabs:
            if lo < distance <= hi: return ch
        raise ChargeError("OUT_OF_DELIVERY_RANGE")
    raise ChargeError("VALIDATION_ERROR")
