package com.dongming.gis.worker.task;

import com.dongming.gis.worker.client.GisBackendClient;
import com.dongming.gis.worker.client.dto.GisClaimedTask;
import com.dongming.gis.worker.config.GisWorkerProperties;
import org.junit.jupiter.api.Test;

import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

/**
 * 验证心跳更新为 0 时会停止当前处理线程。
 */
class GisTaskHeartbeatServiceTest {

    @Test
    void ownershipLossInterruptsProcessorThread() throws Exception {
        GisBackendClient backendClient = mock(GisBackendClient.class);
        GisClaimedTask task = new GisClaimedTask();
        task.setTaskId(30002L);
        task.setDatasetId(100L);
        task.setWorkerId("worker-a");
        task.setClaimToken("token-a");
        when(backendClient.heartbeat(task)).thenReturn(false);
        GisWorkerProperties properties = new GisWorkerProperties();
        properties.setHeartbeatIntervalSeconds(1);
        GisTaskHeartbeatService service = new GisTaskHeartbeatService(backendClient, properties);
        AtomicBoolean interrupted = new AtomicBoolean(false);
        Thread processorThread = new Thread(() -> {
            try {
                TimeUnit.SECONDS.sleep(5);
            } catch (InterruptedException e) {
                interrupted.set(true);
            }
        }, "sleep-processor-test");

        GisTaskHeartbeatService.HeartbeatHandle handle = service.start(task, processorThread);
        try {
            processorThread.start();
            processorThread.join(3000L);
            assertFalse(processorThread.isAlive());
            assertTrue(interrupted.get());
            assertTrue(handle.isOwnershipLost());
        } finally {
            handle.close();
            service.shutdown();
        }
    }
}
