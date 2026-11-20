import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.security.MessageDigest;
import java.util.zip.Deflater;
import javax.crypto.Cipher;
import javax.crypto.Mac;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.SecretKeySpec;

/**
 * Minimal standalone JDK helper for E2E tests: encrypts a plaintext SQLite DB into a
 * spec-compliant WhatsApp `.crypt15` file (protobuf varint + BackupPrefix/C15IV +
 * AES-256-GCM(zlib(sqlite)) + 16-byte MD5 footer).
 */
public class e2e_make_crypt15 {

    private static byte[] hexToBytes(String hex) {
        byte[] out = new byte[hex.length() / 2];
        for (int i = 0; i < out.length; i++) {
            out[i] = (byte) Integer.parseInt(hex.substring(i * 2, i * 2 + 2), 16);
        }
        return out;
    }

    private static byte[] hmacSha256(byte[] key, byte[] data) throws Exception {
        Mac mac = Mac.getInstance("HmacSHA256");
        mac.init(new SecretKeySpec(key, "HmacSHA256"));
        return mac.doFinal(data);
    }

    private static byte[] deriveAesKey(String hexKey64) throws Exception {
        byte[] rootKey = hexToBytes(hexKey64);
        byte[] privateKey = hmacSha256(new byte[32], rootKey);
        byte[] label = "backup encryption".getBytes(StandardCharsets.UTF_8);
        byte[] msg = new byte[label.length + 1];
        System.arraycopy(label, 0, msg, 0, label.length);
        msg[label.length] = 0x01;
        return hmacSha256(privateKey, msg);
    }

    private static byte[] writeVarint(int value) {
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        int v = value;
        while ((v & ~0x7F) != 0) {
            out.write((v & 0x7F) | 0x80);
            v >>>= 7;
        }
        out.write(v);
        return out.toByteArray();
    }

    private static byte[] zlibCompress(byte[] input) {
        Deflater deflater = new Deflater();
        deflater.setInput(input);
        deflater.finish();
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        byte[] buf = new byte[8192];
        while (!deflater.finished()) {
            int n = deflater.deflate(buf);
            if (n > 0) out.write(buf, 0, n);
        }
        deflater.end();
        return out.toByteArray();
    }

    public static void main(String[] args) throws Exception {
        if (args.length != 3) {
            System.err.println("Usage: java e2e_make_crypt15.java <sqlite_in> <hex_key_64> <crypt15_out>");
            System.exit(2);
        }
        byte[] sqliteBytes = Files.readAllBytes(new File(args[0]).toPath());
        byte[] aesKey = deriveAesKey(args[1].trim());
        byte[] iv = new byte[16];
        for (int i = 0; i < 16; i++) iv[i] = (byte) (i + 1);

        // Build BackupPrefix protobuf:
        // field 3 (tag 0x1A) = C15IV { field 1 (tag 0x0A) = 16-byte iv }
        // field 4 (tag 0x22) = BackupMetadata { field 1 (tag 0x0A) = "2.24.20.78" }
        ByteArrayOutputStream c15IvMsg = new ByteArrayOutputStream();
        c15IvMsg.write(0x0A);
        c15IvMsg.write(iv.length);
        c15IvMsg.write(iv);
        byte[] c15IvBytes = c15IvMsg.toByteArray();

        byte[] appVer = "2.24.20.78".getBytes(StandardCharsets.UTF_8);
        ByteArrayOutputStream metaMsg = new ByteArrayOutputStream();
        metaMsg.write(0x0A);
        metaMsg.write(appVer.length);
        metaMsg.write(appVer);
        byte[] metaBytes = metaMsg.toByteArray();

        ByteArrayOutputStream prefix = new ByteArrayOutputStream();
        prefix.write(0x1A);
        prefix.write(writeVarint(c15IvBytes.length));
        prefix.write(c15IvBytes);
        prefix.write(0x22);
        prefix.write(writeVarint(metaBytes.length));
        prefix.write(metaBytes);
        byte[] prefixBytes = prefix.toByteArray();
        byte[] prefixLenVarint = writeVarint(prefixBytes.length);

        byte[] compressed = zlibCompress(sqliteBytes);
        Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
        cipher.init(Cipher.ENCRYPT_MODE, new SecretKeySpec(aesKey, "AES"), new GCMParameterSpec(128, iv));
        byte[] ciphertextWithTag = cipher.doFinal(compressed);

        MessageDigest md5 = MessageDigest.getInstance("MD5");
        md5.update(prefixLenVarint);
        md5.update(prefixBytes);
        md5.update(ciphertextWithTag);
        byte[] md5Footer = md5.digest();

        try (FileOutputStream fos = new FileOutputStream(args[2])) {
            fos.write(prefixLenVarint);
            fos.write(prefixBytes);
            fos.write(ciphertextWithTag);
            fos.write(md5Footer);
        }
    }
}
