package com.dongming.gis.worker.config;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.web.client.RestTemplate;

/**
 * Worker 运行期公共对象。
 */
@Configuration
public class WorkerRuntimeConfig {

    @Bean
    public WorkerIdentity workerIdentity(GisWorkerProperties properties) {
        return new WorkerIdentity(properties.getId());
    }

    @Bean
    public RestTemplate gisRestTemplate(GisBackendProperties properties) {
        SimpleClientHttpRequestFactory requestFactory = new SimpleClientHttpRequestFactory();
        requestFactory.setConnectTimeout(properties.getConnectTimeoutMs());
        requestFactory.setReadTimeout(properties.getReadTimeoutMs());
        return new RestTemplate(requestFactory);
    }
}
