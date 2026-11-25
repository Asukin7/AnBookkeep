package com.an.anbookkeep.backup.http;

import com.an.anbookkeep.backup.protocol.BackupProtocol;
import com.an.anbookkeep.backup.storage.BackupStorage;
import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpHandler;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.time.Duration;
import java.util.Base64;
import java.util.regex.Pattern;

final class BackupUploadHandler implements HttpHandler {
    private static final Pattern DIGEST = Pattern.compile("sha-256=:([A-Za-z0-9+/]{43}=):");
    private static final long AUTH_WINDOW = Duration.ofMinutes(1).toNanos();
    private static final int MAX_FAILED_ATTEMPTS = 30;
    private final byte[] expectedAuthorization;
    private final BackupStorage storage;
    private long authWindowStart = System.nanoTime();
    private int failedAttempts;

    BackupUploadHandler(String key, BackupStorage storage) {
        expectedAuthorization = authorizationDigest(BackupProtocol.authorization(BackupProtocol.encodeKey(key)));
        this.storage = storage;
    }

    @Override
    public void handle(HttpExchange exchange) throws IOException {
        try (exchange) {
            if (!exchange.getRequestMethod().equals("PUT")) {
                ReceiverHttpServer.reply(exchange, 405, "method_not_allowed");
                return;
            }
            var headers = exchange.getRequestHeaders();
            int authorization = authorize(headers.getFirst("Authorization"));
            if (authorization != 200) {
                ReceiverHttpServer.reply(exchange, authorization,
                        authorization == 429 ? "receiver_busy" : "invalid_backup_key");
                return;
            }
            if (!BackupProtocol.XLSX_TYPE.equals(headers.getFirst("Content-Type"))) {
                ReceiverHttpServer.reply(exchange, 415, "invalid_content_type");
                return;
            }
            long length;
            byte[] digest;
            try {
                length = Long.parseLong(headers.getFirst("Content-Length"));
                String digestHeader = headers.getFirst(BackupProtocol.DIGEST_HEADER);
                var value = DIGEST.matcher(digestHeader == null ? "" : digestHeader);
                if (length <= 0 || !value.matches()) {
                    throw new IllegalArgumentException("Invalid length or digest");
                }
                digest = Base64.getDecoder().decode(value.group(1));
            } catch (IllegalArgumentException e) {
                ReceiverHttpServer.reply(exchange, 400, "invalid_upload_headers");
                return;
            }
            String path = exchange.getRequestURI().getPath();
            String name = path.substring(BackupProtocol.BACKUP_PATH.length());
            var result = storage.save(name, exchange.getRequestBody(), length, digest);
            switch (result) {
                case SAVED -> {
                    System.out.println("Backup saved (" + length + " bytes).");
                    exchange.sendResponseHeaders(204, -1);
                }
                case INVALID_NAME -> ReceiverHttpServer.reply(exchange, 400, "invalid_backup_name");
                case BUSY -> ReceiverHttpServer.reply(exchange, 409, "receiver_busy");
                case INTEGRITY_MISMATCH -> ReceiverHttpServer.reply(exchange, 422, "integrity_mismatch");
                case INSUFFICIENT_SPACE -> ReceiverHttpServer.reply(exchange, 507, "insufficient_space");
                case ATOMIC_REPLACE_UNAVAILABLE ->
                        ReceiverHttpServer.reply(exchange, 500, "atomic_replace_unavailable");
                case WRITE_FAILED -> ReceiverHttpServer.reply(exchange, 500, "write_failed");
            }
        }
    }

    private synchronized int authorize(String authorization) {
        long now = System.nanoTime();
        if (now - authWindowStart >= AUTH_WINDOW) {
            authWindowStart = now;
            failedAttempts = 0;
        }
        if (failedAttempts >= MAX_FAILED_ATTEMPTS) return 429;
        if (authorization != null && MessageDigest.isEqual(
                expectedAuthorization, authorizationDigest(authorization))) return 200;
        failedAttempts++;
        return 401;
    }

    private static byte[] authorizationDigest(String authorization) {
        return BackupProtocol.sha256().digest(authorization.getBytes(StandardCharsets.UTF_8));
    }
}
