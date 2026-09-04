package com.dongming.gis.worker.executor;

/**
 * 当前 Worker 已失去任务所有权。
 */
public class LostTaskOwnershipException extends RuntimeException {

    public LostTaskOwnershipException(Long taskId) {
        super("GIS 任务所有权已失效，taskId=" + taskId);
    }
}
