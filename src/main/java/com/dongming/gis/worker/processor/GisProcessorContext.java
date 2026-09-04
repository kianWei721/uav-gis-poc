package com.dongming.gis.worker.processor;

import com.dongming.gis.worker.client.GisBackendClient;
import com.dongming.gis.worker.client.dto.GisClaimedTask;
import com.dongming.gis.worker.executor.LostTaskOwnershipException;

/**
 * 处理器运行上下文，进度更新统一经过所有权条件校验。
 */
public class GisProcessorContext {

    private final GisClaimedTask task;
    private final GisBackendClient backendClient;

    public GisProcessorContext(GisClaimedTask task, GisBackendClient backendClient) {
        this.task = task;
        this.backendClient = backendClient;
    }

    public GisClaimedTask getTask() {
        return task;
    }

    public void updateProgress(String stage, int progress) {
        if (progress < 0 || progress > 100) {
            throw new IllegalArgumentException("GIS 任务进度必须在 0 到 100 之间");
        }
        if (!backendClient.reportProgress(task, stage, progress)) {
            throw new LostTaskOwnershipException(task.getTaskId());
        }
    }
}
