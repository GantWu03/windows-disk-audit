from __future__ import annotations

import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class PackageTests(unittest.TestCase):
    def run_validator(
        self, report: Path, findings: Path, merged: Path | None = None
    ) -> subprocess.CompletedProcess[str]:
        merged = merged or ROOT / "evals" / "fixtures" / "sample-merged-findings.json"
        return subprocess.run(
            [
                "powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
                str(ROOT / "scripts" / "validate_report.ps1"),
                "-ManifestPath", str(ROOT / "evals" / "fixtures" / "sample-manifest.json"),
                "-MergedFindingsPath", str(merged),
                "-ReportPath", str(report), "-FindingsPath", str(findings),
            ],
            capture_output=True, text=True, encoding="utf-8", errors="replace",
        )

    def test_required_files_and_single_entrypoint(self) -> None:
        for relative in (
            "SKILL.md", "README.md", "manifest.json", "agents/interface.yaml",
            "references/workflow.md", "references/data-contracts.md",
            "references/directory-procedures.md", "references/report-format.md",
            "references/windows-installer-cache.md",
            "scripts/new_audit_manifest.ps1", "scripts/collect_inventory.ps1",
            "scripts/merge_findings.ps1", "scripts/render_report.ps1", "scripts/validate_report.ps1",
        ):
            self.assertTrue((ROOT / relative).is_file(), relative)
        self.assertEqual(list(ROOT.rglob("SKILL.md")), [ROOT / "SKILL.md"])

    def test_json_files_parse(self) -> None:
        for path in ROOT.rglob("*.json"):
            with self.subTest(path=path.relative_to(ROOT)):
                json.loads(path.read_text(encoding="utf-8-sig"))

    def test_powershell_scripts_keep_bom(self) -> None:
        for path in (ROOT / "scripts").glob("*.ps1"):
            self.assertTrue(path.read_bytes().startswith(b"\xef\xbb\xbf"), path.name)

    def test_inventory_scripts_do_not_clean(self) -> None:
        for name in ("new_audit_manifest.ps1", "collect_inventory.ps1"):
            text = (ROOT / "scripts" / name).read_text(encoding="utf-8-sig").lower()
            for token in ("remove-item", "takeown", "icacls", "stop-service", "wsl --unregister", "docker system prune"):
                self.assertNotIn(token, text)

    def test_skill_preserves_investigation_but_fixes_directory_explanation_contract(self) -> None:
        skill = (ROOT / "SKILL.md").read_text(encoding="utf-8")
        workflow = (ROOT / "references" / "workflow.md").read_text(encoding="utf-8")
        report = (ROOT / "references" / "report-format.md").read_text(encoding="utf-8")
        self.assertIn("调查教程", skill)
        self.assertIn("无损合并", workflow)
        self.assertIn("不得按重要性筛除", workflow)
        self.assertIn("主要空间去向概览表", report)
        self.assertIn("正文以真实目录为主线", report)
        self.assertIn("它是什么，由哪个系统、软件或使用行为产生", report)
        self.assertIn("最终正文直接使用这些章节", report)
        self.assertIn("再由用户决定是否处理", skill)
        self.assertIn("不替用户判断某个软件、项目、会话或备份是否还需要", skill)
        self.assertIn("先形成完整的 `cluster-plan`", skill)
        self.assertIn("显著的大目录原则上一个子 Agent 负责", skill)
        self.assertIn("可以使用软件提供的并行上限", skill)
        self.assertIn("目录内发现新的重大对象时应继续调查", skill)
        self.assertIn("每个一级对象必须明确分配给某个子 Agent", skill)
        self.assertIn("优先查找 Microsoft 或产品官方资料", skill)
        self.assertIn("没有矛盾时不重复调查", skill)
        self.assertIn("正文直接使用各目录 `chapter.md`", skill)
        self.assertIn("不得另写一份缩略正文", skill)
        self.assertIn("承认的未知、抽样边界、权限失败和盲区必须原样进入最终报告", skill)
        self.assertIn("主 Agent只做四件事", workflow)
        self.assertNotIn("确定性生成最终 Markdown", skill)
        self.assertNotIn("复核所有没有明确", skill)
        self.assertNotIn("并行二至三路", workflow)

    def test_sample_report_is_directory_explanation_not_action_shortlist(self) -> None:
        report = (ROOT / "evals" / "fixtures" / "sample-report.md").read_text(encoding="utf-8")
        self.assertIn("## 主要空间去向", report)
        self.assertIn("| 对象或目录 | 大概位置 | 占用与口径 | 它是什么 |", report)
        self.assertIn("## 系统盘根目录", report)
        self.assertIn("## 用户目录与应用数据", report)
        self.assertIn("## Windows 系统区", report)
        self.assertIn("它由 Windows 电源管理创建", report)
        self.assertIn("以后需要联网重新下载", report)
        self.assertNotIn("最值得现在做的三件事", report)

    def test_validator_rejects_report_without_space_overview_table(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            source = (ROOT / "evals" / "fixtures" / "sample-report.md").read_text(encoding="utf-8")
            start = source.index("## 主要空间去向")
            end = source.index("## 系统盘根目录")
            report = Path(directory) / "report.md"
            report.write_text(source[:start] + source[end:], encoding="utf-8")
            result = self.run_validator(report, ROOT / "evals" / "fixtures" / "sample-findings.json")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("主要空间去向概览表", result.stdout)

    def test_validator_rejects_overview_table_moved_to_end(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            source = (ROOT / "evals" / "fixtures" / "sample-report.md").read_text(encoding="utf-8")
            start = source.index("## 主要空间去向")
            end = source.index("## 系统盘根目录")
            report = Path(directory) / "report.md"
            report.write_text(source[:start] + source[end:] + "\n" + source[start:end], encoding="utf-8")
            result = self.run_validator(report, ROOT / "evals" / "fixtures" / "sample-findings.json")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("必须位于报告前部", result.stdout)

    def test_validator_rejects_ids_without_directory_explanations(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            source = (ROOT / "evals" / "fixtures" / "sample-report.md").read_text(encoding="utf-8")
            start = source.index("## 主要空间去向")
            body = source.index("## 系统盘根目录")
            overview_only = source[:body]
            report = Path(directory) / "report.md"
            report.write_text(
                overview_only + "## Windows 系统区\n\nS-001 U-001 R-001\n\n本次未执行清理。\n",
                encoding="utf-8",
            )
            result = self.run_validator(report, ROOT / "evals" / "fixtures" / "sample-findings.json")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("没有解释基本用途", result.stdout)

    def test_installer_appendix_blocks_unsafe_shortcuts(self) -> None:
        text = (ROOT / "references" / "windows-installer-cache.md").read_text(encoding="utf-8")
        self.assertIn("MsiEnumPatchesEx", text)
        self.assertIn("不能单独证明文件孤立", text)
        self.assertIn("不把 `msizap`", text)
        self.assertIn("可安全回收量为未知", text)

    def test_minimal_and_rich_findings_validate(self) -> None:
        result = self.run_validator(
            ROOT / "evals" / "fixtures" / "sample-report.md",
            ROOT / "evals" / "fixtures" / "sample-findings.json",
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_unknown_extension_fields_are_allowed(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            findings = json.loads((ROOT / "evals" / "fixtures" / "sample-findings.json").read_text(encoding="utf-8"))
            findings[0]["better_local_analysis"] = {"growth_samples": [1, 2], "note": "保留额外能力"}
            path = Path(directory) / "findings.json"
            path.write_text(json.dumps(findings, ensure_ascii=False), encoding="utf-8")
            result = self.run_validator(ROOT / "evals" / "fixtures" / "sample-report.md", path)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_aggregated_paths_are_allowed(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            findings = json.loads((ROOT / "evals" / "fixtures" / "sample-findings.json").read_text(encoding="utf-8"))
            findings[2]["paths"] = [findings[2].pop("path"), "C:\\Windows\\Temp"]
            path = Path(directory) / "findings.json"
            path.write_text(json.dumps(findings, ensure_ascii=False), encoding="utf-8")
            result = self.run_validator(ROOT / "evals" / "fixtures" / "sample-report.md", path)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_natural_report_rewrite_is_allowed(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            source = (ROOT / "evals" / "fixtures" / "sample-report.md").read_text(encoding="utf-8")
            path = Path(directory) / "report.md"
            path.write_text(source.replace("## 系统盘根目录", "## C 盘根目录"), encoding="utf-8")
            result = self.run_validator(path, ROOT / "evals" / "fixtures" / "sample-findings.json")
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_low_value_record_may_omit_advice_and_external_evidence(self) -> None:
        findings = json.loads((ROOT / "evals" / "fixtures" / "sample-findings.json").read_text(encoding="utf-8"))
        record = findings[2]
        self.assertEqual(record["role"], "record")
        self.assertNotIn("recommendation", record)
        self.assertNotIn("evidence", record)

    def test_validator_rejects_missing_core_safety_field(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            findings = json.loads((ROOT / "evals" / "fixtures" / "sample-findings.json").read_text(encoding="utf-8"))
            del findings[0]["state_changes_performed"]
            path = Path(directory) / "findings.json"
            path.write_text(json.dumps(findings, ensure_ascii=False), encoding="utf-8")
            result = self.run_validator(ROOT / "evals" / "fixtures" / "sample-report.md", path)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("轻量核心字段", result.stdout)

    def test_validator_rejects_candidate_dropped_after_merge(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            findings = json.loads((ROOT / "evals" / "fixtures" / "sample-findings.json").read_text(encoding="utf-8"))
            findings.pop()
            report = Path(directory) / "report.md"
            report.write_text((ROOT / "evals" / "fixtures" / "sample-report.md").read_text(encoding="utf-8"), encoding="utf-8")
            path = Path(directory) / "findings.json"
            path.write_text(json.dumps(findings, ensure_ascii=False), encoding="utf-8")
            result = self.run_validator(report, path)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("没有进入最终复核结果", result.stdout)

    def test_validator_allows_duplicate_candidates_to_merge_without_disappearing(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            merged = json.loads((ROOT / "evals" / "fixtures" / "sample-merged-findings.json").read_text(encoding="utf-8"))
            duplicate = dict(merged[1])
            duplicate["id"] = "M-0004"
            duplicate["source_refs"] = ["second-lane:U-099"]
            merged.append(duplicate)
            merged_path = Path(directory) / "findings.raw.json"
            merged_path.write_text(json.dumps(merged, ensure_ascii=False), encoding="utf-8")
            findings = json.loads((ROOT / "evals" / "fixtures" / "sample-findings.json").read_text(encoding="utf-8"))
            findings[1]["source_refs"].append("second-lane:U-099")
            findings[1]["review_status"] = "merged_duplicate"
            findings_path = Path(directory) / "findings.json"
            findings_path.write_text(json.dumps(findings, ensure_ascii=False), encoding="utf-8")
            result = self.run_validator(ROOT / "evals" / "fixtures" / "sample-report.md", findings_path, merged_path)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_validator_rejects_unknown_action_value(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            findings = json.loads((ROOT / "evals" / "fixtures" / "sample-findings.json").read_text(encoding="utf-8"))
            findings[1]["recommended_action"] = "cleanup_via_app"
            path = Path(directory) / "findings.json"
            path.write_text(json.dumps(findings, ensure_ascii=False), encoding="utf-8")
            result = self.run_validator(ROOT / "evals" / "fixtures" / "sample-report.md", path)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("recommended_action 使用未知值", result.stdout)

    def test_validator_requires_every_final_finding_in_markdown(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            report = Path(directory) / "report.md"
            text = (ROOT / "evals" / "fixtures" / "sample-report.md").read_text(encoding="utf-8")
            report.write_text(text.replace("R-001 ", ""), encoding="utf-8")
            result = self.run_validator(report, ROOT / "evals" / "fixtures" / "sample-findings.json")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("没有出现在按目录组织的正文中", result.stdout)

    def test_merge_script_preserves_every_cluster_candidate(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            clusters = root / "clusters"
            for cluster, ids in (("system", ["A-1", "A-2"]), ("users", ["B-1"])):
                lane = clusters / cluster
                lane.mkdir(parents=True)
                records = [
                    {
                        "id": candidate_id,
                        "path": f"C:\\{cluster}\\{candidate_id}",
                        "summary": f"candidate {candidate_id}",
                        "observations": ["measured"],
                        "state_changes_performed": [],
                        "actual_result": "not_executed",
                    }
                    for candidate_id in ids
                ]
                (lane / "findings.json").write_text(json.dumps(records), encoding="utf-8")
                (lane / "coverage.json").write_text(
                    json.dumps({"checked_paths": [f"C:\\{cluster}"], "completeness": "complete"}),
                    encoding="utf-8",
                )
                (lane / "chapter.md").write_text(
                    f"## {cluster}\n\n" + "\n\n".join(
                        f"### {candidate_id}\n\n这是工具运行时产生的缓存目录，用于保存已经下载的组件。"
                        "空间充足时可以保留；急需空间时可以退出工具后只清理缓存。"
                        "清理不会删除源码，但以后使用缺失组件时会重新下载，缓存也会再次增长。"
                        for candidate_id in ids
                    ),
                    encoding="utf-8",
                )
            output = root / "merged"
            result = subprocess.run(
                [
                    "powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
                    str(ROOT / "scripts" / "merge_findings.ps1"),
                    "-ClustersDirectory", str(clusters), "-OutputDirectory", str(output),
                ],
                capture_output=True, text=True, encoding="utf-8", errors="replace",
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            merged = json.loads((output / "findings.raw.json").read_text(encoding="utf-8-sig"))
            self.assertEqual(len(merged), 3)
            self.assertEqual(
                {ref for item in merged for ref in item["source_refs"]},
                {"system:A-1", "system:A-2", "users:B-1"},
            )
            chapters = (output / "chapters.raw.md").read_text(encoding="utf-8-sig")
            self.assertIn("source_cluster: system", chapters)
            self.assertIn("source_cluster: users", chapters)
            self.assertIn("A-1", chapters)
            self.assertIn("B-1", chapters)

    def test_merge_script_rejects_chapter_that_omits_candidate(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            lane = root / "clusters" / "system"
            lane.mkdir(parents=True)
            (lane / "findings.json").write_text(json.dumps([{"id": "A-1", "summary": "sample"}]), encoding="utf-8")
            (lane / "coverage.json").write_text(
                json.dumps({"checked_paths": ["C:\\Windows"], "completeness": "complete"}),
                encoding="utf-8",
            )
            (lane / "chapter.md").write_text("## Windows 系统区\n\n只有一句总览。", encoding="utf-8")
            result = subprocess.run(
                [
                    "powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
                    str(ROOT / "scripts" / "merge_findings.ps1"),
                    "-ClustersDirectory", str(root / "clusters"), "-OutputDirectory", str(root / "merged"),
                ],
                capture_output=True, text=True, encoding="utf-8", errors="replace",
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("chapter.md", result.stdout + result.stderr)

    def test_merge_script_rejects_empty_coverage_contract(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            lane = root / "clusters" / "system"
            lane.mkdir(parents=True)
            (lane / "findings.json").write_text(json.dumps([{"id": "A-1", "summary": "sample"}]), encoding="utf-8")
            (lane / "coverage.json").write_text("{}", encoding="utf-8")
            (lane / "chapter.md").write_text(
                "## Windows 系统区\n\n### A-1\n\n这是系统维护缓存，用于保存更新组件。"
                "当前可以保留并继续核验，不要直接删除。误删会影响后续维护，恢复可能需要重新下载。",
                encoding="utf-8",
            )
            result = subprocess.run(
                [
                    "powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
                    str(ROOT / "scripts" / "merge_findings.ps1"),
                    "-ClustersDirectory", str(root / "clusters"), "-OutputDirectory", str(root / "merged"),
                ],
                capture_output=True, text=True, encoding="utf-8", errors="replace",
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("coverage.json", result.stdout + result.stderr)

    def test_validator_rejects_state_change_and_unsupported_reclaim(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            findings = json.loads((ROOT / "evals" / "fixtures" / "sample-findings.json").read_text(encoding="utf-8"))
            findings[1]["state_changes_performed"] = ["deleted cache"]
            findings[1]["reclaimable_min_bytes"] = 1
            findings[1]["reclaimable_max_bytes"] = 100
            path = Path(directory) / "findings.json"
            path.write_text(json.dumps(findings, ensure_ascii=False), encoding="utf-8")
            result = self.run_validator(ROOT / "evals" / "fixtures" / "sample-report.md", path)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("状态变更", result.stdout)
            self.assertIn("没有明确依据", result.stdout)

    def test_validator_requires_decision_index_for_action(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            findings = json.loads((ROOT / "evals" / "fixtures" / "sample-findings.json").read_text(encoding="utf-8"))
            del findings[1]["decision_basis"]
            path = Path(directory) / "findings.json"
            path.write_text(json.dumps(findings, ensure_ascii=False), encoding="utf-8")
            result = self.run_validator(ROOT / "evals" / "fixtures" / "sample-report.md", path)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("decision index", result.stdout)

    def test_validator_rejects_copyable_destructive_commands(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            report = Path(directory) / "report.md"
            report.write_text("# 只读审计\n\n未执行清理。\n\nRemove-Item C:\\Temp -Recurse -Force\n", encoding="utf-8")
            result = self.run_validator(report, ROOT / "evals" / "fixtures" / "sample-findings.json")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("强制递归删除命令", result.stdout)

    def test_validator_rejects_direct_clean_of_active_or_protected_object(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            findings = json.loads((ROOT / "evals" / "fixtures" / "sample-findings.json").read_text(encoding="utf-8"))
            findings[0]["recommended_action"] = "direct_clean"
            findings[1]["active_use"] = "yes"
            findings[1]["recommended_action"] = "direct_clean"
            path = Path(directory) / "findings.json"
            path.write_text(json.dumps(findings, ensure_ascii=False), encoding="utf-8")
            result = self.run_validator(ROOT / "evals" / "fixtures" / "sample-report.md", path)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("受保护对象", result.stdout)
            self.assertIn("正在活动", result.stdout)

    def test_renderer_produces_editable_draft(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            report = Path(directory) / "draft.md"
            result = subprocess.run(
                [
                    "powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
                    str(ROOT / "scripts" / "render_report.ps1"),
                    "-ManifestPath", str(ROOT / "evals" / "fixtures" / "sample-manifest.json"),
                    "-FindingsPath", str(ROOT / "evals" / "fixtures" / "sample-findings.json"),
                    "-ChaptersPath", str(ROOT / "evals" / "fixtures" / "sample-chapters.md"),
                    "-ReportPath", str(report),
                ],
                capture_output=True, text=True, encoding="utf-8", errors="replace",
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            text = report.read_text(encoding="utf-8-sig")
            self.assertIn("初稿", text)
            self.assertIn("主 Agent继续编辑", text)
            self.assertIn("主要空间去向", text)
            self.assertIn("| 对象或目录 | 大概位置 | 占用与口径 | 它是什么 |", text)
            self.assertIn("系统盘根目录", text)
            self.assertNotIn("重点发现", text)

    def test_narrow_scope_baseline_does_not_enumerate_system_root_or_known_candidates(self) -> None:
        non_system_root = Path("D:/")
        if not non_system_root.is_dir():
            self.skipTest("requires a non-system drive for low-space-safe evidence output")
        with tempfile.TemporaryDirectory() as data_directory, tempfile.TemporaryDirectory(dir=non_system_root) as output_parent:
            data = Path(data_directory)
            (data / "sample.bin").write_bytes(b"x" * 64)
            output = Path(output_parent) / "audit"
            init = subprocess.run(
                [
                    "powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
                    str(ROOT / "scripts" / "new_audit_manifest.ps1"),
                    "-OutputDirectory", str(output), "-AllowedPaths", str(data), "-TimeBudgetMinutes", "5",
                ],
                capture_output=True, text=True, encoding="utf-8", errors="replace",
            )
            self.assertEqual(init.returncode, 0, init.stdout + init.stderr)
            run = subprocess.run(
                [
                    "powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
                    str(ROOT / "scripts" / "collect_inventory.ps1"),
                    "-ManifestPath", str(output / "audit-manifest.json"), "-Phase", "baseline", "-SecondsPerPath", "1",
                ],
                capture_output=True, text=True, encoding="utf-8", errors="replace",
            )
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            inventory = json.loads((output / "baseline" / "inventory.json").read_text(encoding="utf-8-sig"))
            self.assertEqual(inventory["root_entries"], [])
            self.assertEqual(inventory["known_candidates"], [])
            self.assertEqual(inventory["relevant_services"], [])
            measured = {Path(item["path"]).resolve() for item in inventory["targeted_measurements"] if item["type"] != "rejected"}
            self.assertEqual(measured, {(data / "sample.bin").resolve()})

    def test_runtime_low_space_gate_blocks_system_drive_output_before_writing(self) -> None:
        system_drive = os.environ.get("SystemDrive", "C:").rstrip("\\/")
        non_system_root = Path("D:/")
        if not non_system_root.is_dir():
            self.skipTest("requires a non-system drive for the manifest fixture")
        with tempfile.TemporaryDirectory() as allowed_directory, tempfile.TemporaryDirectory(dir=non_system_root) as manifest_directory:
            blocked_output = Path(allowed_directory) / "must-not-be-created"
            manifest = {
                "schema_version": "1.0", "audit_id": "runtime-low-space", "system_drive": system_drive,
                "mode": "read_only", "cleanup_authorized": False, "time_budget_minutes": 5,
                "output_directory": str(blocked_output), "allowed_paths": [allowed_directory], "excluded_paths": [],
                "low_space_write_gate_bytes": 9_000_000_000_000_000_000,
            }
            manifest_path = Path(manifest_directory) / "audit-manifest.json"
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
            run = subprocess.run(
                [
                    "powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
                    str(ROOT / "scripts" / "collect_inventory.ps1"),
                    "-ManifestPath", str(manifest_path), "-Phase", "baseline", "-SecondsPerPath", "1",
                ],
                capture_output=True, text=True, encoding="utf-8", errors="replace",
            )
            self.assertNotEqual(run.returncode, 0)
            self.assertFalse(blocked_output.exists())


if __name__ == "__main__":
    unittest.main()
