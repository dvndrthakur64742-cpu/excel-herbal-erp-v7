#!/usr/bin/env python3
import importlib.util
import pathlib
import unittest

spec = importlib.util.spec_from_file_location(
    "pack", pathlib.Path(__file__).with_name("pack-unified-plugin.py"))
pack = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pack)

class VersionEntrypointsTest(unittest.TestCase):
    def setUp(self):
        self.index = '<base href="/unchanged/"><script src="flutter_bootstrap.js" async></script>'
        self.bootstrap = '_flutter.buildConfig={"builds":[{"mainJsPath":"main.dart.js"},{}]};'
        self.a = "a" * 40
        self.b = "b" * 40

    def test_version_both_urls(self):
        index, bootstrap = pack.version_entrypoints(self.index, self.bootstrap, self.a)
        self.assertIn("flutter_bootstrap.js?v=" + self.a, index)
        self.assertIn("main.dart.js?v=" + self.a, bootstrap)
        self.assertIn('<base href="/unchanged/">', index)

    def test_new_release_invalidates_both_urls(self):
        self.assertNotEqual(pack.version_entrypoints(self.index, self.bootstrap, self.a)[0],
                            pack.version_entrypoints(self.index, self.bootstrap, self.b)[0])
        self.assertNotEqual(pack.version_entrypoints(self.index, self.bootstrap, self.a)[1],
                            pack.version_entrypoints(self.index, self.bootstrap, self.b)[1])

    def test_reject_missing_or_duplicate_entrypoints(self):
        for index, bootstrap in [("", self.bootstrap), (self.index * 2, self.bootstrap),
                                 (self.index, ""), (self.index, self.bootstrap * 2)]:
            with self.subTest(index=index, bootstrap=bootstrap):
                with self.assertRaises(ValueError):
                    pack.version_entrypoints(index, bootstrap, self.a)

    def test_reject_invalid_identity(self):
        with self.assertRaises(ValueError):
            pack.version_entrypoints(self.index, self.bootstrap, "../evil")

if __name__ == "__main__":
    unittest.main()
