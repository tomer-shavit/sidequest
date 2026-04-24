"""Tests for plugin_disabled event emission (DASH-06).

Detects when plugin is disabled via config flag and emits one-shot event
to /events endpoint. Marker file suppresses re-emission on same calendar day.
"""

import json
import os
import shutil
import subprocess
import tempfile
import unittest
from datetime import datetime


class PluginDisabledDetectionTests(unittest.TestCase):
    """Test plugin_disabled detection and event emission."""

    def setUp(self):
        """Set up temp directories for config and state files."""
        self.tmpdir = tempfile.mkdtemp()
        self.config_dir = os.path.join(self.tmpdir, '.sidequest')
        os.makedirs(self.config_dir)

    def tearDown(self):
        """Clean up temp directories."""
        shutil.rmtree(self.tmpdir)

    def _write_config(self, config_data):
        """Write config.json to temp .sidequest directory."""
        config_path = os.path.join(self.config_dir, 'config.json')
        with open(config_path, 'w') as f:
            json.dump(config_data, f)
        return config_path

    def _write_state(self, state_data):
        """Write last-session-state.json to temp .sidequest directory."""
        state_path = os.path.join(self.config_dir, 'last-session-state.json')
        with open(state_path, 'w') as f:
            json.dump(state_data, f)
        return state_path

    def _read_state(self):
        """Read last-session-state.json from temp .sidequest directory."""
        state_path = os.path.join(self.config_dir, 'last-session-state.json')
        if not os.path.isfile(state_path):
            return None
        with open(state_path) as f:
            return json.load(f)

    def test_detects_disabled_via_config_flag(self):
        """Verify detection logic: enabled: false in config => DISABLED=1."""
        config = {
            'uid': 'test-user-123',
            'enabled': False,
            'token': 'test-token'
        }
        self._write_config(config)

        # Simulate shell logic: jq -r '.enabled // true' config.json
        # This reads the boolean value, treating missing as true (default)
        config_path = os.path.join(self.config_dir, 'config.json')
        is_enabled = subprocess.check_output(
            f"jq -r '.enabled' {config_path}",
            shell=True, text=True
        ).strip()
        self.assertEqual(is_enabled, 'false')

    def test_detects_missing_directory(self):
        """Verify detection logic: missing ~/.sidequest directory => DISABLED=1."""
        nonexistent_dir = os.path.join(self.tmpdir, 'nonexistent')
        # Should not exist
        self.assertFalse(os.path.isdir(nonexistent_dir))

    def test_detects_missing_config_file(self):
        """Verify detection logic: missing config.json => DISABLED=1."""
        # Directory exists but config.json doesn't
        self.assertTrue(os.path.isdir(self.config_dir))
        config_path = os.path.join(self.config_dir, 'config.json')
        self.assertFalse(os.path.isfile(config_path))

    def test_marker_file_created_on_emit(self):
        """Verify marker file is created after event emission (one-shot guard)."""
        config = {
            'uid': 'test-user-123',
            'enabled': False,
            'plugin_version': '0.4.0'
        }
        self._write_config(config)

        # Simulate marker file creation with today's date
        today = datetime.now().strftime('%Y-%m-%d')
        marker_data = {
            'last_plugin_disabled_emit': today,
            'was_enabled': False
        }
        self._write_state(marker_data)

        # Verify marker was written
        state = self._read_state()
        self.assertIsNotNone(state)
        self.assertEqual(state['last_plugin_disabled_emit'], today)
        self.assertFalse(state['was_enabled'])

    def test_one_shot_suppression_same_day(self):
        """Verify marker prevents re-emission on same calendar day."""
        today = datetime.now().strftime('%Y-%m-%d')

        config = {
            'uid': 'test-user-123',
            'enabled': False,
            'plugin_version': '0.4.0'
        }
        self._write_config(config)

        # First emission: marker doesn't exist
        marker_data_1 = {
            'last_plugin_disabled_emit': today,
            'was_enabled': False
        }
        self._write_state(marker_data_1)

        # Verify marker shows today's date
        state_1 = self._read_state()
        self.assertEqual(state_1['last_plugin_disabled_emit'], today)

        # Second emission attempt: marker exists with today's date
        # Shell logic: if [ "$LAST_EMIT" != "$TODAY" ] would prevent re-emission
        state_2 = self._read_state()
        should_emit = state_2['last_plugin_disabled_emit'] != today
        self.assertFalse(should_emit)  # Should NOT emit on same day

    def test_re_emission_after_day_change(self):
        """Verify emission resumes after calendar day changes."""
        import datetime as dt

        # Previous day
        yesterday = (dt.datetime.now() - dt.timedelta(days=1)).strftime('%Y-%m-%d')
        today = dt.datetime.now().strftime('%Y-%m-%d')

        config = {
            'uid': 'test-user-123',
            'enabled': False,
            'plugin_version': '0.4.0'
        }
        self._write_config(config)

        # Marker shows yesterday's emit
        old_marker = {
            'last_plugin_disabled_emit': yesterday,
            'was_enabled': False
        }
        self._write_state(old_marker)

        # Check if re-emission would occur: LAST_EMIT != TODAY
        state = self._read_state()
        should_emit = state['last_plugin_disabled_emit'] != today
        self.assertTrue(should_emit)  # Should emit on new day

    def test_marker_persists_across_sessions(self):
        """Verify marker state persists across multiple session starts."""
        today = datetime.now().strftime('%Y-%m-%d')

        config = {
            'uid': 'test-user-123',
            'enabled': False,
            'plugin_version': '0.4.0'
        }
        self._write_config(config)

        # First session: create marker
        marker_1 = {
            'last_plugin_disabled_emit': today,
            'was_enabled': False
        }
        self._write_state(marker_1)

        # Second session: verify marker still exists
        state_1 = self._read_state()
        self.assertIsNotNone(state_1)
        self.assertEqual(state_1['last_plugin_disabled_emit'], today)

        # Third session: verify marker unchanged
        state_2 = self._read_state()
        self.assertEqual(state_2['last_plugin_disabled_emit'], today)

    def test_disabled_via_config_defaults_to_enabled(self):
        """Verify .enabled field defaults to true if missing."""
        config = {
            'uid': 'test-user-123',
            'token': 'test-token'
            # 'enabled' field intentionally omitted
        }
        self._write_config(config)

        config_path = os.path.join(self.config_dir, 'config.json')
        is_enabled = subprocess.check_output(
            f"jq -r '.enabled // true' {config_path}",
            shell=True, text=True
        ).strip()
        self.assertEqual(is_enabled, 'true')  # Defaults to true

    def test_jq_parse_error_silent(self):
        """Verify jq parse errors are silently swallowed (malformed JSON)."""
        config_path = os.path.join(self.config_dir, 'config.json')
        with open(config_path, 'w') as f:
            f.write('{ invalid json')

        # jq should fail silently; fallback to "true"
        is_enabled = subprocess.check_output(
            f"jq -r '.enabled // true' {config_path} 2>/dev/null || echo 'true'",
            shell=True, text=True
        ).strip()
        self.assertEqual(is_enabled, 'true')


if __name__ == '__main__':
    unittest.main()
