package com.dongming.gis.worker.processor;

import com.dongming.gis.worker.config.GisWorkerProperties;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

import java.util.concurrent.TimeUnit;

/**
 * Phase 1 开发处理器，用固定节奏模拟 GIS 长任务。
 */
@Component
public class SleepProcessor implements GisProcessor {

    private static final Logger log = LoggerFactory.getLogger(SleepProcessor.class);

    private final GisWorkerProperties properties;

    public SleepProcessor(GisWorkerProperties properties) {
        this.properties = properties;
    }

    @Override
    public boolean supports(String taskType, String processor, String processorVersion) {
        return "BUILD_3DTILES".equals(taskType)
                && "sleep".equals(processor)
                && "v1".equals(processorVersion);
    }

    @Override
    public void process(GisProcessorContext context) throws InterruptedException {
        for (int step = 1; step <= 10; step++) {
            TimeUnit.SECONDS.sleep(properties.getSleepStepSeconds());
            int progress = step * 10;
            String stage = stageFor(progress);
            context.updateProgress(stage, progress);
            log.info("SleepProcessor 进度已更新，taskId={}，datasetId={}，workerId={}，stage={}，progress={}",
                    context.getTask().getTaskId(), context.getTask().getDatasetId(),
                    context.getTask().getWorkerId(), stage, progress);
        }
    }

    private String stageFor(int progress) {
        if (progress <= 10) {
            return "VALIDATING";
        }
        if (progress <= 20) {
            return "DOWNLOADING";
        }
        if (progress <= 30) {
            return "EXTRACTING";
        }
        if (progress <= 40) {
            return "NORMALIZING";
        }
        if (progress <= 80) {
            return "CONVERTING";
        }
        if (progress <= 90) {
            return "VERIFYING";
        }
        return "CLEANING";
    }
}
