#!/usr/bin/env python3
"""
测试覆盖率报告生成器

功能：
1. 解析 Xcode 覆盖率 JSON 数据
2. 生成可读的 HTML 报告
3. 识别未覆盖的代码区域
4. 提供改进建议
"""

import json
import sys
import os
from datetime import datetime

def parse_coverage_json(json_path):
    """解析覆盖率 JSON 文件"""
    with open(json_path, 'r') as f:
        return json.load(f)

def calculate_total_coverage(data):
    """计算总体覆盖率"""
    total_lines = 0
    covered_lines = 0

    for target in data.get('targets', []):
        for file in target.get('files', []):
            total_lines += file.get('executableLines', 0)
            covered_lines += file.get('coveredLines', 0)

    if total_lines == 0:
        return 0.0

    return (covered_lines / total_lines) * 100

def get_file_coverage(data):
    """获取每个文件的覆盖率"""
    file_coverage = []

    for target in data.get('targets', []):
        for file in target.get('files', []):
            total = file.get('executableLines', 0)
            covered = file.get('coveredLines', 0)

            if total > 0:
                percentage = (covered / total) * 100
                file_coverage.append({
                    'name': file.get('name', 'Unknown'),
                    'path': file.get('path', ''),
                    'total': total,
                    'covered': covered,
                    'percentage': percentage
                })

    return sorted(file_coverage, key=lambda x: x['percentage'])

