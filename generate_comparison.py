#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
HLS Track 2025 - 报告解析与对比生成脚本
从 csynth.xml 提取时钟信息，从 hls_cosim.rpt 提取延迟，从 export_impl.rpt 提取资源使用
"""

import os
import re
import xml.etree.ElementTree as ET
from pathlib import Path

# 项目根目录
PROJECT_ROOT = Path(__file__).parent

# Baseline 数据（来自评分细则）
BASELINE = {
    'SHA-256': {
        'target_clock': 15.0,
        'estimated_clock': 13.846,
        'latency': 809,
        'execution_time': 11201.4,
        'slack_status': 'Pass'
    },
    'LZ4 Compress': {
        'target_clock': 15.0,
        'estimated_clock': 13.220,
        'latency': 3390,
        'execution_time': 44815.8,
        'slack_status': 'Pass'
    },
    'Cholesky': {
        'target_clock': 7.0,
        'estimated_clock': 6.276,
        'latency': 4919,
        'execution_time': 30871.6,
        'slack_status': 'Pass'
    }
}


def parse_csynth_xml(xml_path):
    """从 csynth.xml 提取时钟信息"""
    try:
        tree = ET.parse(xml_path)
        root = tree.getroot()
        
        target_clock = None
        estimated_clock = None
        uncertainty = None
        
        # 1. 从 UserAssignments 提取 Target 和 Uncertainty
        user_assignments = root.find('.//UserAssignments')
        if user_assignments is not None:
            target_elem = user_assignments.find('TargetClockPeriod')
            uncertainty_elem = user_assignments.find('ClockUncertainty')
            if target_elem is not None:
                target_clock = float(target_elem.text)
            if uncertainty_elem is not None:
                uncertainty = float(uncertainty_elem.text)
        
        # 2. 从 PerformanceEstimates/SummaryOfTimingAnalysis 提取 Estimated
        timing_analysis = root.find('.//PerformanceEstimates/SummaryOfTimingAnalysis')
        if timing_analysis is not None:
            estimated_elem = timing_analysis.find('EstimatedClockPeriod')
            if estimated_elem is not None:
                estimated_clock = float(estimated_elem.text)
        
        # 如果成功提取了主要信息
        if target_clock and estimated_clock:
            if uncertainty is None:
                uncertainty = target_clock * 0.1  # 默认 10%
            return {
                'target_clock': target_clock,
                'estimated_clock': estimated_clock,
                'uncertainty': uncertainty
            }
        
        # 备用：查找旧版本格式
        timing = root.find('.//PerformanceEstimates/Timing')
        if timing is not None:
            summary = timing.find('Summary')
            if summary is not None:
                for clock_entry in summary.findall('Clock'):
                    target_clock = float(clock_entry.get('target', '0'))
                    estimated_clock = float(clock_entry.get('estimated', '0'))
                    uncertainty = float(clock_entry.get('uncertainty', '0'))
                    
                    if target_clock > 0 and estimated_clock > 0:
                        return {
                            'target_clock': target_clock,
                            'estimated_clock': estimated_clock,
                            'uncertainty': uncertainty
                        }
    except Exception as e:
        print(f"  ⚠️  解析 {xml_path} 失败: {e}")
    return None


def parse_cosim_rpt(rpt_path):
    """从 hls_cosim.rpt 提取 Latency 和 Total Execution Time"""
    try:
        with open(rpt_path, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
        
        # 查找 Verilog 行，格式有两种：
        # 1. 带 Total Execution Time (Cholesky):
        #    |   Verilog|      Pass|   414|   414|   414|   415|   415|   415|  3319|
        # 2. Interval 为 NA (SHA-256, LZ4):
        #    |   Verilog|      Pass|   800|   800|   800|    NA|    NA|    NA|   800|
        
        # 先尝试匹配包含数字的完整格式
        pattern_full = r'\|\s*Verilog\s*\|\s*\w+\s*\|\s*(\d+)\s*\|\s*(\d+)\s*\|\s*(\d+)\s*\|\s*(\d+)\s*\|\s*(\d+)\s*\|\s*(\d+)\s*\|\s*(\d+)\s*\|'
        match = re.search(pattern_full, content)
        
        if match:
            # 有 Total Execution Time 的格式
            latency_min = int(match.group(1))
            latency_avg = int(match.group(2))
            latency_max = int(match.group(3))
            interval_min = int(match.group(4))
            interval_avg = int(match.group(5))
            interval_max = int(match.group(6))
            total_exec_time = int(match.group(7))
            
            # 优先使用 Total Execution Time
            return {
                'latency': total_exec_time if total_exec_time > 0 else latency_max,
                'latency_max': latency_max,
                'total_exec_time': total_exec_time
            }
        
        # 尝试匹配 Interval 为 NA 的格式
        pattern_na = r'\|\s*Verilog\s*\|\s*\w+\s*\|\s*(\d+)\s*\|\s*(\d+)\s*\|\s*(\d+)\s*\|\s*NA\s*\|\s*NA\s*\|\s*NA\s*\|\s*(\d+)\s*\|'
        match = re.search(pattern_na, content)
        
        if match:
            latency_min = int(match.group(1))
            latency_avg = int(match.group(2))
            latency_max = int(match.group(3))
            total_exec_time = int(match.group(4))
            
            # 这种情况 Total Execution Time 就是 latency_max
            return {
                'latency': latency_max,
                'latency_max': latency_max,
                'total_exec_time': total_exec_time
            }
            
    except Exception as e:
        print(f"  ⚠️  解析 {rpt_path} 失败: {e}")
    return None


def parse_impl_rpt(rpt_path):
    """从 export_impl.rpt 提取资源使用信息"""
    try:
        with open(rpt_path, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
        
        resources = {}
        
        # XC7Z020 资源总量
        XC7Z020_RESOURCES = {
            'LUT': 53200,
            'FF': 106400,
            'BRAM': 140,  # RAMB18
            'DSP': 220
        }
        
        # 查找 Place & Route Resource Summary 部分的资源使用
        # 格式：
        # LUT:              7189
        # FF:               10194
        # DSP:              0
        # BRAM:             75
        
        lut_match = re.search(r'^LUT:\s+(\d+)', content, re.MULTILINE)
        if lut_match:
            used = int(lut_match.group(1))
            available = XC7Z020_RESOURCES['LUT']
            utilization = (used / available) * 100
            resources['LUT'] = {
                'used': used,
                'available': available,
                'utilization': utilization
            }
        
        ff_match = re.search(r'^FF:\s+(\d+)', content, re.MULTILINE)
        if ff_match:
            used = int(ff_match.group(1))
            available = XC7Z020_RESOURCES['FF']
            utilization = (used / available) * 100
            resources['FF'] = {
                'used': used,
                'available': available,
                'utilization': utilization
            }
        
        bram_match = re.search(r'^BRAM:\s+(\d+)', content, re.MULTILINE)
        if bram_match:
            used = int(bram_match.group(1))
            available = XC7Z020_RESOURCES['BRAM']
            utilization = (used / available) * 100
            resources['BRAM'] = {
                'used': used,
                'available': available,
                'utilization': utilization
            }
        
        dsp_match = re.search(r'^DSP:\s+(\d+)', content, re.MULTILINE)
        if dsp_match:
            used = int(dsp_match.group(1))
            available = XC7Z020_RESOURCES['DSP']
            utilization = (used / available) * 100 if available > 0 else 0
            resources['DSP'] = {
                'used': used,
                'available': available,
                'utilization': utilization
            }
        
        return resources if resources else None
    except Exception as e:
        print(f"  ⚠️  解析 {rpt_path} 失败: {e}")
    return None


def calculate_slack(target_clock, estimated_clock):
    """计算 Slack = (Target × 0.9) - Estimated"""
    return target_clock * 0.9 - estimated_clock


def generate_comparison_report():
    """生成对比报告"""
    reports_dir = PROJECT_ROOT / "Reports"
    
    # 收集数据
    results = {}
    
    # SHA-256
    print("📊 解析 SHA-256 报告...")
    sha256_dir = reports_dir / "sha256"
    sha256_data = {}
    
    csynth_xml = sha256_dir / "csynth.xml"
    if csynth_xml.exists():
        timing = parse_csynth_xml(csynth_xml)
        if timing:
            sha256_data.update(timing)
    
    # cosim.rpt 在提交的 reports 目录中被重命名为 test_hmac_sha256_cosim.rpt
    cosim_rpt = sha256_dir / "test_hmac_sha256_cosim.rpt"
    if cosim_rpt.exists():
        latency = parse_cosim_rpt(cosim_rpt)
        if latency:
            sha256_data.update(latency)
    
    # export_impl.rpt 额外复制到 Reports 目录用于资源分析
    impl_rpt = sha256_dir / "export_impl.rpt"
    if impl_rpt.exists():
        resources = parse_impl_rpt(impl_rpt)
        if resources:
            sha256_data['resources'] = resources
    
    results['SHA-256'] = sha256_data
    
    # LZ4
    print("📊 解析 LZ4 报告...")
    lz4_dir = reports_dir / "lz4"
    lz4_data = {}
    
    csynth_xml = lz4_dir / "csynth.xml"
    if csynth_xml.exists():
        timing = parse_csynth_xml(csynth_xml)
        if timing:
            lz4_data.update(timing)
    
    # cosim.rpt 在提交的 reports 目录中被重命名为 lz4CompressEngineRun_cosim.rpt
    cosim_rpt = lz4_dir / "lz4CompressEngineRun_cosim.rpt"
    if cosim_rpt.exists():
        latency = parse_cosim_rpt(cosim_rpt)
        if latency:
            lz4_data.update(latency)
    
    # export_impl.rpt 额外复制到 Reports 目录用于资源分析
    impl_rpt = lz4_dir / "export_impl.rpt"
    if impl_rpt.exists():
        resources = parse_impl_rpt(impl_rpt)
        if resources:
            lz4_data['resources'] = resources
    
    results['LZ4 Compress'] = lz4_data
    
    # Cholesky
    print("📊 解析 Cholesky 报告...")
    cholesky_dir = reports_dir / "cholesky"
    cholesky_data = {}
    
    csynth_xml = cholesky_dir / "csynth.xml"
    if csynth_xml.exists():
        timing = parse_csynth_xml(csynth_xml)
        if timing:
            cholesky_data.update(timing)
    
    # cosim.rpt 在提交的 reports 目录中被重命名为 kernel_cholesky_0_cosim.rpt
    cosim_rpt = cholesky_dir / "kernel_cholesky_0_cosim.rpt"
    if cosim_rpt.exists():
        latency = parse_cosim_rpt(cosim_rpt)
        if latency:
            cholesky_data.update(latency)
    
    # export_impl.rpt 额外复制到 Reports 目录用于资源分析
    impl_rpt = cholesky_dir / "export_impl.rpt"
    if impl_rpt.exists():
        resources = parse_impl_rpt(impl_rpt)
        if resources:
            cholesky_data['resources'] = resources
    
    results['Cholesky'] = cholesky_data
    
    # 生成 Markdown 报告
    output_path = reports_dir / "comparison_report.md"
    with open(output_path, 'w', encoding='utf-8') as f:
        f.write("# HLS Track 2025 - 性能对比报告\n\n")
        f.write("## 📊 与 Baseline 的对比\n\n")
        f.write("---\n\n")
        
        for problem_name in ['SHA-256', 'LZ4 Compress', 'Cholesky']:
            f.write(f"### {problem_name}\n\n")
            
            baseline = BASELINE[problem_name]
            student = results.get(problem_name, {})
            
            # 时钟与时序
            f.write("#### ⏱️ 时钟与时序\n\n")
            f.write("| 指标 | Baseline | 当前优化 | 变化 |\n")
            f.write("|------|----------|----------|------|\n")
            
            # Target Clock
            target_baseline = baseline['target_clock']
            target_student = student.get('target_clock', 0)
            f.write(f"| 目标时钟周期 (ns) | {target_baseline:.3f} | {target_student:.3f} | ")
            if target_student > 0:
                change = ((target_student - target_baseline) / target_baseline) * 100
                f.write(f"{change:+.1f}% |\n")
            else:
                f.write("N/A |\n")
            
            # Estimated Clock
            est_baseline = baseline['estimated_clock']
            est_student = student.get('estimated_clock', 0)
            f.write(f"| 估计时钟周期 (ns) | {est_baseline:.3f} | {est_student:.3f} | ")
            if est_student > 0:
                change = ((est_student - est_baseline) / est_baseline) * 100
                f.write(f"{change:+.1f}% |\n")
            else:
                f.write("N/A |\n")
            
            # Slack
            slack_baseline = calculate_slack(target_baseline, est_baseline)
            f.write(f"| Slack (ns) | {slack_baseline:.3f} | ")
            if target_student > 0 and est_student > 0:
                slack_student = calculate_slack(target_student, est_student)
                f.write(f"{slack_student:.3f} | ")
                if slack_student > 0 and slack_baseline > 0:
                    f.write("✅ 满足 |\n")
                elif slack_student > 0 and slack_baseline <= 0:
                    f.write("✅ 改善 |\n")
                elif slack_student <= 0:
                    f.write("⚠️ 违例 (-10分) |\n")
                else:
                    f.write("N/A |\n")
            else:
                f.write("N/A | N/A |\n")
            
            f.write("\n")
            
            # 性能指标（按照评分细则的核心指标）
            f.write("#### 🚀 性能指标\n\n")
            f.write("**核心评分指标：执行时间 = 估计时钟周期 × Co-sim Latency**\n\n")
            f.write("| 性能指标 | Baseline | 当前优化 | 改善 |\n")
            f.write("|----------|----------|----------|------|\n")
            
            # 1. 估计时钟周期
            est_baseline = baseline['estimated_clock']
            est_student = student.get('estimated_clock', 0)
            f.write(f"| **估计时钟周期** (ns) | {est_baseline:.3f} | ")
            if est_student > 0:
                f.write(f"{est_student:.3f} | ")
                improvement = ((est_baseline - est_student) / est_baseline) * 100
                if improvement > 0:
                    f.write(f"↓ {improvement:.1f}% |\n")
                elif improvement < 0:
                    f.write(f"↑ {-improvement:.1f}% |\n")
                else:
                    f.write("- |\n")
            else:
                f.write("N/A | N/A |\n")
            
            # 2. Co-sim Latency
            lat_baseline = baseline['latency']
            lat_student = student.get('latency', 0)
            f.write(f"| **Co-sim Latency** (cycles) | {lat_baseline} | ")
            if lat_student > 0:
                f.write(f"{lat_student} | ")
                improvement = ((lat_baseline - lat_student) / lat_baseline) * 100
                if improvement > 0:
                    f.write(f"↓ {improvement:.1f}% |\n")
                elif improvement < 0:
                    f.write(f"↑ {-improvement:.1f}% |\n")
                else:
                    f.write("- |\n")
            else:
                f.write("N/A | N/A |\n")
            
            # 3. 执行时间 = 估计时钟周期 × Latency
            exec_baseline = baseline['execution_time']
            if est_student > 0 and lat_student > 0:
                exec_student = est_student * lat_student
            else:
                exec_student = 0
            
            f.write(f"| **执行时间** (ns) | {exec_baseline:.1f} | ")
            if exec_student > 0:
                f.write(f"{exec_student:.1f} | ")
                improvement = ((exec_baseline - exec_student) / exec_baseline) * 100
                if improvement > 0:
                    f.write(f"**↓ {improvement:.1f}%** 🎉 |\n")
                elif improvement < 0:
                    f.write(f"↑ {-improvement:.1f}% ⚠️ |\n")
                else:
                    f.write("- |\n")
            else:
                f.write("N/A | N/A |\n")
            
            f.write("\n")
            
            # 资源使用（参考报告模板格式）
            if 'resources' in student:
                f.write("#### 💾 资源使用对比 (XC7Z020)\n\n")
                f.write("| 资源类型 | Baseline | 当前优化 | 改善幅度 | 利用率(Baseline) | 利用率(当前) | 状态 |\n")
                f.write("|----------|----------|----------|----------|------------------|--------------|------|\n")
                
                resources = student['resources']
                
                # 定义资源顺序和 Baseline（假设 Baseline 资源使用，这里需要实际数据）
                resource_order = ['LUT', 'FF', 'BRAM', 'DSP']
                
                for res_type in resource_order:
                    if res_type in resources:
                        res = resources[res_type]
                        used = res['used']
                        available = res['available']
                        util = res['utilization']
                        
                        # 判断状态
                        if util >= 100:
                            status = "❌ 超限"
                        elif util >= 80:
                            status = "⚠️ 偏高"
                        else:
                            status = "✅ 正常"
                        
                        # 这里暂时没有 Baseline 的资源数据，所以显示为 N/A
                        # 如果有 Baseline 数据，可以在 BASELINE 字典中添加 resources 字段
                        f.write(f"| {res_type} | N/A | {used:,} | N/A | N/A | {util:.2f}% | {status} |\n")
                
                f.write("\n")
                
                # 添加资源使用说明
                f.write("**资源使用说明：**\n")
                f.write(f"- 平台资源总量：LUT={resources['LUT']['available']:,}, ")
                f.write(f"FF={resources['FF']['available']:,}, ")
                f.write(f"BRAM={resources['BRAM']['available']}, ")
                f.write(f"DSP={resources['DSP']['available']}\n")
                f.write("- ✅ 正常: 利用率 < 80%\n")
                f.write("- ⚠️ 偏高: 80% ≤ 利用率 < 100%\n")
                f.write("- ❌ 超限: 利用率 ≥ 100% (该题得 0 分)\n")
                f.write("\n")
            
            f.write("---\n\n")
        
        # 总结
        f.write("## 📈 总结\n\n")
        f.write("### 性能改善汇总\n\n")
        f.write("| 题目 | 执行时间改善 | 时序状态 | 资源状态 |\n")
        f.write("|------|--------------|----------|----------|\n")
        
        for problem_name in ['SHA-256', 'LZ4 Compress', 'Cholesky']:
            baseline = BASELINE[problem_name]
            student = results.get(problem_name, {})
            
            f.write(f"| {problem_name} | ")
            
            # 执行时间改善
            exec_baseline = baseline['execution_time']
            est_student = student.get('estimated_clock', 0)
            lat_student = student.get('latency', 0)
            
            if est_student > 0 and lat_student > 0:
                exec_student = est_student * lat_student
                improvement = ((exec_baseline - exec_student) / exec_baseline) * 100
                if improvement > 0:
                    f.write(f"**{improvement:.1f}%** 🎉 | ")
                else:
                    f.write(f"{improvement:.1f}% | ")
            else:
                f.write("N/A | ")
            
            # 时序状态
            target_student = student.get('target_clock', 0)
            if target_student > 0 and est_student > 0:
                slack = calculate_slack(target_student, est_student)
                if slack > 0:
                    f.write("✅ 满足 | ")
                else:
                    f.write("⚠️ 违例 (-10分) | ")
            else:
                f.write("N/A | ")
            
            # 资源状态
            if 'resources' in student:
                resources = student['resources']
                max_util = max([res['utilization'] for res in resources.values()])
                if max_util < 100:
                    f.write("✅ 正常 |\n")
                else:
                    f.write("❌ 超限 (0分) |\n")
            else:
                f.write("N/A |\n")
        
        f.write("\n")
        f.write("### 评分说明\n\n")
        f.write("- ✅ **时序满足**: Slack > 0，正常计分\n")
        f.write("- ⚠️ **时序违例**: Slack ≤ 0，该题扣除 10 分\n")
        f.write("- ❌ **资源超限**: 任意资源利用率 ≥ 100%，该题得 0 分\n")
        f.write("- 🎉 **性能改善**: 执行时间相对 Baseline 的改善百分比\n\n")
        
        f.write("---\n\n")
        f.write("*报告生成时间: 自动生成*\n")
    
    print(f"✅ 对比报告已生成: {output_path}")


if __name__ == '__main__':
    generate_comparison_report()

