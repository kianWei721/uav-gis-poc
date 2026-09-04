package com.dongming.gis.worker.config;

import java.lang.management.ManagementFactory;
import java.net.InetAddress;
import java.net.UnknownHostException;
import java.util.UUID;

/**
 * 生成当前 Worker 实例标识。
 */
public class WorkerIdentity {

    private final String value;

    public WorkerIdentity(String configuredId) {
        this.value = hasText(configuredId) ? configuredId.trim() : generateId();
    }

    public String getValue() {
        return value;
    }

    private String generateId() {
        String host = "unknown-host";
        try {
            host = InetAddress.getLocalHost().getHostName();
        } catch (UnknownHostException ignored) {
            // 主机名不可用时使用固定占位，进程标识和随机段仍能保证区分实例。
        }
        String process = ManagementFactory.getRuntimeMXBean().getName().replace('@', '-');
        return host + "-" + process + "-" + UUID.randomUUID().toString().substring(0, 8);
    }

    private boolean hasText(String value) {
        return value != null && !value.trim().isEmpty();
    }
}
