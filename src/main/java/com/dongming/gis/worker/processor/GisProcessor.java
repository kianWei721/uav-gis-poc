package com.dongming.gis.worker.processor;

/**
 * GIS 处理器统一接口。
 */
public interface GisProcessor {

    boolean supports(String taskType, String processor, String processorVersion);

    void process(GisProcessorContext context) throws Exception;
}
