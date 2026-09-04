package com.dongming.gis.worker.processor;

import com.dongming.gis.worker.client.GisBackendClient;
import com.dongming.gis.worker.client.dto.GisClaimedTask;
import com.dongming.gis.worker.config.GisWorkerProperties;
import org.junit.jupiter.api.Test;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * 验证 SleepProcessor 按 10 个步骤更新进度。
 */
class SleepProcessorTest {

    @Test
    void updatesProgressFromTenToOneHundred() throws Exception {
        GisWorkerProperties properties = new GisWorkerProperties();
        properties.setSleepStepSeconds(0);
        GisBackendClient backendClient = mock(GisBackendClient.class);
        when(backendClient.reportProgress(any(GisClaimedTask.class), anyString(), anyInt()))
                .thenReturn(true);

        GisClaimedTask task = new GisClaimedTask();
        task.setTaskId(30002L);
        task.setDatasetId(100L);
        task.setWorkerId("worker-a");
        task.setClaimToken("token-a");

        new SleepProcessor(properties).process(new GisProcessorContext(task, backendClient));

        verify(backendClient, times(10))
                .reportProgress(eq(task), anyString(), anyInt());
        verify(backendClient).reportProgress(task, "VALIDATING", 10);
        verify(backendClient).reportProgress(task, "CLEANING", 100);
    }
}
