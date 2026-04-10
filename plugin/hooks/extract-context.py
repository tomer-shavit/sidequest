"""
Context extractor — reads Claude Code conversation history and extracts
developer tool topic tags via keyword matching and pattern detection.

Standalone and replaceable: future versions can swap this for an embedding
model without changing the rest of the pipeline.

Input:  history file path (arg 1), project dir filter (arg 2, optional)
Output: JSON array of tag slugs to stdout (e.g., ["postgresql", "react", "docker"])
Exit:   Always exits 0. Errors produce empty array [].
"""

import json
import os
import re
import sys
from collections import Counter

# Maximum entries to scan (most recent first)
MAX_ENTRIES = 30
# Minimum keyword occurrences to include as a tag
MIN_COUNT = 1
# Maximum tags to return
MAX_TAGS = 10

# Keyword patterns: maps regex patterns to canonical tag slugs
# Order matters — more specific patterns first
PATTERNS = [
    # Databases
    (r'\b(?:postgres(?:ql)?|pg_|psql|pgcrypto)\b|["\']pg["\']', 'postgresql'),
    (r'\b(?:mysql|mariadb)\b', 'mysql'),
    (r'\b(?:mongo(?:db)?|mongoose)\b', 'mongodb'),
    (r'\bredis\b', 'redis'),
    (r'\bsqlite\b', 'sqlite'),
    (r'\b(?:elastic(?:search)?|kibana)\b', 'elasticsearch'),
    (r'\bdynamo(?:db)?\b', 'dynamodb'),

    # Frameworks (before languages to catch "next.js" before "js")
    (r'\b(?:next\.?js|next\.config|nextjs)\b', 'nextjs'),
    (r'\b(?:react|jsx|tsx|use(?:State|Effect|Ref|Memo|Callback|Context))\b', 'react'),
    (r'\b(?:vue\.?js|vuejs|vue\.config)\b', 'vue'),
    (r'\bangular\b', 'angular'),
    (r'\bsvelte(?:kit)?\b', 'svelte'),
    (r'\bexpress(?:\.js)?\b', 'express'),
    (r'\bfastify\b', 'fastify'),
    (r'\bdjango\b', 'django'),
    (r'\bflask\b', 'flask'),
    (r'\b(?:rails|ruby on rails)\b', 'rails'),
    (r'\bspring\b', 'spring'),
    (r'\btailwind(?:css)?\b', 'tailwindcss'),

    # Languages
    (r'\b(?:typescript|\.ts\b|tsconfig)', 'typescript'),
    (r'\b(?:javascript|\.js\b|node\.?js|npm|package\.json)\b', 'javascript'),
    (r'\b(?:python|\.py\b|pip|pytest|venv)\b', 'python'),
    (r'\b(?:golang|\.go\b|go\.mod|go\.sum)\b', 'go'),
    (r'\b(?:rust|cargo|\.rs\b)\b', 'rust'),
    (r'\b(?:java\b|\.java\b|maven|gradle)\b', 'java'),
    (r'\bruby\b', 'ruby'),
    (r'\b(?:swift|swiftui|\.swift\b)\b', 'swift'),
    (r'\bkotlin\b', 'kotlin'),
    (r'\bc#|csharp|\.cs\b', 'csharp'),
    (r'\b(?:c\+\+|cpp|\.cpp\b|\.hpp\b)\b', 'cpp'),
    (r'\bphp\b', 'php'),

    # DevOps
    (r'\b(?:docker|dockerfile|docker-compose|container)\b', 'docker'),
    (r'\b(?:kubernetes|k8s|kubectl|helm)\b', 'kubernetes'),
    (r'\b(?:terraform|\.tf\b|hcl)\b', 'terraform'),
    (r'\b(?:ci/?cd|pipeline|github.actions|\.github/workflows)\b', 'cicd'),
    (r'\bnginx\b', 'nginx'),
    (r'\blinux\b', 'linux'),

    # Testing
    (r'\bjest\b', 'jest'),
    (r'\bpytest\b', 'pytest'),
    (r'\bcypress\b', 'cypress'),
    (r'\bplaywright\b', 'playwright'),

    # Monitoring
    (r'\b(?:logging|log\.(?:info|error|warn|debug))\b', 'logging'),
    (r'\b(?:prometheus|grafana|datadog)\b', 'metrics'),
    (r'\b(?:opentelemetry|jaeger|zipkin|tracing)\b', 'tracing'),

    # Security
    (r'\b(?:auth(?:entication)?|login|signup|jwt|bearer)\b', 'authentication'),
    (r'\b(?:oauth|openid|oidc)\b', 'oauth'),
    (r'\b(?:encrypt|tls|ssl|https|certificate)\b', 'encryption'),

    # AI/ML
    (r'\b(?:machine.learning|ml.model|training|inference)\b', 'machine_learning'),
    (r'\b(?:llm|gpt|claude|anthropic|openai|gemini)\b', 'llm'),
    (r'\b(?:embedding|vector|similarity)\b', 'embeddings'),

    # Cloud
    (r'\b(?:aws|lambda|s3|ec2|rds|cloudfront|api.gateway)\b', 'aws'),
    (r'\b(?:gcp|google.cloud|bigquery|cloud.run)\b', 'gcp'),
    (r'\b(?:azure|blob.storage)\b', 'azure'),
    (r'\b(?:cloudflare|workers|wrangler)\b', 'cloudflare'),
    (r'\b(?:vercel|edge.functions)\b', 'vercel'),
    (r'\b(?:serverless|faas)\b', 'serverless'),

    # Tools
    (r'\bgit(?:hub|lab)?\b', 'git'),
    (r'\b(?:webpack|bundle)\b', 'webpack'),
    (r'\bvite\b', 'vite'),
    (r'\bgraphql\b', 'graphql'),
    (r'\b(?:rest|api.endpoint|http.request)\b', 'rest_api'),
    (r'\bwebsocket\b', 'websockets'),
]

