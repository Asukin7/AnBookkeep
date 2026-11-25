package com.an.anbookkeep.lanbackup

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ext.SdkExtensions
import android.util.Log
import com.an.anbookkeep.backup.protocol.BackupProtocol
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.net.Inet4Address
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.Proxy
import java.util.concurrent.Executor
import java.util.concurrent.Executors
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicLong
import java.util.concurrent.atomic.AtomicReference

class LanBackupChannel(
    context: Context,
    messenger: BinaryMessenger,
) : AutoCloseable {
    private companion object {
        val backupOwner = AtomicReference<LanBackupChannel?>()
        val callbacks = Executor { it.run() }
    }

    private val appContext = context.applicationContext
    private val wifi = appContext.getSystemService(WifiManager::class.java)
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private val generation = AtomicLong()
    private val connection = AtomicReference<BackupConnection?>()
    private val channel = MethodChannel(messenger, "com.an.anbookkeep/lan_backup")
    private var preparedUpload: PreparedUpload? = null

    private data class PreparedUpload(
        val fingerprint: String,
        val key: String,
        val endpoint: InetSocketAddress?,
        val network: Network?,
    )

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "prepare" -> {
                    val key = call.argument<String>("key").orEmpty()
                    val fingerprint = call.argument<String>("fingerprint").orEmpty()
                    val address = call.argument<ByteArray>("address")
                    val port = call.argument<Int>("port")
                    val requireLan = call.argument<Boolean>("requireLan") == true
                    runRequest(result) {
                        val network = if (requireLan) {
                            findLan() ?: throw BackupConnection.Failure("lan_unavailable")
                        } else null
                        prepare(key, fingerprint, address, port, network)
                    }
                }
                "upload" -> {
                    val path = call.argument<String>("path").orEmpty()
                    val name = call.argument<String>("name").orEmpty()
                    runRequest(result) { request -> upload(path, name, request) }
                }
                "cancel" -> cancel(result)
                else -> result.notImplemented()
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun findLan(): Network? {
        val connectivity = appContext.getSystemService(ConnectivityManager::class.java)
            ?: return null
        return (listOfNotNull(connectivity.activeNetwork) + connectivity.allNetworks).firstOrNull {
            val capabilities = connectivity.getNetworkCapabilities(it) ?: return@firstOrNull false
            capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN) &&
                (capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) ||
                    capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET))
        }
    }

    private fun runRequest(result: MethodChannel.Result, block: (Long) -> Unit) {
        val request = generation.get()
        worker.execute {
            try {
                ensureCurrent(request)
                block(request)
                main.post { result.success(null) }
            } catch (error: Exception) {
                val code = when (error) {
                    is BackupConnection.Failure -> error.code
                    is SecurityException -> "network_permission_denied"
                    is InterruptedException -> "cancelled"
                    is IOException -> "connection_lost"
                    else -> "receiver_error"
                }
                main.post { result.error(code, null, null) }
            }
        }
    }

    private fun prepare(
        key: String,
        fingerprint: String,
        address: ByteArray?,
        port: Int?,
        backupNetwork: Network?,
    ) {
        if (key.isEmpty() || fingerprint.isEmpty()) throw BackupConnection.Failure("invalid_backup_key")
        val endpoint = if (address != null || port != null) {
            if (address == null || (address.size != 4 && address.size != 16) ||
                port == null || port !in 1..65_535) {
                throw BackupConnection.Failure("invalid_direct_address")
            }
            InetSocketAddress(InetAddress.getByAddress(address), port)
        } else null
        if (!backupOwner.compareAndSet(null, this)) {
            throw BackupConnection.Failure("backup_in_progress")
        }
        preparedUpload = PreparedUpload(fingerprint, key, endpoint, backupNetwork)
    }

    private fun upload(path: String, name: String, request: Long) {
        val target = preparedUpload ?: throw BackupConnection.Failure("backup_not_configured")
        preparedUpload = null
        val file = File(path).canonicalFile
        if (!file.toPath().startsWith(appContext.cacheDir.canonicalFile.toPath()) || !file.isFile) {
            throw BackupConnection.Failure("backup_file_unavailable")
        }
        val backupNetwork = target.network
        val endpoint = target.endpoint
        if (endpoint != null) {
            uploadTo(endpoint.address, endpoint.port, backupNetwork, target, file, name, request)
            return
        }
        val nsd = appContext.getSystemService(NsdManager::class.java)
            ?: throw BackupConnection.Failure("receiver_unavailable")
        val candidates = LinkedBlockingQueue<NsdServiceInfo>(16)
        val discoveryError = AtomicReference<Int?>()
        val discovery = object : NsdManager.DiscoveryListener {
            override fun onDiscoveryStarted(serviceType: String) = Unit
            override fun onDiscoveryStopped(serviceType: String) = Unit
            override fun onServiceLost(service: NsdServiceInfo) = Unit
            override fun onServiceFound(service: NsdServiceInfo) {
                candidates.offer(service)
            }
            override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) {
                discoveryError.set(errorCode)
            }
            override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) = Unit
        }
        val multicast = if (backupNetwork != null || Build.VERSION.SDK_INT < 33 ||
            SdkExtensions.getExtensionVersion(Build.VERSION_CODES.TIRAMISU) < 7) {
            wifi?.createMulticastLock("anbookkeep-backup")?.apply { acquire() }
        } else null
        var discoveryStarted = false
        var foundService = false
        var failure: BackupConnection.Failure? = null
        val seen = mutableSetOf<String>()
        val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(12)
        try {
            if (backupNetwork != null && Build.VERSION.SDK_INT >= 33) {
                nsd.discoverServices(
                    BackupProtocol.SERVICE_TYPE, NsdManager.PROTOCOL_DNS_SD,
                    backupNetwork, callbacks, discovery,
                )
            } else {
                nsd.discoverServices(BackupProtocol.SERVICE_TYPE, NsdManager.PROTOCOL_DNS_SD, discovery)
            }
            discoveryStarted = true
            while (true) {
                ensureCurrent(request)
                discoveryError.get()?.let { error ->
                    Log.w("LanBackup", "NSD discovery failed ($error)")
                    throw BackupConnection.Failure("discovery_failed")
                }
                val remaining = deadline - System.nanoTime()
                if (remaining <= 0) break
                val candidate = candidates.poll(minOf(remaining, TimeUnit.MILLISECONDS.toNanos(250)),
                    TimeUnit.NANOSECONDS) ?: continue
                foundService = true
                val resolved = resolve(nsd, candidate, deadline) ?: continue
                val fingerprint = resolved.attributes[BackupProtocol.FINGERPRINT_ATTRIBUTE]
                if (fingerprint?.toString(Charsets.US_ASCII) != target.fingerprint) {
                    failure = BackupConnection.Failure("receiver_identity_mismatch")
                    continue
                }
                val network = backupNetwork ?: if (Build.VERSION.SDK_INT >= 34) {
                    resolved.network ?: candidate.network
                } else null
                for (host in addresses(resolved).sortedBy { it !is Inet4Address }) {
                    ensureCurrent(request)
                    if (!seen.add("$network/${host.hostAddress}:${resolved.port}")) continue
                    try {
                        uploadTo(host, resolved.port, network, target, file, name, request)
                        return
                    } catch (error: BackupConnection.Failure) {
                        if (error.code != "receiver_unreachable" &&
                            error.code != "receiver_identity_mismatch") throw error
                        if (failure == null || error.code != "receiver_unreachable") {
                            failure = error
                        }
                    }
                }
            }
            throw failure ?: BackupConnection.Failure(
                if (foundService) "receiver_address_unavailable" else "receiver_unavailable",
            )
        } finally {
            if (discoveryStarted) {
                runCatching { nsd.stopServiceDiscovery(discovery) }
            }
            multicast?.release()
        }
    }

    private fun uploadTo(
        address: InetAddress,
        port: Int,
        network: Network?,
        target: PreparedUpload,
        file: File,
        name: String,
        request: Long,
    ) {
        val transport = if (network == null) {
            BackupConnection(address, port, target.fingerprint)
        } else {
            BackupConnection(address, port, target.fingerprint) { url ->
                network.openConnection(url, Proxy.NO_PROXY)
            }
        }
        connection.set(transport)
        try {
            ensureCurrent(request)
            transport.upload(file, name, target.key)
            ensureCurrent(request)
        } finally {
            connection.compareAndSet(transport, null)
            transport.close()
        }
    }

    private fun resolve(nsd: NsdManager, service: NsdServiceInfo, deadline: Long): NsdServiceInfo? {
        if (hasResolvedIdentity(service)) return service
        val wait = minOf(deadline - System.nanoTime(), TimeUnit.SECONDS.toNanos(4))
        if (wait <= 0) return null
        val results = LinkedBlockingQueue<NsdServiceInfo>(1)
        if (Build.VERSION.SDK_INT >= 34) {
            val callback = object : NsdManager.ServiceInfoCallback {
                override fun onServiceInfoCallbackRegistrationFailed(error: Int) {
                    Log.w("LanBackup", "NSD address subscription failed ($error)")
                    results.offer(NsdServiceInfo())
                }
                override fun onServiceInfoCallbackUnregistered() = Unit
                override fun onServiceLost() {
                    results.offer(NsdServiceInfo())
                }
                override fun onServiceUpdated(info: NsdServiceInfo) {
                    if (hasResolvedIdentity(info)) results.offer(info)
                }
            }
            nsd.registerServiceInfoCallback(service, callbacks, callback)
            return try {
                results.poll(wait, TimeUnit.NANOSECONDS)?.takeIf { it.port > 0 }
            } finally {
                runCatching { nsd.unregisterServiceInfoCallback(callback) }
            }
        }
        return resolveOnce(nsd, service, results, wait)
    }

    private fun hasResolvedIdentity(service: NsdServiceInfo): Boolean =
        service.port > 0 && addresses(service).isNotEmpty() &&
            service.attributes.containsKey(BackupProtocol.FINGERPRINT_ATTRIBUTE)

    @Suppress("DEPRECATION")
    private fun resolveOnce(
        nsd: NsdManager,
        service: NsdServiceInfo,
        results: LinkedBlockingQueue<NsdServiceInfo>,
        wait: Long,
    ): NsdServiceInfo? {
        val resolver = object : NsdManager.ResolveListener {
            override fun onResolveFailed(info: NsdServiceInfo, error: Int) {
                Log.w("LanBackup", "NSD address resolution failed ($error)")
                results.offer(NsdServiceInfo())
            }
            override fun onServiceResolved(info: NsdServiceInfo) {
                results.offer(info)
            }
        }
        nsd.resolveService(service, resolver)
        return results.poll(wait, TimeUnit.NANOSECONDS)?.takeIf { it.port > 0 }
    }

    @Suppress("DEPRECATION")
    private fun addresses(service: NsdServiceInfo) = if (Build.VERSION.SDK_INT >= 34) {
        service.hostAddresses
    } else {
        listOfNotNull(service.host)
    }

    private fun ensureCurrent(request: Long) {
        if (request != generation.get()) throw BackupConnection.Failure("cancelled")
    }

    private fun cancel(result: MethodChannel.Result? = null) {
        generation.incrementAndGet()
        connection.getAndSet(null)?.let { previous ->
            Thread(previous::close, "lan-backup-cancel").start()
        }
        worker.execute {
            preparedUpload = null
            backupOwner.compareAndSet(this, null)
            if (result != null) main.post { result.success(null) }
        }
    }

    override fun close() {
        channel.setMethodCallHandler(null)
        cancel()
        worker.shutdown()
    }
}
