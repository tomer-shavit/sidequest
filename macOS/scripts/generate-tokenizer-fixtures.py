#!/usr/bin/env python3
"""
Generate SentencePiece tokenizer fixtures for EmbeddingGemma-300M.
Produces reference token sequences via HF AutoTokenizer.

Usage:
    python3 generate-tokenizer-fixtures.py

Output: client/macOS/SideQuestAppTests/sentencepiece-fixtures.json
"""
import json
from transformers import AutoTokenizer

# Load the official EmbeddingGemma tokenizer from HuggingFace
tok = AutoTokenizer.from_pretrained('google/embeddinggemma-300m')

test_inputs = [
    # Basic English
    ("hello world", "basic english"),
    ("The quick brown fox", "english phrase"),

    # Code patterns
    ("async/await", "code with punctuation"),
    ("import { useState } from 'react'", "javascript import"),
    ("def calculate(x: int) -> float:", "python function"),
    ("const data = await fetch(url)", "async javascript"),

    # Emoji and Unicode
    ("🚀 rocket", "emoji with text"),
    ("Hello 世界", "chinese characters"),
    ("Привет мир", "russian text"),
    ("مرحبا بالعالم", "arabic text"),

    # Edge cases
    ("", "empty string"),
    ("x", "single character"),
    ("   spaces only   ", "whitespace"),
    ("!!!???", "special characters only"),
    ("ALLCAPS", "all uppercase"),
    ("mixedCASE", "mixed case"),
    ("snake_case_text", "underscore separated"),
    ("kebab-case-text", "hyphen separated"),

    # Long text
    ("The Python programming language is widely used in data science, web development, automation, and machine learning. Its syntax is simple and readable, making it ideal for beginners.", "long english"),
    ("This is a very long message that might exceed typical embedding context windows. " * 3, "very long text"),

    # Code snippets
    ("const sum = (a, b) => a + b;", "arrow function"),
    ("SELECT * FROM users WHERE id = 1;", "sql query"),
    ("for (let i = 0; i < 10; i++) { console.log(i); }", "javascript loop"),
    ("if __name__ == '__main__':", "python main check"),

    # Mixed content
    ("Check out https://example.com for more info!", "url with text"),
    ("Email: user@example.com", "email address"),
    ("Phone: +1-234-567-8900", "phone number"),
    ("Price: $99.99 USD", "currency"),

    # Domain-specific (AI/coding context)
    ("Write a Python function to calculate fibonacci", "task description"),
    ("async function fetchData(endpoint) { ... }", "async code"),
    ("type User = { id: string; email: string }", "typescript type"),
    ("@app.route('/api/users', methods=['GET'])", "flask decorator"),

    # Special tokens and punctuation
    ("Hello, world! How are you?", "punctuation heavy"),
    ("Don't worry—it's fine.", "apostrophe and dash"),
    ("what???", "repeated punctuation"),
    ("(nested (parentheses (are) tricky))", "nested parens"),

    # Whitespace variants
    ("tabs\there", "tab character"),
    ("newline\nhere", "newline character"),
    ("mixed  spacing", "multiple spaces"),

    # More emoji combinations
    ("👋 👨‍💻 🔥 ✨", "multiple emoji"),
    ("🎉🎊🎈", "emoji only"),

    # Final examples to reach 50
    ("This is a SideQuest AI testing fixture", "testing context"),
    ("Embedding model inference on Apple Neural Engine", "ANE context"),
    ("768-dimensional vector space", "numeric context"),
    ("gradient descent optimization algorithm", "ML context"),
]

# Ensure we have exactly 50 inputs
while len(test_inputs) < 50:
    test_inputs.append((f"test_{len(test_inputs)}", f"auto-generated test {len(test_inputs)}"))
test_inputs = test_inputs[:50]

# Generate fixtures
fixtures = []
for text, description in test_inputs:
    try:
        # Add special tokens (BOS token for EmbeddingGemma)
        token_ids = tok.encode(text, add_special_tokens=True)
        fixtures.append({
            "text": text,
            "expected_token_ids": token_ids,
            "description": description
        })
    except Exception as e:
        print(f"Error encoding '{text[:30]}...': {e}")

# Write to fixture file
output_path = 'client/macOS/SideQuestAppTests/sentencepiece-fixtures.json'
with open(output_path, 'w') as f:
    json.dump(fixtures, f, indent=2)

print(f"Generated {len(fixtures)} fixtures → {output_path}")
for i, fix in enumerate(fixtures[:5]):
    print(f"  [{i}] {fix['description']}: {len(fix['expected_token_ids'])} tokens")
print(f"  ...")
for i, fix in enumerate(fixtures[-3:], start=len(fixtures)-3):
    print(f"  [{i}] {fix['description']}: {len(fix['expected_token_ids'])} tokens")
