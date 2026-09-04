package com.dongming.gis.worker.polling;

import com.dongming.gis.worker.client.GisBackendClient;
import com.dongming.gis.worker.client.dto.GisClaimedTask;
import com.dongming.gis.worker.executor.GisTaskExecutor;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.util.Optional;

/**
 * 每五秒通过 HTTPS 尝试 Claim 一个 GIS 任务。
 */
@Component
public class GisTaskPoller {

    private static final Logger log = LoggerFactory.getLogger(GisTaskPoller.class);

    private final GisBackendClient backendClient;
    private final GisTaskExecutor taskExecutor;

    public GisTaskPoller(GisBackendClient backendClient, GisTaskExecutor taskExecutor) {
        this.backendClient = backendClient;
        this.taskExecutor = taskExecutor;
    }

    @Scheduled(initialDelayString = "${gis.worker.poll-interval-ms:5000}",
            fixedDelayString = "${gis.worker.poll-interval-ms:5000}")
    public void poll() {
        try {
            Optional<GisClaimedTask> task = backendClient.claim();
            if (task.isPresent()) {
                log.info("GIS Worker HTTPS Claim 返回任务，taskId={}，datasetId={}，workerId={}，status={}，stage={}，progress={}",
                        task.get().getTaskId(), task.get().getDatasetId(), task.get().getWorkerId(),
                        task.get().getStatus(), task.get().getStage(), task.get().getProgress());
                taskExecutor.execute(task.get());
            }
        } catch (RuntimeException e) {
            log.error("GIS Worker 轮询 Backend 失败", e);
        }
    }
}