# Compile patterns once
COMPILED_PATTERNS = [(re.compile(p, re.IGNORECASE), slug) for p, slug in PATTERNS]


def read_recent_entries(history_path, project_filter=None, max_entries=MAX_ENTRIES):
    """Read most recent entries from history.jsonl, optionally filtered by project."""
    if not os.path.exists(history_path):
        return []

    entries = []
    try:
        with open(history_path, 'r') as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    entry = json.loads(line)
                    if project_filter and entry.get('project', '') != project_filter:
                        continue
                    entries.append(entry)
                except json.JSONDecodeError:
                    continue
    except (IOError, PermissionError):
        return []

    # Return most recent entries
    return entries[-max_entries:]


def extract_tags(entries):
    """Extract developer tool tags from conversation entries using pattern matching."""
    tag_counts = Counter()

    for entry in entries:
        text = entry.get('display', '')
        if not text:
            continue

        # Also check pasted content inline text
        pasted = entry.get('pastedContents', {})
        if isinstance(pasted, dict):
            for paste in pasted.values():
                if isinstance(paste, dict) and paste.get('content'):
                    text += ' ' + paste['content']

        # Match patterns
        for pattern, slug in COMPILED_PATTERNS:
            if pattern.search(text):
                tag_counts[slug] += 1

    # Filter by minimum count and return top tags
    tags = [slug for slug, count in tag_counts.most_common(MAX_TAGS)
            if count >= MIN_COUNT]

    return tags


def main():
    history_path = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser('~/.claude/history.jsonl')
    project_filter = sys.argv[2] if len(sys.argv) > 2 else None

    entries = read_recent_entries(history_path, project_filter)
    tags = extract_tags(entries)

    print(json.dumps(tags))


if __name__ == '__main__':
    try:
        main()
    except Exception:
        # Always output valid JSON, never crash
        print('[]')
