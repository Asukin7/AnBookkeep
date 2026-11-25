package com.an.anbookkeep.backup.discovery;

import com.an.anbookkeep.backup.protocol.BackupProtocol;
import java.io.IOException;
import java.util.Map;
import javax.jmdns.JmmDNS;
import javax.jmdns.ServiceInfo;

public final class LanServicePublisher implements AutoCloseable {
    private final JmmDNS dns = JmmDNS.Factory.getInstance();
    private ServiceInfo service;

    public void start(int port, String fingerprint) throws IOException {
        String host = System.getenv("COMPUTERNAME");
        String name = host == null || host.isBlank() ? "AnBookkeep Backup" : "AnBookkeep - " + host;
        service = ServiceInfo.create(BackupProtocol.SERVICE_TYPE + ".local.", name, port,
                0, 0, Map.of(BackupProtocol.FINGERPRINT_ATTRIBUTE, fingerprint));
        dns.registerService(service);
    }

    @Override
    public void close() throws IOException {
        if (service != null) {
            dns.unregisterService(service);
        }
        JmmDNS.Factory.close();
    }
}
