"""Tests for context extraction from Claude Code conversation history."""

import json
import os
import subprocess
import tempfile
import unittest

SCRIPT_PATH = os.path.join(os.path.dirname(__file__), '..', 'hooks', 'extract-context.py')


def run_extractor(entries, project_filter=None):
    """Write entries to a temp JSONL file and run the extractor."""
    with tempfile.NamedTemporaryFile(mode='w', suffix='.jsonl', delete=False) as f:
        for entry in entries:
            f.write(json.dumps(entry) + '\n')
        f.flush()
        args = ['python3', SCRIPT_PATH, f.name]
        if project_filter:
            args.append(project_filter)
        result = subprocess.run(args, capture_output=True, text=True, timeout=5)
        os.unlink(f.name)
        return json.loads(result.stdout.strip())


def make_entry(display, project='/test/project', session_id='test-session'):
    return {
        'display': display,
        'timestamp': 1712000000000,
        'project': project,
        'sessionId': session_id,
    }


class TestContextExtraction(unittest.TestCase):

    def test_extracts_database_tags(self):
        entries = [
            make_entry('help me fix my PostgreSQL query'),
            make_entry('the pg_dump command is failing'),
        ]
        tags = run_extractor(entries)
        self.assertIn('postgresql', tags)

    def test_extracts_framework_tags(self):
        entries = [
            make_entry('how do I use useState in React'),
            make_entry('my Next.js app is not building'),
        ]
        tags = run_extractor(entries)
        self.assertIn('react', tags)
        self.assertIn('nextjs', tags)

    def test_extracts_language_tags(self):
        entries = [
            make_entry('write a Python script to parse CSV'),
            make_entry('fix the typescript compilation error'),
        ]
        tags = run_extractor(entries)
        self.assertIn('python', tags)
        self.assertIn('typescript', tags)

    def test_extracts_devops_tags(self):
        entries = [
            make_entry('my docker container keeps crashing'),
            make_entry('update the kubernetes deployment'),
        ]
        tags = run_extractor(entries)
        self.assertIn('docker', tags)
        self.assertIn('kubernetes', tags)

    def test_extracts_cloud_tags(self):
        entries = [
            make_entry('deploy to AWS Lambda'),
            make_entry('configure the S3 bucket'),
        ]
        tags = run_extractor(entries)
        self.assertIn('aws', tags)

    def test_extracts_multiple_tags_from_single_message(self):
        entries = [
            make_entry('set up a React app with PostgreSQL and Docker'),
        ]
        tags = run_extractor(entries)
        self.assertIn('react', tags)
        self.assertIn('postgresql', tags)
        self.assertIn('docker', tags)

    def test_filters_by_project(self):
        entries = [
            make_entry('fix PostgreSQL query', project='/my/project'),
            make_entry('fix React component', project='/other/project'),
        ]
        tags = run_extractor(entries, project_filter='/my/project')
        self.assertIn('postgresql', tags)
        self.assertNotIn('react', tags)

    def test_returns_empty_for_no_matches(self):
        entries = [
            make_entry('what is the meaning of life'),
            make_entry('tell me a joke'),
        ]
        tags = run_extractor(entries)
        self.assertEqual(tags, [])

    def test_handles_empty_history(self):
        tags = run_extractor([])
        self.assertEqual(tags, [])

    def test_handles_missing_file(self):
        result = subprocess.run(
            ['python3', SCRIPT_PATH, '/nonexistent/file.jsonl'],
            capture_output=True, text=True, timeout=5
        )
        tags = json.loads(result.stdout.strip())
        self.assertEqual(tags, [])
        self.assertEqual(result.returncode, 0)

    def test_handles_malformed_jsonl(self):
        with tempfile.NamedTemporaryFile(mode='w', suffix='.jsonl', delete=False) as f:
            f.write('not valid json\n')
            f.write(json.dumps(make_entry('fix my React bug')) + '\n')
            f.write('{broken\n')
            f.flush()
            result = subprocess.run(
                ['python3', SCRIPT_PATH, f.name],
                capture_output=True, text=True, timeout=5
            )
            os.unlink(f.name)
            tags = json.loads(result.stdout.strip())
            self.assertIn('react', tags)

    def test_returns_max_10_tags(self):
        # Create entries mentioning many different tools
        entries = [
            make_entry('react next.js vue angular svelte express django flask rails spring postgresql docker kubernetes'),
        ]
        tags = run_extractor(entries)
        self.assertLessEqual(len(tags), 10)

    def test_includes_pasted_content(self):
        entries = [{
            'display': 'fix this code',
            'pastedContents': {
                '1': {
                    'id': 1,
                    'type': 'text',
                    'content': 'import { Pool } from "pg"\nconst pool = new Pool()',
                }
            },
            'timestamp': 1712000000000,
            'project': '/test/project',
            'sessionId': 'test-session',
        }]
        tags = run_extractor(entries)
        self.assertIn('postgresql', tags)

    def test_case_insensitive_matching(self):
        entries = [
            make_entry('using DOCKER and PostgreSQL'),
        ]
        tags = run_extractor(entries)
        self.assertIn('docker', tags)
        self.assertIn('postgresql', tags)


if __name__ == '__main__':
    unittest.main()
