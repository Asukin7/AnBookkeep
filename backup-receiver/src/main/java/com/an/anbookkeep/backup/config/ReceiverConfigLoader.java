package com.an.anbookkeep.backup.config;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.InvalidPathException;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.security.SecureRandom;
import java.util.Base64;
import java.util.HashMap;
import java.util.Map;

public final class ReceiverConfigLoader {
    private ReceiverConfigLoader() {}

    public static ReceiverConfig loadOrCreate(Path programDirectory) throws IOException {
        Path configFile = programDirectory.resolve("config.properties");
        if (Files.notExists(configFile)) {
            byte[] randomBytes = new byte[32];
            new SecureRandom().nextBytes(randomBytes);
            String key = Base64.getUrlEncoder().withoutPadding().encodeToString(randomBytes);
            Path temporary = Files.createTempFile(programDirectory, ".backup-config-", ".tmp");
            try {
                Files.writeString(temporary, "key=" + key + System.lineSeparator()
                        + "backup.path=backups" + System.lineSeparator());
                Files.move(temporary, configFile, StandardCopyOption.ATOMIC_MOVE);
            } finally {
                Files.deleteIfExists(temporary);
            }
            System.out.println("Created configuration: " + configFile);
        }

        // The two values are literal so pasted Windows paths keep their backslashes.
        Map<String, String> properties = new HashMap<>();
        for (String line : Files.readAllLines(configFile)) {
            String trimmed = line.strip();
            if (trimmed.isEmpty() || trimmed.startsWith("#") || trimmed.startsWith("!")) {
                continue;
            }
            int separator = trimmed.indexOf('=');
            if (separator < 1 || properties.putIfAbsent(trimmed.substring(0, separator).strip(),
                    trimmed.substring(separator + 1).strip()) != null) {
                throw new IOException("Invalid or duplicate setting in " + configFile);
            }
        }
        String key = required(properties, "key", configFile);
        String directory = required(properties, "backup.path", configFile);
        try {
            return new ReceiverConfig(key, programDirectory.resolve(Path.of(directory)).normalize());
        } catch (InvalidPathException e) {
            throw new IOException("Invalid backup.path in " + configFile);
        }
    }

    private static String required(Map<String, String> properties, String field, Path file)
            throws IOException {
        String value = properties.get(field);
        if (value == null || value.isBlank()) {
            throw new IOException("Missing " + field + " in " + file);
        }
        return value;
    }
}
