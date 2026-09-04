package com.dongming.gis.worker.client;

import com.dongming.gis.worker.client.dto.GisClaimedTask;
import com.dongming.gis.worker.config.GisBackendProperties;
import com.dongming.gis.worker.config.WorkerIdentity;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Service;
import org.springframework.util.StringUtils;
import org.springframework.web.client.HttpClientErrorException;
import org.springframework.web.client.RestTemplate;

import java.util.HashMap;
import java.util.Map;
import java.util.Optional;

/**
 * GIS Worker 调用东明 Backend Internal API 的客户端。
 */
@Service
public class GisBackendClient {

    private static final String INTERNAL_PATH = "/api/internal/gis-worker";

    private final RestTemplate restTemplate;
    private final GisBackendProperties properties;
    private final WorkerIdentity workerIdentity;
    private final String baseUrl;

    public GisBackendClient(RestTemplate restTemplate, GisBackendProperties properties,
                            WorkerIdentity workerIdentity) {
        this.restTemplate = restTemplate;
        this.properties = properties;
        this.workerIdentity = workerIdentity;
        if (!StringUtils.hasText(properties.getBaseUrl())) {
            throw new IllegalStateException("GIS_BACKEND_BASE_URL 未配置");
        }
        if (!StringUtils.hasText(properties.getWorkerToken())) {
            throw new IllegalStateException("GIS_WORKER_TOKEN 未配置");
        }
        this.baseUrl = trimTrailingSlash(properties.getBaseUrl());
    }

    public Optional<GisClaimedTask> claim() {
        ResponseEntity<GisClaimedTask> response = restTemplate.exchange(
                url("/tasks/claim"), HttpMethod.POST, new HttpEntity<>(headers()),
                GisClaimedTask.class);
        if (response.getStatusCode() == HttpStatus.NO_CONTENT || response.getBody() == null) {
            return Optional.empty();
        }
        return Optional.of(response.getBody());
    }

    public boolean heartbeat(GisClaimedTask task) {
        return postOwnedUpdate(task, "/heartbeat", ownedBody(task));
    }

    public boolean reportProgress(GisClaimedTask task, String stage, int progress) {
        Map<String, Object> body = ownedBody(task);
        body.put("stage", stage);
        body.put("progress", progress);
        return postOwnedUpdate(task, "/progress", body);
    }

    public boolean markSucceeded(GisClaimedTask task, Long outputBytes) {
        Map<String, Object> body = ownedBody(task);
        body.put("outputBytes", outputBytes);
        return postOwnedUpdate(task, "/success", body);
    }

    public boolean markFailed(GisClaimedTask task, String errorCode, String errorMessage,
                              boolean retryable) {
        Map<String, Object> body = ownedBody(task);
        body.put("errorCode", errorCode);
        body.put("errorMessage", errorMessage);
        body.put("retryable", retryable);
        return postOwnedUpdate(task, "/failure", body);
    }

    public boolean health() {
        ResponseEntity<Map> response = restTemplate.exchange(
                url("/health"), HttpMethod.GET, new HttpEntity<>(headers()), Map.class);
        return response.getStatusCode().is2xxSuccessful();
    }

    private boolean postOwnedUpdate(GisClaimedTask task, String operation,
                                    Map<String, Object> body) {
        try {
            ResponseEntity<Void> response = restTemplate.exchange(
                    url("/tasks/" + task.getTaskId() + operation), HttpMethod.POST,
                    new HttpEntity<>(body, headers()), Void.class);
            return response.getStatusCode().is2xxSuccessful();
        } catch (HttpClientErrorException e) {
            if (e.getStatusCode() == HttpStatus.CONFLICT) {
                return false;
            }
            throw e;
        }
    }

    private Map<String, Object> ownedBody(GisClaimedTask task) {
        Map<String, Object> body = new HashMap<>();
        body.put("claimToken", task.getClaimToken());
        return body;
    }

    private HttpHeaders headers() {
        HttpHeaders headers = new HttpHeaders();
        headers.setContentType(MediaType.APPLICATION_JSON);
        headers.set("X-GIS-Worker-Id", workerIdentity.getValue());
        headers.set("X-GIS-Worker-Token", properties.getWorkerToken());
        return headers;
    }

    private String url(String path) {
        return baseUrl + INTERNAL_PATH + path;
    }

    private String trimTrailingSlash(String value) {
        String result = value.trim();
        while (result.endsWith("/")) {
            result = result.substring(0, result.length() - 1);
        }
        return result;
    }
}
