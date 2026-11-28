package app.galla.subscription;
import java.math.BigDecimal;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.util.regex.Pattern;
/** Builds a standard UPI payment link (upi://pay) that any UPI app opens when the QR is scanned. The amount is pre-filled. */
public final class UpiLink {
  private UpiLink() {}
  public static final Pattern VPA = Pattern.compile("^[A-Za-z0-9._-]{2,256}@[A-Za-z][A-Za-z0-9]{1,63}$");
  private static String enc(String s) { return URLEncoder.encode(s, StandardCharsets.UTF_8).replace("+", "%20"); }
  public static String build(String vpa, String payeeName, BigDecimal amount, String note) {
    if (!VPA.matcher(vpa).matches()) throw new IllegalArgumentException("invalid UPI id");
    return "upi://pay?pa=" + enc(vpa) + "&pn=" + enc(payeeName) + "&am=" + amount.setScale(2, java.math.RoundingMode.HALF_UP).toPlainString() + "&cu=INR&tn=" + enc(note);
  }
}
