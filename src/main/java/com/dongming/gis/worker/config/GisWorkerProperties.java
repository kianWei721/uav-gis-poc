package com.dongming.gis.worker.config;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

/**
 * Worker 执行、心跳与租约参数。
 */
@ConfigurationProperties(prefix = "gis.worker")
@Component
public class GisWorkerProperties {

    private String id;
    private long pollIntervalMs = 5000L;
    private int heartbeatIntervalSeconds = 30;
    private int sleepStepSeconds = 5;

    public String getId() {
        return id;
    }

    public void setId(String id) {
        this.id = id;
    }

    public long getPollIntervalMs() {
        return pollIntervalMs;
    }

    public void setPollIntervalMs(long pollIntervalMs) {
        this.pollIntervalMs = pollIntervalMs;
    }

    public int getHeartbeatIntervalSeconds() {
        return heartbeatIntervalSeconds;
    }

    public void setHeartbeatIntervalSeconds(int heartbeatIntervalSeconds) {
        this.heartbeatIntervalSeconds = heartbeatIntervalSeconds;
    }

    public int getSleepStepSeconds() {
        return sleepStepSeconds;
    }

    public void setSleepStepSeconds(int sleepStepSeconds) {
        this.sleepStepSeconds = sleepStepSeconds;
    }

}
