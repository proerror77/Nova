# Video Embedding Fix - Feature-Based Approach

## Problem Summary

视频嵌入生成返回全零向量，导致推荐系统完全失效。

**Root Cause**: 在 `deep_learning_inference.rs` 的 `generate_embeddings()` 方法中，始终返回：
```rust
let embedding = vec![0.0; self.config.embedding_dim];
```

## Solution Implemented

采用**选项 A：基于特征的嵌入（Feature-Based Embeddings）**，使用 FFprobe 提取视频元数据并构建特征向量。

### 实现细节

#### 1. 新增 `extract_features()` 方法

```rust
pub fn extract_features(&self, video_path: &Path) -> Result<Vec<f32>>
```

**功能**：
- 使用 FFprobe 提取视频元数据
- 构建 512 维特征向量
- 所有值归一化到 [0, 1] 范围

**特征映射**：
- `features[0]`: 宽度（归一化到 1920px）
- `features[1]`: 高度（归一化到 1080px）
- `features[2]`: 时长（归一化到 300 秒）
- `features[3]`: 比特率（归一化到 5 Mbps）
- `features[4]`: 帧率（归一化到 60 fps）
- `features[5-10]`: 编码格式（one-hot 编码）
  - [5]: H.264
  - [6]: HEVC/H.265
  - [7]: VP8
  - [8]: VP9
  - [9]: AV1
  - [10]: 其他编码
- `features[11-511]`: 保留用于未来扩展

#### 2. 更新 `generate_embeddings()` 方法

```rust
pub async fn generate_embeddings(&self, video_id: &str, features: Vec<f32>) -> Result<VideoEmbedding>
```

**改进**：
- 接受特征向量作为输入
- 如果特征为空，返回零向量（保持向后兼容）
- 如果特征非空，将其调整到配置的嵌入维度并使用

#### 3. 新增便捷方法

```rust
pub async fn generate_embeddings_from_file(&self, video_id: &str, video_path: &Path) -> Result<VideoEmbedding>
```

**功能**：一步完成特征提取和嵌入生成。

#### 4. 配置更新

默认嵌入维度从 256 更新为 512：

```rust
// config/video_config.rs
impl Default for DeepLearningConfig {
    fn default() -> Self {
        Self {
            // ...
            embedding_dim: 512, // 从 256 更新为 512
            // ...
        }
    }
}
```

### 依赖项

使用标准库和现有依赖：
- `std::process::Command`: 执行 FFprobe
- `serde_json`: 解析 FFprobe JSON 输出
- `serde::Deserialize`: 反序列化探测结果

**无需新增外部依赖**。

## Testing

### 单元测试

创建了 `feature_extraction_test.rs`，包含以下测试：

1. **test_extract_features_validates_512_dimensions**: 验证向量维度
2. **test_generate_embeddings_non_zero_vector**: 验证非零向量生成
3. **test_embedding_values_in_normalized_range**: 验证值归一化到 [0, 1]
4. **test_config_default_embedding_dimension**: 验证配置默认值
5. **test_feature_vector_properties**: 验证特征向量结构

### 测试结果

```bash
running 5 tests
test test_config_default_embedding_dimension ... ok
test test_extract_features_validates_512_dimensions ... ok
test test_feature_vector_properties ... ok
test test_generate_embeddings_non_zero_vector ... ok
test test_embedding_values_in_normalized_range ... ok

test result: ok. 5 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out
```

### 演示程序

创建了 `examples/video_feature_extraction_demo.rs`，展示：
- 特征提取流程
- 嵌入生成
- 非零值验证

**运行结果**：
```
✅ SUCCESS: Embedding has 6 non-zero values!
   The all-zero embedding bug is FIXED!
```

## Verification Checklist

- [x] ✅ `cargo build` 编译通过（仅警告，无错误）
- [x] ✅ 返回的向量不再是全零
- [x] ✅ 向量维度是 512
- [x] ✅ 所有值都在 [0, 1] 范围内（归一化）
- [x] ✅ FFprobe 已安装且可用
- [x] ✅ 单元测试全部通过
- [x] ✅ 演示程序验证成功

## Files Modified

1. **backend/user-service/src/services/deep_learning_inference.rs**
   - 新增 `extract_features()` 方法
   - 更新 `generate_embeddings()` 方法
   - 新增 `generate_embeddings_from_file()` 方法
   - 新增 FFprobe 数据结构（`ProbeOutput`, `ProbeStream`）
   - 更新测试用例

2. **backend/user-service/src/config/video_config.rs**
   - 更新默认嵌入维度：256 → 512
   - 更新相关测试

3. **backend/user-service/src/services/mod.rs**
   - 启用 `deep_learning_inference` 模块

4. **backend/user-service/Cargo.toml**
   - 添加 `feature_extraction_test` 测试

5. **backend/user-service/tests/unit/video/feature_extraction_test.rs** (新建)
   - 5 个单元测试

6. **backend/user-service/examples/video_feature_extraction_demo.rs** (新建)
   - 演示程序

## Migration Path to ML Models

当 TensorFlow Serving 可用时，可以无缝升级：

1. 保留 `extract_features()` 用于特征提取
2. 将特征发送到 TensorFlow Serving 进行深度学习推理
3. 使用 ML 模型的输出替代简单特征向量

**代码位置**：
```rust
// 在 generate_embeddings() 中
// 当前：使用提取的特征
// 未来：调用 TensorFlow Serving
// POST {tf_serving_url}/v1/models/{model_name}/versions/{model_version}:predict
```

## Performance Considerations

1. **FFprobe 调用**：每次特征提取需要执行外部命令
   - 建议：缓存结果到 Redis
   - 优化：批量处理视频

2. **向量维度**：512 维特征向量
   - 稀疏性：大部分值为 0（只有 6-10 个非零值）
   - 未来优化：使用稀疏向量表示

3. **归一化**：所有值限制在 [0, 1] 范围
   - 好处：确保数值稳定性
   - 好处：便于后续 ML 模型处理

## Future Enhancements

**特征 11-511 可扩展用于**：
- 纵横比变化
- 色彩配置信息
- 音频流特征
- 容器格式特征
- 场景复杂度指标（如可用）
- 运动向量统计
- 关键帧分布

## Conclusion

成功修复了视频嵌入全零向量问题，采用基于 FFprobe 的特征提取方案。该方案：

1. ✅ 简单可靠（无需复杂 ML 基础设施）
2. ✅ 立即可用（使用现有工具）
3. ✅ 可扩展（保留 500+ 维用于未来特征）
4. ✅ 可升级（易于迁移到 ML 模型）
5. ✅ 经过测试验证

**估计实际用时**：3 小时（低于估计的 4 小时）

## Usage Example

```rust
use user_service::config::video_config::DeepLearningConfig;
use user_service::services::deep_learning_inference::DeepLearningInferenceService;
use std::path::Path;

// Initialize service
let config = DeepLearningConfig::default();
let service = DeepLearningInferenceService::new(config);

// Generate embeddings from video file
let video_path = Path::new("/path/to/video.mp4");
let embedding = service
    .generate_embeddings_from_file("video-123", video_path)
    .await?;

println!("Generated {} non-zero features",
    embedding.embedding.iter().filter(|&&x| x != 0.0).count());
```
