package com.dongming.gis.worker.task;

import com.dongming.gis.worker.client.GisBackendClient;
import com.dongming.gis.worker.client.dto.GisClaimedTask;
import com.dongming.gis.worker.config.GisWorkerProperties;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import javax.annotation.PreDestroy;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.ScheduledFuture;
import java.util.concurrent.ThreadFactory;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;

/**
 * 运行中任务的心跳与租约续期服务。
 */
@Service
public class GisTaskHeartbeatService {

    private static final Logger log = LoggerFactory.getLogger(GisTaskHeartbeatService.class);

    private final GisBackendClient backendClient;
    private final GisWorkerProperties properties;
    private final ScheduledExecutorService scheduler;

    public GisTaskHeartbeatService(GisBackendClient backendClient, GisWorkerProperties properties) {
        this.backendClient = backendClient;
        this.properties = properties;
        this.scheduler = Executors.newScheduledThreadPool(2, new HeartbeatThreadFactory());
    }

    public HeartbeatHandle start(GisClaimedTask task, Thread processorThread) {
        HeartbeatHandle handle = new HeartbeatHandle(task, processorThread);
        ScheduledFuture<?> future = scheduler.scheduleAtFixedRate(
                () -> heartbeat(handle),
                properties.getHeartbeatIntervalSeconds(),
                properties.getHeartbeatIntervalSeconds(),
                TimeUnit.SECONDS);
        handle.setFuture(future);
        return handle;
    }

    private void heartbeat(HeartbeatHandle handle) {
        if (handle.isClosed()) {
            return;
        }
        try {
            if (backendClient.heartbeat(handle.getTask())) {
                log.info("GIS 任务心跳成功，taskId={}，datasetId={}，workerId={}",
                        handle.getTaskId(), handle.getDatasetId(), handle.getWorkerId());
                return;
            }
            handle.markOwnershipLost();
            log.warn("GIS 任务心跳更新为 0，已失去所有权并中断处理器，taskId={}，datasetId={}，workerId={}",
                    handle.getTaskId(), handle.getDatasetId(), handle.getWorkerId());
        } catch (RuntimeException e) {
            log.error("GIS 任务心跳异常，等待下一次心跳或租约回收，taskId={}，datasetId={}，workerId={}",
                    handle.getTaskId(), handle.getDatasetId(), handle.getWorkerId(), e);
        }
    }

    @PreDestroy
    public void shutdown() {
        scheduler.shutdownNow();
    }

    public static final class HeartbeatHandle implements AutoCloseable {

        private final Long taskId;
        private final Long datasetId;
        private final String workerId;
        private final String claimToken;
        private final GisClaimedTask task;
        private final Thread processorThread;
        private final AtomicBoolean ownershipLost = new AtomicBoolean(false);
        private final AtomicBoolean closed = new AtomicBoolean(false);
        private volatile ScheduledFuture<?> future;

        private HeartbeatHandle(GisClaimedTask task, Thread processorThread) {
            this.task = task;
            this.taskId = task.getTaskId();
            this.datasetId = task.getDatasetId();
            this.workerId = task.getWorkerId();
            this.claimToken = task.getClaimToken();
            this.processorThread = processorThread;
        }

        private void setFuture(ScheduledFuture<?> future) {
            this.future = future;
        }

        private void markOwnershipLost() {
            if (ownershipLost.compareAndSet(false, true)) {
                processorThread.interrupt();
                close();
            }
        }

        public boolean isOwnershipLost() {
            return ownershipLost.get();
        }

        private boolean isClosed() {
            return closed.get();
        }

        public Long getTaskId() {
            return taskId;
        }

        public Long getDatasetId() {
            return datasetId;
        }

        public String getWorkerId() {
            return workerId;
        }

        public String getClaimToken() {
            return claimToken;
        }

        private GisClaimedTask getTask() {
            return task;
        }

        @Override
        public void close() {
            if (closed.compareAndSet(false, true)) {
                ScheduledFuture<?> current = future;
                if (current != null) {
                    current.cancel(false);
                }
            }
        }
    }

    private static final class HeartbeatThreadFactory implements ThreadFactory {

        private int sequence;

        @Override
        public synchronized Thread newThread(Runnable runnable) {
            Thread thread = new Thread(runnable, "gis-heartbeat-" + (++sequence));
            thread.setDaemon(true);
            return thread;
        }
    }
}
