package com.an.anbookkeep.backup.storage;

import com.an.anbookkeep.backup.protocol.BackupProtocol;
import java.io.IOException;
import java.io.InputStream;
import java.nio.ByteBuffer;
import java.nio.channels.FileChannel;
import java.nio.file.AtomicMoveNotSupportedException;
import java.nio.file.Files;
import java.nio.file.LinkOption;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.nio.file.StandardOpenOption;
import java.security.MessageDigest;
import java.util.Locale;
import java.util.concurrent.locks.ReentrantLock;
import java.util.regex.Pattern;

public final class BackupStorage {
    private static final Pattern RESERVED = Pattern.compile(
            "(?i)(CON|PRN|AUX|NUL|COM[1-9¹²³]|LPT[1-9¹²³])(?:\\..*)?");
    private static final Pattern INVALID = Pattern.compile("[\\x00-\\x1f<>:\"/\\\\|?*]");
    private final Path directory;
    private final ReentrantLock uploadLock = new ReentrantLock();

    public enum Result {
        SAVED, INVALID_NAME, BUSY, INTEGRITY_MISMATCH, INSUFFICIENT_SPACE,
        ATOMIC_REPLACE_UNAVAILABLE, WRITE_FAILED
    }

    public BackupStorage(Path directory) {
        this.directory = directory;
    }

    public void prepare() throws IOException {
        Files.createDirectories(directory);
        Path probe = Files.createTempFile(directory, ".anbookkeep-", ".part");
        Files.delete(probe);
    }

    public Result save(String name, InputStream input, long length, byte[] expected) {
        if (!validName(name)) {
            return Result.INVALID_NAME;
        }
        if (!uploadLock.tryLock()) {
            return Result.BUSY;
        }
        Path temporary = null;
        try {
            Path target = directory.resolve(name + ".xlsx");
            if (Files.exists(target, LinkOption.NOFOLLOW_LINKS)
                    && !Files.isRegularFile(target, LinkOption.NOFOLLOW_LINKS)) {
                return Result.WRITE_FAILED;
            }
            if (Files.getFileStore(directory).getUsableSpace() < length) {
                return Result.INSUFFICIENT_SPACE;
            }
            temporary = Files.createTempFile(directory, ".anbookkeep-", ".part");
            if (!writeAndVerify(temporary, input, length, expected)) {
                return Result.INTEGRITY_MISMATCH;
            }
            Files.move(temporary, target, StandardCopyOption.ATOMIC_MOVE,
                    StandardCopyOption.REPLACE_EXISTING);
            return Result.SAVED;
        } catch (AtomicMoveNotSupportedException e) {
            return Result.ATOMIC_REPLACE_UNAVAILABLE;
        } catch (IOException e) {
            return Result.WRITE_FAILED;
        } finally {
            if (temporary != null) {
                try {
                    Files.deleteIfExists(temporary);
                } catch (IOException e) {
                    System.err.println("Could not remove an incomplete backup file.");
                }
            }
            uploadLock.unlock();
        }
    }

    private static boolean writeAndVerify(Path file, InputStream input, long length, byte[] expected)
            throws IOException {
        MessageDigest digest = BackupProtocol.sha256();
        byte[] bytes = new byte[BackupProtocol.BUFFER_SIZE];
        long remaining = length;
        try (var output = FileChannel.open(file, StandardOpenOption.WRITE)) {
            while (remaining > 0) {
                int count = input.read(bytes, 0, (int) Math.min(bytes.length, remaining));
                if (count < 0) {
                    return false;
                }
                digest.update(bytes, 0, count);
                ByteBuffer chunk = ByteBuffer.wrap(bytes, 0, count);
                while (chunk.hasRemaining()) {
                    output.write(chunk);
                }
                remaining -= count;
            }
            if (input.read() != -1 || !MessageDigest.isEqual(digest.digest(), expected)) {
                return false;
            }
            output.force(true);
            return true;
        }
    }

    private static boolean validName(String name) {
        return !name.isBlank() && !name.endsWith(".") && !name.endsWith(" ")
                && !name.toLowerCase(Locale.ROOT).endsWith(".xlsx")
                && !INVALID.matcher(name).find() && !RESERVED.matcher(name).matches();
    }
}
