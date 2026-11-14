import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest


PROJECT = Path(__file__).resolve().parents[1]
SCRIPT = PROJECT / "internetIncome.sh"
BASH = shutil.which("bash")


@unittest.skipUnless(BASH, "Bash is required")
class InternetIncomeTests(unittest.TestCase):
    def run_shell(self, setup="", action="start_containers", matches="", answer="no"):
        source = SCRIPT.read_text(encoding="utf-8")
        variables = source[source.index("# File names"):source.index("#Unique Id")]
        functions = source[source.index("# Check for open ports"):source.index("# Update and Install Docker")]
        # Redirect confirmation input to a fixture, not the developer's terminal.
        functions = functions.replace("</dev/tty", "</dev/null")
        harness = r'''
RED= GREEN= YELLOW= NOCOLOUR=
UNIQUE_ID=0123456789abcdef0123456789abcdef
CPU_ARCH=x86_64
DEVICE_NAME=testing
ENABLE_LOGS=false
AUTO_UPDATE_CONTAINERS=false
CLOSE_ALL_PORTS=false
USE_SOCKS5_DNS=false
USE_DNS_OVER_HTTPS=false
TUNNEL_METHOD=auto
read() {
  if [[ "$*" == *"-t 60"* ]]; then
    printf -v "${@: -1}" '%s' "$TEST_ANSWER"
    return "${TEST_READ_STATUS:-0}"
  fi
  builtin read "$@"
}
sudo() {
  if [[ "$1" != docker ]]; then return 0; fi
  shift
  printf '%s\n' "$*" >> docker.calls
  case "$1" in
    inspect) return 1 ;;
    ps) printf '%s' "$TEST_MATCHES" ;;
    pull) return 0 ;;
    run)
      if [[ "$*" == *'if [ ! -f /output/'* ]]; then return 1; fi
      if [[ "$*" == *"--name $TEST_FAIL_CONTAINER"* && -n "$TEST_FAIL_CONTAINER" ]]; then return 1; fi
      printf 'mock-container-id\n'
      ;;
  esac
}
sleep() { :; }
check_open_ports() { printf '2000\n'; }
uuidgen() { printf 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee\n'; }
'''
        with tempfile.TemporaryDirectory(prefix="internetincome-test-") as directory:
            path = Path(directory)
            (path / "library.sh").write_text(variables + functions, encoding="utf-8", newline="\n")
            (path / "test.sh").write_text("source ./library.sh\n" + harness + setup + "\n" + action + "\n", encoding="utf-8", newline="\n")
            env = dict(os.environ, TEST_MATCHES=matches, TEST_ANSWER=answer)
            result = subprocess.run([BASH, "./test.sh"], cwd=path, env=env, capture_output=True, text=True, timeout=30)
            calls = (path / "docker.calls").read_text(encoding="utf-8") if (path / "docker.calls").exists() else ""
            tracked = (path / "containernames.txt").read_text(encoding="utf-8") if (path / "containernames.txt").exists() else ""
            return result, calls, tracked

    def run_cli(self, argument, setup=None):
        with tempfile.TemporaryDirectory(prefix="internetincome-cli-test-") as directory:
            path = Path(directory)
            for filename in ("internetIncome.sh", "properties.conf", "restart.sh", "banner.jpg"):
                shutil.copyfile(PROJECT / filename, path / filename)
            commands = path / "commands"
            commands.mkdir()
            docker = commands / "docker"
            docker.write_text('''#!/bin/bash
printf '%s\\n' "$*" >> "$TEST_CALLS"
case "$1" in
  inspect) exit 1 ;;
  ps) exit 0 ;;
  run)
    [[ "$*" == *'if [ ! -f /output/'* ]] && exit 1
    printf 'mock-container-id\\n'
    ;;
esac
''', encoding="utf-8", newline="\n")
            sudo = commands / "sudo"
            sudo.write_text('''#!/bin/bash
if [[ "$1" != docker ]]; then exit 0; fi
exec "$@"
''', encoding="utf-8", newline="\n")
            docker.chmod(0o700)
            sudo.chmod(0o700)
            if setup:
                setup(path)
            env = dict(os.environ, PATH=str(commands) + os.pathsep + os.environ.get("PATH", ""), TEST_CALLS=str(path / "docker.calls"))
            result = subprocess.run([BASH, "./internetIncome.sh", argument], cwd=path, env=env, capture_output=True, text=True, timeout=30)
            calls = (path / "docker.calls").read_text(encoding="utf-8") if (path / "docker.calls").exists() else ""
            files = {str(file.relative_to(path)).replace("\\", "/") for file in path.rglob("*") if file.is_file()}
            return result, calls, files

    def assert_success(self, result):
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_cli_start_defaults(self):
        result, calls, files = self.run_cli("--start")
        self.assert_success(result)
        self.assertNotIn("--name", calls)
        self.assertIn("resolv.conf", files)
        self.assertNotIn("process.pid", files)

    def test_cli_delete_preserves_idlepay_identity(self):
        def setup(path):
            (path / "containernames.txt").write_text("idlepay-test-fixture\n", encoding="utf-8")
            (path / "idlepay-data/data").mkdir(parents=True)
            (path / "idlepay-data/data/config.json").write_text("{}", encoding="utf-8")
        result, calls, files = self.run_cli("--delete", setup)
        self.assert_success(result)
        self.assertIn("rm -f idlepay-test-fixture", calls)
        self.assertIn("idlepay-data/data/config.json", files)
        self.assertNotIn("containernames.txt", files)

    def test_cli_delete_backup_removes_idlepay_identity(self):
        def setup(path):
            (path / "idlepay-data/data").mkdir(parents=True)
            (path / "idlepay-data/data/config.json").write_text("{}", encoding="utf-8")
        result, _, files = self.run_cli("--deleteBackup", setup)
        self.assert_success(result)
        self.assertNotIn("idlepay-data/data/config.json", files)

    def test_shell_syntax(self):
        for filename, shell in (("internetIncome.sh", "bash"), ("restart.sh", "sh"), ("properties.conf", "bash")):
            with self.subTest(filename=filename):
                result = subprocess.run([BASH, "-c", f'{shell} -n "$1"', "syntax", str(PROJECT / filename)], capture_output=True, text=True)
                self.assert_success(result)

    def test_excluded_apps_stay_excluded(self):
        source = SCRIPT.read_text(encoding="utf-8")
        for setting in ("GRASS_EMAIL", "GRADIENT_EMAIL", "ADNADE_USERNAME", "EBESUCHER_USERNAME"):
            self.assertNotIn(setting, source)
        for archive in ("firefoxprofiledata.zip", "chromeprofiledata.zip"):
            self.assertNotIn(archive, source)

    def test_required_files_do_not_include_profiles(self):
        source = SCRIPT.read_text(encoding="utf-8")
        required = re.search(r"^required_files=(.*)$", source, re.MULTILINE).group(1)
        self.assertEqual(required, "($banner_file $properties_file $restart_file)")

    def test_apps_disabled_by_default(self):
        result, calls, tracked = self.run_shell()
        self.assert_success(result)
        self.assertNotIn("--name", calls)
        self.assertEqual(tracked, "")
        self.assertNotIn("9.9.9.9", SCRIPT.read_text(encoding="utf-8"))

    def test_repocket_api_without_email(self):
        result, calls, _ = self.run_shell("REPOCKET_API=sample-key")
        self.assert_success(result)
        self.assertIn("--name repocket", calls)
        self.assertIn("RP_API_KEY=sample-key repocket/repocket:latest", calls)
        self.assertNotIn("RP_EMAIL", calls)
        self.assertNotIn("watchtower.scope", calls)

    def test_existing_apps_remain_launchable(self):
        scenarios = {
            "bitping": "BITPING_EMAIL=user BITPING_PASSWORD=secret",
            "earnfm": "EARN_FM_API=sample-key",
            "traffmon": "TRAFFMONETIZER_TOKEN=sample-key",
            "proxyrack": "PROXYRACK_API=sample-key",
            "proxybase": "PROXYBASE_ACCOUNT_ID=sample-id",
            "pawns": "IPROYALS_EMAIL=user IPROYALS_PASSWORD=secret",
            "wipter": "WIPTER_EMAIL=user WIPTER_PASSWORD=secret",
            "packetshare": "PACKETSHARE_EMAIL=user PACKETSHARE_PASSWORD=secret",
            "honey": "HONEYGAIN_EMAIL=user HONEYGAIN_PASSWORD=secret",
            "peer2profit": "PEER2PROFIT_EMAIL=user",
            "antgain": "ANTGAIN_API_KEY=sample-key\ncontainer_pulled=true",
            "wizardgain": "WIZARD_GAIN_EMAIL=user",
            "packetstream": "PACKETSTREAM_CID=sample-id",
            "proxylite": "PROXYLITE_USER_ID=sample-id",
            "urnetwork": "UR_AUTH_TOKEN=sample-token\nmkdir -p urnetwork-data/data/.urnetwork\nprintf 'fixture' > urnetwork-data/data/.urnetwork/jwt",
            "titan": "TITAN_HASH=sample-hash",
            "earnapp": "EARNAPP=true",
            "myst": "MYSTERIUM=true",
        }
        for name, setup in scenarios.items():
            with self.subTest(app=name):
                result, calls, tracked = self.run_shell(setup)
                self.assert_success(result)
                self.assertIn(f"--name {name}", calls)
                self.assertIn(name, tracked)

    def test_fleetshare_preserved(self):
        result, calls, _ = self.run_shell("EARN_FM_API=sample-key\nUSE_EARN_FM_FLEETSHARE=true\nprintf 'socks5://user:pass@proxy.test:1080\\n' > proxies.txt")
        self.assert_success(result)
        self.assertIn("earnfm/fleetshare:latest", calls)
        self.assertNotIn("earnfm/earnfm-client", calls)

    def test_pawns_restart_policy(self):
        result, calls, _ = self.run_shell("IPROYALS_EMAIL=user IPROYALS_PASSWORD=secret")
        self.assert_success(result)
        self.assertIn("--restart=on-failure:5", calls)

    def test_watchtower_opt_in_and_scope(self):
        result, calls, tracked = self.run_shell("AUTO_UPDATE_CONTAINERS=true\nREPOCKET_API=sample-key")
        self.assert_success(result)
        self.assertIn("--label=com.centurylinklabs.watchtower.scope=0123456789abcdef0123456789abcdef", calls)
        self.assertIn("ghcr.io/nicholas-fedor/watchtower:nightly --scope 0123456789abcdef0123456789abcdef --interval 86400", calls)
        self.assertIn("internetincomewatchtower", tracked)

    def test_watchtower_one_per_run(self):
        result, calls, _ = self.run_shell("AUTO_UPDATE_CONTAINERS=true\nREPOCKET_API=sample-key", "start_containers 1 socks5://proxy.test:1080\nstart_containers 2 socks5://proxy.test:1081")
        self.assert_success(result)
        self.assertEqual(calls.count("run -d --name internetincomewatchtower"), 1)
        self.assertEqual(calls.count("run -d --label=com.centurylinklabs.watchtower.scope="), 2)

    def test_watchtower_tag_selection(self):
        for image, eligible in (("app:latest", True), ("app:arm64v8", True), ("app:arm32v7", True), ("app:0.6.6", False), ("app:lite", False), ("", False)):
            with self.subTest(image=image):
                result, _, _ = self.run_shell("AUTO_UPDATE_CONTAINERS=true", f'check_container_exists test-container "{image}"\nprintf "LABEL=%s\\n" "$WATCH_TOWER_LABEL"')
                self.assert_success(result)
                self.assertEqual("watchtower.scope=" in result.stdout, eligible)

    def test_existing_containers_require_consent(self):
        matches = "other-container|repocket/repocket:latest\nrepocket0123456789abcdef0123456789abcdef|repocket/repocket:latest\n"
        for answer, removed in (("no", False), ("yes", True), ("invalid", False)):
            with self.subTest(answer=answer):
                result, calls, _ = self.run_shell(action="check_container_exists new-container repocket/repocket:latest", matches=matches, answer=answer)
                self.assert_success(result)
                self.assertEqual("rm -f other-container" in calls, removed)
                self.assertNotIn("rm -f repocket0123456789abcdef0123456789abcdef", calls)
                self.assertIn("--filter ancestor=repocket/repocket:latest --filter network=bridge", calls)

    def test_existing_containers_timeout_keeps_them(self):
        result, calls, _ = self.run_shell("TEST_READ_STATUS=1", "check_container_exists new-container repocket/repocket:latest", matches="other-container|repocket/repocket:latest\n", answer="yes")
        self.assert_success(result)
        self.assertNotIn("rm -f", calls)
        self.assertIn("Skipping container deletion", result.stdout)

    def test_tunnel_selector_and_versions(self):
        scenarios = (
            ("auto", "false", "false", "socks5://proxy.test:1080", "ghcr.io/tun2proxy/tun2proxy:v0.8.7", "--dns virtual"),
            ("auto", "true", "false", "socks5://user:pa@ss@proxy.test:1080", "ghcr.io/heiher/hev-socks5-tunnel:2.20.0", "SOCKS5_PASSWORD=pa@ss"),
            ("auto", "false", "true", "http://proxy.test:8080", "ghcr.io/tun2proxy/tun2proxy:v0.8.7", "--dns over-tcp"),
            ("tun2socks", "false", "false", "socks5://proxy.test:1080", "xjasonlyu/tun2socks:v2.7.0", "PROXY=socks5://proxy.test:1080"),
            ("tun2proxy", "false", "false", "socks4://proxy.test:1080", "ghcr.io/tun2proxy/tun2proxy:v0.8.7", "--dns virtual"),
            ("redsocks", "false", "false", "socks5://proxy.test:1080", "alpine:3.20", "PROXY_TYPE=socks5"),
        )
        for method, socks_dns, doh, proxy, image, option in scenarios:
            with self.subTest(method=method, proxy=proxy):
                setup = f"TUNNEL_METHOD={method}\nUSE_SOCKS5_DNS={socks_dns}\nUSE_DNS_OVER_HTTPS={doh}"
                result, calls, tracked = self.run_shell(setup, f"start_containers 1 {proxy}")
                self.assert_success(result)
                self.assertIn(image, calls)
                self.assertIn(option, calls)
                self.assertIn("tun0123456789abcdef0123456789abcdef1", tracked)

    def test_proxy_apps_share_tunnel(self):
        result, calls, _ = self.run_shell("REPOCKET_API=sample-key", "start_containers 1 socks5://proxy.test:1080")
        self.assert_success(result)
        app_run = next(line for line in calls.splitlines() if line.startswith("run -d") and "--name repocket" in line)
        self.assertIn("--network=container:tun0123456789abcdef0123456789abcdef1", app_run)

    def test_invalid_tunnel_method_fails(self):
        result, calls, _ = self.run_shell("TUNNEL_METHOD=invalid", "start_containers 1 socks5://proxy.test:1080")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Invalid TUNNEL_METHOD", result.stdout)
        self.assertNotIn("--name tun", calls)

    def test_mysterium_close_ports(self):
        for action in ("start_containers", "start_containers 1 socks5://proxy.test:1080"):
            with self.subTest(action=action):
                result, calls, _ = self.run_shell("MYSTERIUM=true\nCLOSE_ALL_PORTS=true", action)
                self.assert_success(result)
                self.assertNotIn("-p 2000:4449", calls)
                self.assertNotIn("http://127.0.0.1:2000", result.stdout)

    def test_idlepay_direct_enrollment(self):
        result, calls, tracked = self.run_shell("IDLEPAY_KEY=ipk_sample")
        self.assert_success(result)
        app_run = next(line for line in calls.splitlines() if "--name idlepay" in line)
        self.assertIn("ghcr.io/idlepay/idlepay:latest", app_run)
        self.assertIn("IDLEPAY_KEY=ipk_sample", app_run)
        self.assertIn("IDLEPAY_DIRECT=on", app_run)
        self.assertIn("--hostname testing", app_run)
        self.assertIn("idlepay-data/data,target=/etc/idlepay", app_run)
        self.assertNotIn("--network=container:", app_run)
        self.assertIn("idlepay", tracked)

    def test_idlepay_native_proxy_mode_one_container(self):
        setup = "IDLEPAY_KEY=ipk_sample\nUSE_PROXIES=true\nprintf 'socks5://user:pass@proxy.test:1080\\nhttps://proxy.test:8080\\n' > proxies.txt"
        result, calls, _ = self.run_shell(setup, "start_containers 1 socks5://proxy.test:1080\nstart_containers 2 https://proxy.test:8080")
        self.assert_success(result)
        runs = [line for line in calls.splitlines() if "--name idlepay" in line]
        self.assertEqual(len(runs), 1)
        self.assertIn("IDLEPAY_DIRECT=off", runs[0])
        self.assertIn("proxies.txt,target=/proxies.txt,readonly", runs[0])
        self.assertNotIn("--network=container:", runs[0])

    def test_idlepay_saved_identity_without_key(self):
        result, calls, _ = self.run_shell("mkdir -p idlepay-data/data\nprintf '{}' > idlepay-data/data/config.json")
        self.assert_success(result)
        self.assertIn("--name idlepay", calls)
        source = SCRIPT.read_text(encoding="utf-8")
        backups = re.search(r"^back_up_folders=(.*)$", source, re.MULTILINE).group(1)
        cleanup = re.search(r"^folders_to_be_removed=(.*)$", source, re.MULTILINE).group(1)
        self.assertIn("$idlepay_data_folder", backups)
        self.assertNotIn("$idlepay_data_folder", cleanup)

    def test_idlepay_unsupported_proxy_fails_clearly(self):
        setup = "IDLEPAY_KEY=ipk_sample\nUSE_PROXIES=true\nprintf 'socks4://proxy.test:1080\\n' > proxies.txt"
        result, calls, _ = self.run_shell(setup, "start_containers 1 socks4://proxy.test:1080")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("IdlePay supports only static HTTP/HTTPS/SOCKS5 proxies", result.stdout)
        self.assertNotIn("--name idlepay", calls)

    def test_idlepay_launch_failure(self):
        result, _, _ = self.run_shell("IDLEPAY_KEY=ipk_sample\nTEST_FAIL_CONTAINER=idlepay")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Failed to start container for IdlePay", result.stdout)

    def test_watchtower_excludes_pinned_images_and_helpers(self):
        result, calls, _ = self.run_shell("AUTO_UPDATE_CONTAINERS=true\nEARNAPP=true\nHONEYGAIN_EMAIL=user HONEYGAIN_PASSWORD=secret\nPROXYLITE_USER_ID=sample-id", "start_containers 1 socks5://proxy.test:1080")
        self.assert_success(result)
        for name in ("earnapp", "honey", "dindproxylite", "internetincomewatchtower", "tun"):
            with self.subTest(container=name):
                app_run = next(line for line in calls.splitlines() if "--name " + name in line)
                self.assertNotIn("watchtower.scope", app_run)

    def test_traffmonetizer_arm_tag_eligible(self):
        for arch, tag in (("arm64", "arm64v8"), ("armv7l", "arm32v7")):
            with self.subTest(arch=arch):
                result, calls, _ = self.run_shell(f"AUTO_UPDATE_CONTAINERS=true\nCPU_ARCH={arch}\nTRAFFMONETIZER_TOKEN=sample-key")
                self.assert_success(result)
                app_run = next(line for line in calls.splitlines() if "--name traffmon" in line)
                self.assertIn(f"traffmonetizer/cli_v2:{tag}", app_run)
                self.assertIn("watchtower.scope", app_run)

    def test_container_launch_failure_is_reported(self):
        result, _, _ = self.run_shell("REPOCKET_API=sample-key\nTEST_FAIL_CONTAINER=repocket", "start_containers")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Failed to start container for Repocket", result.stdout)

    def test_proxy_validation(self):
        for proxy, valid in (("socks5://user:pa@ss@proxy.test:1080", True), ("http://proxy.test:8080", True), ("socks5://proxy.test:65536", False), ("ftp://proxy.test:21", False), ("no-scheme", False)):
            with self.subTest(proxy=proxy):
                result, _, _ = self.run_shell(f"printf '%s\\n' '{proxy}' > proxies.txt", "validate_proxies")
                self.assertEqual(result.returncode == 0, valid, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
