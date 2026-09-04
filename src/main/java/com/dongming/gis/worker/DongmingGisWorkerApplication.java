package com.dongming.gis.worker;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.scheduling.annotation.EnableScheduling;

/**
 * 东明无人机 GIS 独立处理 Worker 入口。
 */
@EnableScheduling
@SpringBootApplication
public class DongmingGisWorkerApplication {

    public static void main(String[] args) {
        SpringApplication application = new SpringApplication(DongmingGisWorkerApplication.class);
        application.run(args);
    }
}