def generate_html_report(coverage_data, output_path):
    """生成 HTML 报告"""
    total_coverage = calculate_total_coverage(coverage_data)
    file_coverage = get_file_coverage(coverage_data)

    # 分类文件
    low_coverage = [f for f in file_coverage if f['percentage'] < 50]
    medium_coverage = [f for f in file_coverage if 50 <= f['percentage'] < 80]
    high_coverage = [f for f in file_coverage if f['percentage'] >= 80]

    html = f"""
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Test Coverage Report - NovaSocial iOS</title>
    <style>
        * {{
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }}

        body {{
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            padding: 20px;
            color: #333;
        }}

        .container {{
            max-width: 1200px;
            margin: 0 auto;
            background: white;
            border-radius: 12px;
            padding: 40px;
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
        }}

        h1 {{
            font-size: 2.5em;
            margin-bottom: 10px;
            color: #667eea;
        }}

        .timestamp {{
            color: #999;
            margin-bottom: 30px;
        }}

        .summary {{
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 30px;
            border-radius: 12px;
            margin-bottom: 30px;
        }}

        .coverage-percentage {{
            font-size: 4em;
            font-weight: bold;
            margin: 20px 0;
        }}

        .stats {{
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }}

        .stat-card {{
            background: #f8f9fa;
            padding: 20px;
            border-radius: 8px;
            border-left: 4px solid #667eea;
        }}

        .stat-label {{
            color: #666;
            font-size: 0.9em;
            margin-bottom: 5px;
        }}

        .stat-value {{
            font-size: 2em;
            font-weight: bold;
            color: #333;
        }}

        .section {{
            margin-bottom: 40px;
        }}

        .section-title {{
            font-size: 1.5em;
            margin-bottom: 20px;
            color: #333;
            border-bottom: 2px solid #667eea;
            padding-bottom: 10px;
        }}

        .file-list {{
            list-style: none;
        }}

        .file-item {{
            background: #f8f9fa;
            margin-bottom: 10px;
            padding: 15px;
            border-radius: 8px;
            display: flex;
            justify-content: space-between;
            align-items: center;
        }}

        .file-name {{
            font-weight: 500;
            flex: 1;
        }}

        .file-stats {{
            display: flex;
            gap: 20px;
            align-items: center;
        }}

        .coverage-bar {{
            width: 200px;
            height: 20px;
            background: #e0e0e0;
            border-radius: 10px;
            overflow: hidden;
        }}

        .coverage-fill {{
            height: 100%;
            background: linear-gradient(90deg, #667eea 0%, #764ba2 100%);
            transition: width 0.3s ease;
        }}

        .coverage-fill.low {{
            background: linear-gradient(90deg, #f093fb 0%, #f5576c 100%);
        }}

        .coverage-fill.medium {{
            background: linear-gradient(90deg, #ffd89b 0%, #19547b 100%);
        }}

        .percentage {{
            font-weight: bold;
            min-width: 60px;
            text-align: right;
        }}

        .low {{ color: #f5576c; }}
        .medium {{ color: #ff9800; }}
        .high {{ color: #4caf50; }}

        .recommendations {{
            background: #fff3cd;
            border-left: 4px solid #ffc107;
            padding: 20px;
            border-radius: 8px;
            margin-top: 30px;
        }}

        .recommendations h3 {{
            color: #856404;
            margin-bottom: 15px;
        }}

        .recommendations ul {{
            margin-left: 20px;
        }}

        .recommendations li {{
            margin-bottom: 10px;
            color: #856404;
        }}
    </style>
</head>
<body>
    <div class="container">
        <h1>🧪 Test Coverage Report</h1>
        <div class="timestamp">Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}</div>

        <div class="summary">
            <h2>Overall Coverage</h2>
            <div class="coverage-percentage">{total_coverage:.1f}%</div>
            <p>Total executable lines covered by tests</p>
        </div>

        <div class="stats">
            <div class="stat-card">
                <div class="stat-label">Total Files</div>
                <div class="stat-value">{len(file_coverage)}</div>
            </div>
            <div class="stat-card">
                <div class="stat-label">High Coverage (≥80%)</div>
                <div class="stat-value high">{len(high_coverage)}</div>
            </div>
            <div class="stat-card">
                <div class="stat-label">Medium Coverage (50-79%)</div>
                <div class="stat-value medium">{len(medium_coverage)}</div>
            </div>
            <div class="stat-card">
                <div class="stat-label">Low Coverage (<50%)</div>
                <div class="stat-value low">{len(low_coverage)}</div>
            </div>
        </div>
"""

    # 低覆盖率文件
    if low_coverage:
        html += """
        <div class="section">
            <h2 class="section-title">⚠️ Low Coverage Files (Need Attention)</h2>
            <ul class="file-list">
"""
        for file in low_coverage:
            html += f"""
                <li class="file-item">
                    <div class="file-name">{file['name']}</div>
                    <div class="file-stats">
                        <div class="coverage-bar">
                            <div class="coverage-fill low" style="width: {file['percentage']:.0f}%"></div>
                        </div>
                        <span class="percentage low">{file['percentage']:.1f}%</span>
                    </div>
                </li>
"""
        html += """
            </ul>
        </div>
"""

    # 中等覆盖率文件
    if medium_coverage:
        html += """
        <div class="section">
            <h2 class="section-title">⚡ Medium Coverage Files</h2>
            <ul class="file-list">
"""
        for file in medium_coverage[:10]:  # 只显示前10个
            html += f"""
                <li class="file-item">
                    <div class="file-name">{file['name']}</div>
                    <div class="file-stats">
                        <div class="coverage-bar">
                            <div class="coverage-fill medium" style="width: {file['percentage']:.0f}%"></div>
                        </div>
                        <span class="percentage medium">{file['percentage']:.1f}%</span>
                    </div>
                </li>
"""
        html += """
            </ul>
        </div>
"""

    # 高覆盖率文件
    if high_coverage:
        html += """
        <div class="section">
            <h2 class="section-title">✅ High Coverage Files (Well Tested)</h2>
            <ul class="file-list">
"""
        for file in high_coverage[-10:]:  # 显示最后10个（最高的）
            html += f"""
                <li class="file-item">
                    <div class="file-name">{file['name']}</div>
                    <div class="file-stats">
                        <div class="coverage-bar">
                            <div class="coverage-fill high" style="width: {file['percentage']:.0f}%"></div>
                        </div>
                        <span class="percentage high">{file['percentage']:.1f}%</span>
                    </div>
                </li>
"""
        html += """
            </ul>
        </div>
"""

    # 建议
    html += """
        <div class="recommendations">
            <h3>📋 Recommendations</h3>
            <ul>
"""

    if total_coverage < 70:
        html += """
                <li><strong>Overall coverage is below 70%.</strong> Focus on adding tests for core business logic.</li>
"""

    if len(low_coverage) > 5:
        html += f"""
                <li><strong>{len(low_coverage)} files have low coverage.</strong> Prioritize testing these critical paths.</li>
"""

    html += """
                <li>Add unit tests for all Repository methods.</li>
                <li>Implement integration tests for complete user flows.</li>
                <li>Add concurrency and thread safety tests.</li>
                <li>Test error handling and retry mechanisms thoroughly.</li>
                <li>Run tests with Thread Sanitizer to detect race conditions.</li>
            </ul>
        </div>
    </div>
</body>
</html>
"""

    with open(output_path, 'w') as f:
        f.write(html)

    print(f"✅ HTML report generated: {output_path}")

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 generate_coverage_report.py <coverage.json>")
        sys.exit(1)

    json_path = sys.argv[1]

    if not os.path.exists(json_path):
        print(f"❌ Coverage file not found: {json_path}")
        sys.exit(1)

    # 解析数据
    coverage_data = parse_coverage_json(json_path)

    # 生成报告
    output_path = os.path.join(os.path.dirname(json_path), 'coverage_report.html')
    generate_html_report(coverage_data, output_path)

    # 打印总结
    total_coverage = calculate_total_coverage(coverage_data)
    print(f"\n📊 Overall Coverage: {total_coverage:.1f}%")

    if total_coverage >= 80:
        print("✅ Excellent coverage!")
    elif total_coverage >= 60:
        print("⚠️  Good coverage, but room for improvement")
    else:
        print("❌ Low coverage - need more tests")

if __name__ == '__main__':
    main()
