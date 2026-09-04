package com.dongming.gis.worker.executor;

import com.dongming.gis.worker.client.GisBackendClient;
import com.dongming.gis.worker.client.dto.GisClaimedTask;
import com.dongming.gis.worker.processor.GisProcessor;
import com.dongming.gis.worker.processor.GisProcessorContext;
import com.dongming.gis.worker.task.GisTaskHeartbeatService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import java.util.List;

/**
 * GIS 任务执行器，集中管理心跳、处理和终态上报。
 */
@Service
public class GisTaskExecutor {

    private static final Logger log = LoggerFactory.getLogger(GisTaskExecutor.class);

    private final GisBackendClient backendClient;
    private final GisTaskHeartbeatService heartbeatService;
    private final List<GisProcessor> processors;

    public GisTaskExecutor(GisBackendClient backendClient,
                           GisTaskHeartbeatService heartbeatService,
                           List<GisProcessor> processors) {
        this.backendClient = backendClient;
        this.heartbeatService = heartbeatService;
        this.processors = processors;
    }

    public void execute(GisClaimedTask task) {
        GisTaskHeartbeatService.HeartbeatHandle heartbeat = heartbeatService.start(
                task, Thread.currentThread());
        log.info("GIS 任务开始执行，taskId={}，datasetId={}，workerId={}",
                task.getTaskId(), task.getDatasetId(), task.getWorkerId());

        try {
            GisProcessor processor = findProcessor(task);
            processor.process(new GisProcessorContext(task, backendClient));
            if (!backendClient.markSucceeded(task, null)) {
                throw new LostTaskOwnershipException(task.getTaskId());
            }
            log.info("GIS 任务执行成功，taskId={}，datasetId={}，workerId={}",
                    task.getTaskId(), task.getDatasetId(), task.getWorkerId());
        } catch (LostTaskOwnershipException e) {
            log.warn("GIS 任务已停止，旧 Worker 不再更新状态，taskId={}，datasetId={}，workerId={}",
                    task.getTaskId(), task.getDatasetId(), task.getWorkerId());
        } catch (InterruptedException e) {
            if (heartbeat.isOwnershipLost()) {
                log.warn("GIS 任务因失去所有权被中断，taskId={}，datasetId={}，workerId={}",
                        task.getTaskId(), task.getDatasetId(), task.getWorkerId());
            } else {
                markFailed(task, "WORKER_INTERRUPTED", "Worker 执行线程被中断", true);
                Thread.currentThread().interrupt();
            }
        } catch (UnsupportedProcessorException e) {
            markFailed(task, "UNSUPPORTED_PROCESSOR", e.getMessage(), false);
        } catch (Exception e) {
            log.error("GIS 任务执行异常，taskId={}，datasetId={}，workerId={}",
                    task.getTaskId(), task.getDatasetId(), task.getWorkerId(), e);
            markFailed(task, "PROCESSOR_ERROR", safeMessage(e), true);
        } finally {
            heartbeat.close();
        }
    }

    private GisProcessor findProcessor(GisClaimedTask task) {
        return processors.stream()
                .filter(processor -> processor.supports(task.getTaskType(), task.getProcessor(),
                        task.getProcessorVersion()))
                .findFirst()
                .orElseThrow(() -> new UnsupportedProcessorException(
                        "不支持的处理器：" + task.getTaskType() + "/" + task.getProcessor()
                                + "/" + task.getProcessorVersion()));
    }

    private void markFailed(GisClaimedTask task, String errorCode, String errorMessage,
                            boolean retryable) {
        boolean updated = backendClient.markFailed(task, errorCode,
                truncate(errorMessage, 2000), retryable);
        if (!updated) {
            log.warn("GIS 任务失败状态更新被拒绝，当前 Worker 已无所有权，taskId={}，datasetId={}，workerId={}",
                    task.getTaskId(), task.getDatasetId(), task.getWorkerId());
        } else {
            log.error("GIS 任务已记录失败，taskId={}，datasetId={}，workerId={}，errorCode={}，retryable={}",
                    task.getTaskId(), task.getDatasetId(), task.getWorkerId(), errorCode,
                    retryable);
        }
    }

    private String safeMessage(Exception e) {
        return e.getMessage() == null ? e.getClass().getSimpleName() : e.getMessage();
    }

    private String truncate(String value, int maxLength) {
        if (value == null || value.length() <= maxLength) {
            return value;
        }
        return value.substring(0, maxLength);
    }

    private static final class UnsupportedProcessorException extends RuntimeException {

        private UnsupportedProcessorException(String message) {
            super(message);
        }
    }
}
