import json
import threading
import subprocess
import tempfile
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


class TodSocialConversationSimulationTests(unittest.TestCase):
    def test_small_run_produces_checkpoints_and_passes_thresholds(self):
        repo_root = Path(__file__).resolve().parent
        script = repo_root / "scripts" / "tod_social_conversation_simulation.py"
        catalog = repo_root / "tod" / "conversation_eval" / "social_domain_catalog.json"

        with tempfile.TemporaryDirectory(dir=repo_root) as temp_dir:
            output_root = Path(temp_dir) / "social-sim"
            command = [
                str(repo_root / ".venv" / "Scripts" / "python.exe"),
                str(script),
                "--conversation-count",
                "20000",
                "--checkpoint-interval",
                "5000",
                "--human-count",
                "2000",
                "--seed",
                "20260413",
                "--domain-catalog",
                str(catalog),
                "--output-root",
                str(output_root),
                "--warmup-checkpoints",
                "2",
                "--emit-json",
                "--fail-on-threshold",
            ]
            completed = subprocess.run(command, capture_output=True, text=True, check=True)
            payload = json.loads(completed.stdout)

            self.assertTrue(payload["summary"]["pass"])
            self.assertEqual(payload["summary"]["processed_conversations"], 20000)
            self.assertEqual(payload["summary"]["checkpoint_count"], 4)
            self.assertGreaterEqual(payload["summary"]["learning_delta"], 0.015)
            self.assertGreaterEqual(payload["summary"]["recognition_average"], 0.72)
            self.assertGreaterEqual(payload["summary"]["memory_average"], 0.73)
            self.assertGreaterEqual(payload["summary"]["resource_average"], 0.71)
            self.assertIn("social_style_distribution", payload["coverage"])
            self.assertIn("ambiguity_distribution", payload["coverage"])
            self.assertIn("resource_case_distribution", payload["coverage"])
            self.assertGreater(payload["coverage"]["resource_case_distribution"].get("none_needed", 0), 0)
            self.assertGreater(len(payload["coverage"]["social_style_distribution"]), 3)

            run_root = Path(payload["artifacts"]["run_root"])
            self.assertTrue((run_root / "social-simulation-report.json").exists())
            self.assertTrue((run_root / "social-simulation-report.md").exists())
            self.assertTrue((run_root / "checkpoints" / "checkpoint-00001.json").exists())
            self.assertTrue((run_root / "checkpoints" / "checkpoint-00004.json").exists())

    def test_live_fetch_checkpoint_probe_uses_real_retrieval(self):
        repo_root = Path(__file__).resolve().parent
        script = repo_root / "scripts" / "tod_social_conversation_simulation.py"

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                payload = (
                    "<html><body>travel trains timetable freshness_check location_specific "
                    "history science math theory food technology allergies </body></html>"
                ).encode("utf-8")
                self.send_response(200)
                self.send_header("Content-Type", "text/html; charset=utf-8")
                self.send_header("Content-Length", str(len(payload)))
                self.end_headers()
                self.wfile.write(payload)

            def log_message(self, format, *args):
                return

        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()

        try:
            live_url = f"http://127.0.0.1:{server.server_address[1]}/probe"
            with tempfile.TemporaryDirectory(dir=repo_root) as temp_dir:
                output_root = Path(temp_dir) / "social-sim"
                catalog_path = Path(temp_dir) / "social_domain_catalog.json"
                catalog = json.loads((repo_root / "tod" / "conversation_eval" / "social_domain_catalog.json").read_text(encoding="utf-8"))
                catalog["resource_catalog"] = {
                    "travel": [live_url],
                    "science": [live_url],
                    "math": [live_url],
                    "theory": [live_url],
                    "history": [live_url],
                    "food": [live_url],
                    "technology": [live_url],
                    "planet": [live_url],
                    "religion": [live_url],
                    "health": [live_url],
                    "finance": [live_url],
                    "literature": [live_url],
                    "sports": [live_url],
                }
                catalog_path.write_text(json.dumps(catalog), encoding="utf-8")

                command = [
                    str(repo_root / ".venv" / "Scripts" / "python.exe"),
                    str(script),
                    "--conversation-count",
                    "12000",
                    "--checkpoint-interval",
                    "4000",
                    "--human-count",
                    "2500",
                    "--seed",
                    "20260414",
                    "--domain-catalog",
                    str(catalog_path),
                    "--output-root",
                    str(output_root),
                    "--enable-live-fetch",
                    "--live-fetch-samples-per-checkpoint",
                    "2",
                    "--live-fetch-timeout-seconds",
                    "2",
                    "--warmup-checkpoints",
                    "1",
                    "--emit-json",
                    "--fail-on-threshold",
                ]
                completed = subprocess.run(command, capture_output=True, text=True, check=True)
                payload = json.loads(completed.stdout)

                self.assertTrue(payload["summary"]["pass"])
                self.assertTrue(payload["live_fetch"]["enabled"])
                self.assertGreaterEqual(payload["live_fetch"]["attempted"], 2)
                self.assertGreaterEqual(payload["live_fetch"]["success_rate"], 0.66)
                self.assertGreaterEqual(payload["live_fetch"]["average_grounding_score"], 0.68)
                checkpoint_with_fetch = next(item for item in payload["checkpoints"] if item["live_fetch"] and item["live_fetch"]["attempted"] > 0)
                self.assertGreaterEqual(checkpoint_with_fetch["live_fetch"]["success_rate"], 0.66)
                self.assertTrue(checkpoint_with_fetch["live_fetch"]["samples"][0]["url"].startswith("http://127.0.0.1:"))
        finally:
            server.shutdown()
            server.server_close()

    def test_include_domains_filters_output_coverage(self):
        repo_root = Path(__file__).resolve().parent
        script = repo_root / "scripts" / "tod_social_conversation_simulation.py"
        catalog = repo_root / "tod" / "conversation_eval" / "social_domain_catalog.json"

        with tempfile.TemporaryDirectory(dir=repo_root) as temp_dir:
            output_root = Path(temp_dir) / "science-sim"
            command = [
                str(repo_root / ".venv" / "Scripts" / "python.exe"),
                str(script),
                "--conversation-count",
                "15000",
                "--checkpoint-interval",
                "5000",
                "--human-count",
                "5000",
                "--seed",
                "20260414",
                "--domain-catalog",
                str(catalog),
                "--output-root",
                str(output_root),
                "--include-domains",
                "science",
                "math",
                "theory",
                "planet",
                "technology",
                "health",
                "--warmup-checkpoints",
                "1",
                "--emit-json",
            ]
            completed = subprocess.run(command, capture_output=True, text=True, check=True)
            payload = json.loads(completed.stdout)

            self.assertEqual(set(payload["coverage"]["domain_distribution"].keys()), {"science", "math", "theory", "planet", "technology", "health"})
            self.assertEqual(payload["config"]["include_domains"], ["science", "math", "theory", "planet", "technology", "health"])
            self.assertGreaterEqual(payload["summary"]["resource_average"], 0.71)
            self.assertGreaterEqual(payload["summary"]["recognition_average"], 0.72)


if __name__ == "__main__":
    unittest.main()