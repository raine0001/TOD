import importlib.util
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[2] / "query_tod_local.py"
SPEC = importlib.util.spec_from_file_location("query_tod_local", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(MODULE)


def test_query_utility_reads_tod_managed_connection_authority(tmp_path):
    authority = tmp_path / "connection.json"
    authority.write_text(
        '{"managed_by":"TOD","ssh_host":"10.0.0.42","api_port":8102}',
        encoding="utf-8",
    )

    payload = MODULE.load_connection_authority(authority)

    assert payload["managed_by"] == "TOD"
    assert payload["ssh_host"] == "10.0.0.42"


def test_query_utility_contains_no_literal_todbox_lan_address():
    source = SCRIPT.read_text(encoding="utf-8")

    assert "192.168." not in source
