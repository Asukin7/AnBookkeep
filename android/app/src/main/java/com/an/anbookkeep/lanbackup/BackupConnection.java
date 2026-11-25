package com.an.anbookkeep.lanbackup;

import com.an.anbookkeep.backup.protocol.BackupProtocol;
import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.net.InetAddress;
import java.net.Proxy;
import java.net.URI;
import java.net.URISyntaxException;
import java.net.URL;
import java.net.URLConnection;
import java.security.GeneralSecurityException;
import java.security.cert.CertificateException;
import java.security.cert.X509Certificate;
import javax.net.ssl.HttpsURLConnection;
import javax.net.ssl.SSLContext;
import javax.net.ssl.TrustManager;
import javax.net.ssl.X509TrustManager;

public final class BackupConnection implements AutoCloseable {
    private final InetAddress address;
    private final int port;
    private final ConnectionFactory connectionFactory;
    private final PeerIdentity peer;
    private final SSLContext tls;
    private volatile HttpsURLConnection active;
    private volatile boolean cancelled;

    public static final class Failure extends IOException {
        public final String code;

        public Failure(String code) {
            super(code);
            this.code = code;
        }
    }

    @FunctionalInterface
    public interface ConnectionFactory {
        URLConnection open(URL url) throws IOException;
    }

    public BackupConnection(InetAddress address, int port, String fingerprint)
            throws GeneralSecurityException {
        this(address, port, fingerprint, url -> url.openConnection(Proxy.NO_PROXY));
    }

    public BackupConnection(InetAddress address, int port, String fingerprint,
                            ConnectionFactory connectionFactory)
            throws GeneralSecurityException {
        this.address = address;
        this.port = port;
        this.connectionFactory = connectionFactory;
        peer = new PeerIdentity(fingerprint);
        tls = SSLContext.getInstance("TLS");
        tls.init(null, new TrustManager[] {peer}, null);
    }

    public void upload(File file, String name, String encodedKey) throws IOException {
        long length = file.length();
        byte[] buffer = new byte[BackupProtocol.BUFFER_SIZE];
        var digest = BackupProtocol.sha256();
        try (var input = new FileInputStream(file)) {
            int count;
            while ((count = input.read(buffer)) != -1) {
                checkCancelled();
                digest.update(buffer, 0, count);
            }
        }
        var connection = open(name, length);
        boolean connected = false;
        try {
            connection.setRequestProperty("Content-Type", BackupProtocol.XLSX_TYPE);
            connection.setRequestProperty("Authorization", BackupProtocol.authorization(encodedKey));
            connection.setRequestProperty(BackupProtocol.DIGEST_HEADER,
                    BackupProtocol.contentDigest(digest.digest()));
            connection.connect();
            connected = true;
            try (var input = new FileInputStream(file);
                 var output = connection.getOutputStream()) {
                int count;
                while ((count = input.read(buffer)) != -1) {
                    checkCancelled();
                    output.write(buffer, 0, count);
                }
            }
            requireSaved(connection);
        } catch (IOException error) {
            checkCancelled();
            if (peer.mismatch) throw new Failure("receiver_identity_mismatch");
            if (!connected) throw new Failure("receiver_unreachable");
            throw error;
        } finally {
            finish(connection);
        }
    }

    private HttpsURLConnection open(String name, long length) throws IOException {
        checkCancelled();
        try {
            var uri = new URI("https", null, address.getHostAddress(), port,
                    BackupProtocol.BACKUP_PATH + name, null, null);
            var url = URI.create(uri.toASCIIString()).toURL();
            var connection = (HttpsURLConnection) connectionFactory.open(url);
            connection.setSSLSocketFactory(tls.getSocketFactory());
            // The fingerprint in the configured Key is the receiver's identity, even if its IP changes.
            connection.setHostnameVerifier((host, session) -> true);
            connection.setInstanceFollowRedirects(false);
            connection.setConnectTimeout(3_000);
            connection.setReadTimeout(30_000);
            connection.setRequestMethod("PUT");
            connection.setDoOutput(true);
            connection.setFixedLengthStreamingMode(length);
            active = connection;
            if (cancelled) {
                finish(connection);
                throw new Failure("cancelled");
            }
            return connection;
        } catch (URISyntaxException e) {
            throw new Failure("invalid_backup_name");
        }
    }

    private static void requireSaved(HttpsURLConnection connection) throws IOException {
        int status = connection.getResponseCode();
        if (status == 204) {
            return;
        }
        String code = connection.getHeaderField(BackupProtocol.ERROR_HEADER);
        if (code != null && code.matches("[a-z_]{1,40}")) {
            throw new Failure(code);
        }
        throw new Failure(status == 401 ? "invalid_backup_key" : "receiver_error");
    }

    private void checkCancelled() throws Failure {
        if (cancelled) {
            throw new Failure("cancelled");
        }
    }

    private void finish(HttpsURLConnection connection) {
        active = null;
        connection.disconnect();
    }

    @Override
    public void close() {
        cancelled = true;
        var connection = active;
        if (connection != null) {
            connection.disconnect();
        }
    }

    private static final class PeerIdentity implements X509TrustManager {
        private final String fingerprint;
        private volatile boolean mismatch;

        private PeerIdentity(String fingerprint) {
            this.fingerprint = fingerprint;
        }

        @Override
        public void checkServerTrusted(X509Certificate[] chain, String authType)
                throws CertificateException {
            if (chain == null || chain.length == 0) {
                throw new CertificateException("Missing backup receiver certificate");
            }
            chain[0].checkValidity();
            if (!fingerprint.equals(BackupProtocol.receiverFingerprint(chain[0].getPublicKey()))) {
                mismatch = true;
                throw new CertificateException("Backup receiver fingerprint does not match");
            }
        }

        @Override
        public void checkClientTrusted(X509Certificate[] chain, String authType)
                throws CertificateException {
            throw new CertificateException("No client certificates are expected");
        }

        @Override
        public X509Certificate[] getAcceptedIssuers() {
            return new X509Certificate[0];
        }
    }
}
