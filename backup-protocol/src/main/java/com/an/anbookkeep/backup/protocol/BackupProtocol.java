package com.an.anbookkeep.backup.protocol;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.security.PublicKey;
import java.util.Base64;

public final class BackupProtocol {
    public static final String SERVICE_TYPE = "_anbk-backup._tcp";
    public static final String BACKUP_PATH = "/backups/";
    public static final String FINGERPRINT_ATTRIBUTE = "fingerprint";
    public static final String ERROR_HEADER = "X-Backup-Error";
    public static final String DIGEST_HEADER = "Content-Digest";
    public static final String XLSX_TYPE =
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";
    public static final int BUFFER_SIZE = 64 * 1024;

    private BackupProtocol() {}

    public static MessageDigest sha256() {
        try {
            return MessageDigest.getInstance("SHA-256");
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException("SHA-256 is unavailable", e);
        }
    }

    public static String receiverFingerprint(PublicKey publicKey) {
        return Base64.getUrlEncoder().withoutPadding()
                .encodeToString(sha256().digest(publicKey.getEncoded()));
    }

    public static String connectionKey(String fingerprint, String key) {
        return fingerprint + "." + encodeKey(key);
    }

    public static String encodeKey(String key) {
        return Base64.getUrlEncoder().withoutPadding().encodeToString(key.getBytes(StandardCharsets.UTF_8));
    }

    public static String authorization(String encodedKey) {
        return "Bearer " + encodedKey;
    }

    public static String contentDigest(byte[] digest) {
        return "sha-256=:" + Base64.getEncoder().encodeToString(digest) + ":";
    }
}
