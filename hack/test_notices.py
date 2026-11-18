import base64
import contextlib
import hashlib
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import notices


class RenderTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.out_json = Path(self.tmp.name) / "notices.json"
        self.out_md = Path(self.tmp.name) / "notices.md"
        text = "Copyright Example\nPermission granted.\n"
        sha = hashlib.sha256(text.encode()).hexdigest()
        self.data = {
            "packages": [{
                "package": "example",
                "version": "1.0",
                "license": "MIT",
                "files": [{"path": "LICENSE", "sha256": sha, "origin": "source"}],
                "missing": [],
                "unavailable": [],
            }],
            "bundled": [],
            "texts": {sha: text},
        }

    def render(self):
        with patch.object(notices, "collect", return_value=self.data), \
                contextlib.redirect_stdout(io.StringIO()), \
                contextlib.redirect_stderr(io.StringIO()):
            notices.render("sources.json", "image.tar", "cache", self.out_json, self.out_md)

    def set_size(self, size):
        self.data["texts"]["padding"] = ""
        overhead = len((json.dumps(self.data, separators=(",", ":")) + "\n").encode())
        self.data["texts"]["padding"] = "x" * (size - overhead)

    def pages(self):
        return [json.loads(p.read_bytes()) for p in
                sorted(self.out_json.with_suffix(".pages").glob("page-*.json"))]

    def assemble(self, pages=None, indexes=None):
        index_path = self.out_json.with_suffix(".index.json")
        if indexes is not None:
            index_path.write_bytes(b"".join(notices.json_bytes(index) for index in indexes))
        pages_path = Path(self.tmp.name) / "verified-pages.jsonl"
        pages_path.write_bytes(b"".join(notices.json_bytes(page) for page in
                                      (self.pages() if pages is None else pages)))
        output = Path(self.tmp.name) / "reconstructed.json"
        notices.assemble(index_path, pages_path, output)
        self.assertEqual(output.read_bytes(), self.out_json.read_bytes())

    def test_compaction_preserves_notices_and_markdown(self):
        self.data["packages"] *= 300
        self.data["texts"]["unicode"] = "Copyright \u00a9 Example\n"
        self.set_size(notices.MAX_BYTES - 1024)
        pretty_size = len((json.dumps(self.data, indent=1) + "\n").encode())
        self.assertGreater(pretty_size, notices.MAX_BYTES)

        self.render()

        self.assertEqual(self.out_json.stat().st_size, notices.MAX_BYTES - 1024)
        self.assertEqual(json.loads(self.out_json.read_text()), self.data)
        self.assertEqual(self.out_md.read_text(), notices.markdown(self.data))
        for sha, text in self.data["texts"].items():
            if sha not in ("padding", "unicode"):
                self.assertEqual(hashlib.sha256(text.encode()).hexdigest(), sha)

    def test_large_document_is_paginated(self):
        self.set_size(3 * (1 << 20))
        self.render()
        self.assertGreater(self.out_json.stat().st_size, 1 << 20)
        self.assertGreater(len(self.pages()), 1)
        for path in self.out_json.with_suffix(".pages").glob("*.json"):
            self.assertLessEqual(path.stat().st_size, notices.MAX_BYTES)
        self.assertLessEqual(self.out_json.with_suffix(".index.json").stat().st_size, notices.MAX_BYTES)
        self.assemble()

    def test_exact_predicate_budget_is_accepted(self):
        predicate = {"data": ""}
        predicate["data"] = "x" * (notices.MAX_BYTES - len(notices.json_bytes(predicate)))
        notices.write_predicate(self.out_json, predicate)
        self.assertEqual(self.out_json.stat().st_size, notices.MAX_BYTES)
        predicate["data"] += "x"
        with self.assertRaisesRegex(ValueError, "over the .* attestation budget"):
            notices.write_predicate(self.out_json, predicate)

    def test_chunk_boundaries(self):
        for size in (notices.CHUNK_BYTES - 1, notices.CHUNK_BYTES, notices.CHUNK_BYTES + 1):
            with self.subTest(size=size):
                self.set_size(size)
                self.render()
                self.assertEqual(len(self.pages()), 1 if size <= notices.CHUNK_BYTES else 2)
                self.assemble()

    def test_large_individual_unicode_text_round_trips(self):
        text = "Copyright \u00a9 \u4e2d \U0001f430\n" * (notices.MAX_BYTES // 8)
        sha = hashlib.sha256(text.encode()).hexdigest()
        self.data["texts"][sha] = text
        self.render()
        self.assertGreater(len(self.pages()), 1)
        self.assemble(list(reversed(self.pages())))

    def test_stale_pages_are_removed(self):
        self.set_size(3 * notices.CHUNK_BYTES)
        self.render()
        self.assertEqual(len(self.pages()), 3)
        self.set_size(1024)
        self.render()
        self.assertEqual(len(self.pages()), 1)
        self.assemble()

    def test_missing_page_is_rejected_without_writing_output(self):
        self.set_size(2 * notices.CHUNK_BYTES)
        self.render()
        with self.assertRaisesRegex(ValueError, "missing notice pages: 2"):
            self.assemble(self.pages()[:1])
        self.assertFalse((Path(self.tmp.name) / "reconstructed.json").exists())

    def test_corrupted_page_is_rejected(self):
        self.render()
        pages = self.pages()
        chunk = base64.b64decode(pages[0]["data"])
        pages[0]["data"] = base64.b64encode(b"!" + chunk[1:]).decode()
        with self.assertRaisesRegex(ValueError, "size or SHA256 mismatch"):
            self.assemble(pages)

    def test_invalid_base64_is_rejected(self):
        self.render()
        pages = self.pages()
        pages[0]["data"] = "!"
        with self.assertRaisesRegex(ValueError, "invalid base64"):
            self.assemble(pages)

    def test_unexpected_page_number_is_rejected(self):
        self.render()
        pages = self.pages()
        pages[0]["number"] = 2
        with self.assertRaisesRegex(ValueError, "unexpected notice page number"):
            self.assemble(pages)

    def test_signing_retries_are_accepted(self):
        self.render()
        index = json.loads(self.out_json.with_suffix(".index.json").read_bytes())
        self.assemble(self.pages() * 2, [index, index])

    def test_conflicting_indexes_are_rejected(self):
        self.render()
        index = json.loads(self.out_json.with_suffix(".index.json").read_bytes())
        with self.assertRaisesRegex(ValueError, "one distinct notice index"):
            self.assemble(indexes=[index, {**index, "documentSize": 1}])

    def test_document_integrity_is_checked(self):
        self.render()
        index = json.loads(self.out_json.with_suffix(".index.json").read_bytes())
        index["documentSize"] += 1
        with self.assertRaisesRegex(ValueError, "notice document size or SHA256 mismatch"):
            self.assemble(indexes=[index])

    def test_document_hash_is_checked(self):
        self.render()
        index = json.loads(self.out_json.with_suffix(".index.json").read_bytes())
        index["documentSha256"] = "0" * 64
        pages = [{**page, "documentSha256": "0" * 64} for page in self.pages()]
        with self.assertRaisesRegex(ValueError, "notice document size or SHA256 mismatch"):
            self.assemble(pages, [index])

    def test_pages_from_other_documents_are_reported_and_ignored(self):
        self.render()
        foreign = {**self.pages()[0], "documentSha256": "0" * 64}
        with contextlib.redirect_stderr(io.StringIO()) as stderr:
            self.assemble([foreign, *self.pages()])
        self.assertIn("ignoring notice page for another document", stderr.getvalue())

    def test_invalid_indexes_are_rejected(self):
        self.render()
        index = json.loads(self.out_json.with_suffix(".index.json").read_bytes())
        for field, value in (("encoding", "gzip"), ("documentSha256", "bad"),
                             ("documentSize", -1), ("pages", []),
                             ("pages", [{**index["pages"][0], "number": 2}])):
            with self.subTest(field=field, value=value), self.assertRaises(ValueError):
                self.assemble(indexes=[{**index, field: value}])

    def test_missing_license_text_is_rejected(self):
        self.data["packages"][0]["files"] = []
        with self.assertRaisesRegex(SystemExit, "no license text at all for: example"):
            self.render()

    def test_reviewed_unlicensed_bundle_is_accepted(self):
        self.data["bundled"].append({
            "name": "reviewed",
            "bundled_in": "example",
            "license": "NOASSERTION",
            "files": [],
            "missing": [],
            "unavailable": [],
            "note": "reviewed by name and version",
        })
        self.render()
        self.assertEqual(json.loads(self.out_json.read_text()), self.data)


if __name__ == "__main__":
    unittest.main()
