package com.an.anbookkeep.backup;

import com.an.anbookkeep.backup.config.ReceiverConfig;
import com.an.anbookkeep.backup.config.ReceiverConfigLoader;
import com.an.anbookkeep.backup.discovery.LanServicePublisher;
import com.an.anbookkeep.backup.http.ReceiverHttpServer;
import com.an.anbookkeep.backup.protocol.BackupProtocol;
import com.an.anbookkeep.backup.security.TlsIdentityStore;
import com.an.anbookkeep.backup.storage.BackupStorage;
import java.io.IOException;
import java.net.Inet6Address;
import java.net.NetworkInterface;
import java.net.SocketException;
import java.nio.channels.FileChannel;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.util.concurrent.CountDownLatch;

public final class ReceiverMain {
    private static final int PORT = 18765;

    private ReceiverMain() {}

    public static void main(String[] args) {
        try {
            Path location = Path.of(ReceiverMain.class.getProtectionDomain()
                    .getCodeSource().getLocation().toURI()).toAbsolutePath();
            run(Files.isDirectory(location) ? location : location.getParent());
        } catch (Exception e) {
            System.err.println("Backup receiver stopped: " + e.getMessage());
            System.exit(1);
        }
    }

    private static void run(Path directory) throws Exception {
        Path state = Files.createDirectories(directory.resolve(".receiver"));
        try (var lockFile = FileChannel.open(state.resolve("receiver.lock"),
                StandardOpenOption.CREATE, StandardOpenOption.WRITE);
             var lock = lockFile.tryLock()) {
            if (lock == null) {
                throw new IOException("A backup receiver is already running from " + directory);
            }
            var config = ReceiverConfigLoader.loadOrCreate(directory);
            var storage = new BackupStorage(config.backupDirectory());
            storage.prepare();
            var identity = TlsIdentityStore.loadOrCreate(state);
            var stopped = new CountDownLatch(1);
            var finished = new CountDownLatch(1);
            try (var http = new ReceiverHttpServer(PORT, identity.context(), config.key(), storage);
                 var publisher = new LanServicePublisher()) {
                http.start();
                publisher.start(http.port(), identity.fingerprint());
                printConnectionInfo(config, http.port(), identity.fingerprint());
                var shutdown = new Thread(() -> {
                    stopped.countDown();
                    try {
                        finished.await();
                    } catch (InterruptedException e) {
                        Thread.currentThread().interrupt();
                    }
                }, "backup-receiver-shutdown");
                Runtime.getRuntime().addShutdownHook(shutdown);
                stopped.await();
            } finally {
                finished.countDown();
            }
        }
    }

    private static void printConnectionInfo(ReceiverConfig config, int port, String fingerprint) {
        System.out.println("AnBookkeep backup receiver listening on TCP " + port);
        try {
            boolean printedAddress = false;
            for (var network : NetworkInterface.networkInterfaces().toList()) {
                if (!network.isUp() || network.isLoopback()) continue;
                for (var address : network.inetAddresses().toList()) {
                    boolean ipv6 = address instanceof Inet6Address;
                    if (address.isAnyLocalAddress() || address.isLoopbackAddress()
                            || (ipv6 && address.isLinkLocalAddress())) continue;
                    String host = address.getHostAddress();
                    String endpoint = ipv6 ? "[" + host + "]" : host;
                    System.out.printf("Address: %s:%d (%s)%n", endpoint, port, network.getDisplayName());
                    printedAddress = true;
                }
            }
            if (!printedAddress) System.out.println("No LAN address available yet.");
        } catch (SocketException e) {
            System.err.println("Could not list LAN addresses: " + e.getMessage());
        }
        System.out.println("Key: " + BackupProtocol.connectionKey(fingerprint, config.key()));
        System.out.println("Backups: " + config.backupDirectory());
    }
}
