#!/usr/bin/env node

const http = require('http');
const https = require('https');
const url = require('url');

// API 目標配置 - 通過環境變數 PROXY_TARGET 控制
// 可用選項: api.nova.app (生產/遠程), localhost:8001 (本地 Staging Docker)
const PROXY_TARGET = process.env.PROXY_TARGET || 'api.nova.app';

// 解析目標
let TARGET_HOST, TARGET_PROTOCOL, TARGET_PORT;

if (PROXY_TARGET === 'localhost' || PROXY_TARGET.startsWith('localhost:')) {
    // 本地 Staging Docker 環境 (HTTP)
    TARGET_HOST = 'localhost';
    TARGET_PORT = 8001;
    TARGET_PROTOCOL = 'http:';
} else if (PROXY_TARGET.includes(':')) {
    // 自訂主機:端口
    const parts = PROXY_TARGET.split(':');
    TARGET_HOST = parts[0];
    TARGET_PORT = parseInt(parts[1], 10);
    TARGET_PROTOCOL = 'https:';
} else {
    // 遠程 API (HTTPS)
    TARGET_HOST = PROXY_TARGET;
    TARGET_PORT = 443;
    TARGET_PROTOCOL = 'https:';
}

const PROXY_PORT = 8080;

// 颜色输出
const colors = {
    reset: '\x1b[0m',
    green: '\x1b[32m',
    yellow: '\x1b[33m',
    cyan: '\x1b[36m',
    red: '\x1b[31m'
};

// 日志函数
function log(level, message) {
    const timestamp = new Date().toLocaleTimeString();
    const levelColor = {
        info: colors.cyan,
        success: colors.green,
        warn: colors.yellow,
        error: colors.red
    }[level] || colors.reset;

    console.log(`${levelColor}[${timestamp}] ${level.toUpperCase()}${colors.reset} ${message}`);
}

// 创建 HTTP 代理服务器
const server = http.createServer((req, res) => {
    const requestId = Math.random().toString(36).substring(7);

    log('info', `${requestId} ${req.method} ${req.url}`);

    // 设置 CORS 头允许所有来源
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, PATCH, OPTIONS');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization, X-Requested-With');
    res.setHeader('Access-Control-Max-Age', '86400');

    // 处理 OPTIONS 请求
    if (req.method === 'OPTIONS') {
        res.writeHead(200);
        res.end();
        log('info', `${requestId} OPTIONS request handled`);
        return;
    }

    // 构建目标 URL
    const parsedUrl = url.parse(TARGET_PROTOCOL + '//' + TARGET_HOST + req.url);

    const options = {
        hostname: TARGET_HOST,
        port: TARGET_PORT,
        path: req.url,
        method: req.method,
        headers: req.headers,
        rejectUnauthorized: false  // 允許自簽證書或無效證書
    };

    // 移除 Host 头以避免冲突
    delete options.headers['host'];

    // 根據協議選擇 HTTP 或 HTTPS
    const protocol = TARGET_PROTOCOL === 'http:' ? require('http') : require('https');

    // 發送代理請求
    const proxyReq = protocol.request(options, (proxyRes) => {
        log('info', `${requestId} Response: ${proxyRes.statusCode}`);

        // 轉發狀態碼和響應頭
        res.writeHead(proxyRes.statusCode, proxyRes.headers);

        // 轉發響應體
        proxyRes.pipe(res);
    });

    // 错误处理
    proxyReq.on('error', (err) => {
        log('error', `${requestId} Proxy request error: ${err.message}`);
        res.writeHead(502, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({
            error: 'Bad Gateway',
            message: err.message,
            targetHost: TARGET_HOST
        }));
    });

    proxyReq.on('timeout', () => {
        log('warn', `${requestId} Request timeout`);
        proxyReq.destroy();
    });

    // 转发请求体
    req.pipe(proxyReq);
});

// 错误处理
server.on('error', (err) => {
    if (err.code === 'EADDRINUSE') {
        log('error', `Port ${PROXY_PORT} 已被占用！`);
        process.exit(1);
    } else {
        log('error', `Server error: ${err.message}`);
        process.exit(1);
    }
});

// 啟動服務器
server.listen(PROXY_PORT, '0.0.0.0', () => {
    const targetUrl = `${TARGET_PROTOCOL}//${TARGET_HOST}${TARGET_PORT !== (TARGET_PROTOCOL === 'https:' ? 443 : 80) ? ':' + TARGET_PORT : ''}`;

    log('success', `✅ 代理服務器已啟動！`);
    log('info', `📍 本地地址: http://localhost:${PROXY_PORT}`);
    log('info', `🎯 目標: ${targetUrl}`);
    log('info', ``);

    if (TARGET_HOST === 'localhost') {
        log('info', `⚠️  目標是本地 Staging Docker 環境`);
        log('info', `   確保 Docker 已啟動: ./scripts/start-staging.sh`);
    } else {
        log('info', `🌐 目標是遠程 API: ${TARGET_HOST}`);
    }

    log('info', ``);
    log('info', `在模擬器中運行應用時，使用環境變數: API_ENV=stagingProxy`);
    log('info', ``);
    log('info', `或在 Xcode 中配置:`);
    log('info', `  Product → Scheme → Edit Scheme → Run → Arguments → Environment Variables`);
    log('info', `  添加: API_ENV = stagingProxy`);
    log('info', ``);
    log('info', `按 Ctrl+C 停止代理服務器`);
});

// 优雅关闭
process.on('SIGINT', () => {
    log('warn', `\n正在关闭代理服务器...`);
    server.close(() => {
        log('success', `✅ 代理服务器已停止`);
        process.exit(0);
    });
});
