package com.an.anbookkeep.backup.security;

import com.an.anbookkeep.backup.protocol.BackupProtocol;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.security.GeneralSecurityException;
import java.security.KeyStore;
import java.security.SecureRandom;
import java.time.Duration;
import java.util.Arrays;
import java.util.Base64;
import java.util.concurrent.TimeUnit;
import javax.net.ssl.KeyManagerFactory;
import javax.net.ssl.SSLContext;

public final class TlsIdentityStore {
    private static final String ALIAS = "anbookkeep-backup";
    private static final String PASSWORD_ENV = "ANBOOKKEEP_TLS_STORE_PASSWORD";

    private TlsIdentityStore() {}

    public record Identity(SSLContext context, String fingerprint) {}

    public static Identity loadOrCreate(Path stateDirectory)
            throws IOException, GeneralSecurityException, InterruptedException {
        Path passwordFile = stateDirectory.resolve("identity.password");
        Path keyStoreFile = stateDirectory.resolve("identity.p12");
        if (Files.notExists(passwordFile) && Files.notExists(keyStoreFile)) {
            byte[] bytes = new byte[24];
            new SecureRandom().nextBytes(bytes);
            Files.writeString(passwordFile, Base64.getUrlEncoder().withoutPadding().encodeToString(bytes),
                    java.nio.file.StandardOpenOption.CREATE_NEW);
        }
        String password = Files.readString(passwordFile).strip();
        if (password.length() < 16) {
            throw new IOException("Invalid TLS identity password in " + stateDirectory);
        }
        if (Files.notExists(keyStoreFile)) {
            generateKeyStore(stateDirectory, keyStoreFile, password);
        }
        char[] passwordChars = password.toCharArray();
        try {
            var keyStore = KeyStore.getInstance("PKCS12");
            try (var input = Files.newInputStream(keyStoreFile)) {
                keyStore.load(input, passwordChars);
            }
            var certificate = keyStore.getCertificate(ALIAS);
            if (certificate == null) {
                throw new IOException("Missing TLS certificate in " + keyStoreFile);
            }
            var keyManagers = KeyManagerFactory.getInstance(KeyManagerFactory.getDefaultAlgorithm());
            keyManagers.init(keyStore, passwordChars);
            var context = SSLContext.getInstance("TLS");
            context.init(keyManagers.getKeyManagers(), null, null);
            return new Identity(context, BackupProtocol.receiverFingerprint(certificate.getPublicKey()));
        } finally {
            Arrays.fill(passwordChars, '\0');
        }
    }

    private static void generateKeyStore(Path directory, Path target, String password)
            throws IOException, InterruptedException {
        Path bin = Path.of(System.getProperty("java.home"), "bin");
        Path keytool = bin.resolve("keytool");
        if (!Files.isRegularFile(keytool)) {
            keytool = bin.resolve("keytool.exe");
        }
        Path staging = Files.createTempDirectory(directory, "identity-");
        Path temporary = staging.resolve("identity.p12");
        try {
            var command = new ProcessBuilder(keytool.toString(), "-genkeypair", "-noprompt",
                    "-alias", ALIAS, "-keyalg", "EC", "-groupname", "secp256r1",
                    "-validity", "3650", "-dname", "CN=AnBookkeep Backup",
                    "-storetype", "PKCS12", "-keystore", temporary.toString(),
                    "-storepass:env", PASSWORD_ENV);
            command.environment().put(PASSWORD_ENV, password);
            command.redirectOutput(ProcessBuilder.Redirect.DISCARD);
            command.redirectError(ProcessBuilder.Redirect.DISCARD);
            Process process = command.start();
            try {
                if (!process.waitFor(Duration.ofSeconds(30).toSeconds(), TimeUnit.SECONDS)
                        || process.exitValue() != 0) {
                    throw new IOException("Could not generate TLS identity with Java keytool");
                }
            } finally {
                if (process.isAlive()) {
                    process.destroyForcibly();
                }
            }
            Files.move(temporary, target, StandardCopyOption.ATOMIC_MOVE);
        } finally {
            Files.deleteIfExists(temporary);
            Files.deleteIfExists(staging);
        }
    }
}
