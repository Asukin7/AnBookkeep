package com.an.anbookkeep.backup.http;

import com.an.anbookkeep.backup.protocol.BackupProtocol;
import com.an.anbookkeep.backup.storage.BackupStorage;
import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpsConfigurator;
import com.sun.net.httpserver.HttpsServer;
import java.io.IOException;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;
import javax.net.ssl.SSLContext;

public final class ReceiverHttpServer implements AutoCloseable {
    private final HttpsServer server;
    private final ThreadPoolExecutor workers;

    public ReceiverHttpServer(int port, SSLContext context, String key, BackupStorage storage)
            throws IOException {
        // These JDK server settings are read when the standalone HTTPS server starts.
        System.setProperty("sun.net.httpserver.maxReqTime", "180");
        System.setProperty("sun.net.httpserver.maxRspTime", "30");
        System.setProperty("jdk.httpserver.maxConnections", "24");
        server = HttpsServer.create(new InetSocketAddress(port), 16);
        server.setHttpsConfigurator(new HttpsConfigurator(context));
        workers = new ThreadPoolExecutor(4, 4, 20, TimeUnit.SECONDS, new ArrayBlockingQueue<>(8));
        workers.allowCoreThreadTimeOut(true);
        server.setExecutor(workers);
        server.createContext(BackupProtocol.BACKUP_PATH, new BackupUploadHandler(key, storage));
    }

    public void start() {
        server.start();
    }

    public int port() {
        return server.getAddress().getPort();
    }

    @Override
    public void close() {
        server.stop(0);
        workers.shutdownNow();
    }

    static void reply(HttpExchange exchange, int status, String code) throws IOException {
        byte[] bytes = code.getBytes(StandardCharsets.US_ASCII);
        exchange.getResponseHeaders().set("Content-Type", "text/plain; charset=us-ascii");
        exchange.getResponseHeaders().set(BackupProtocol.ERROR_HEADER, code);
        exchange.getResponseHeaders().set("Cache-Control", "no-store");
        exchange.sendResponseHeaders(status, bytes.length);
        exchange.getResponseBody().write(bytes);
    }
}
