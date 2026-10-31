import base64
import importlib.util
import pathlib
import tempfile
import unittest
import xml.etree.ElementTree as ET

spec = importlib.util.spec_from_file_location("appcast", pathlib.Path(__file__).resolve().parents[1] / "scripts/validate-appcast.py")
appcast = importlib.util.module_from_spec(spec)
spec.loader.exec_module(appcast)


class AppcastTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        directory = pathlib.Path(self.temporary.name)
        self.archive = directory / "Revision.dmg"
        self.archive.write_bytes(b"fixture")
        self.feed = directory / "appcast.xml"
        self.prefix = "https://example.invalid/releases/v1.3/"
        self.root = ET.Element("rss")
        self.item = ET.SubElement(ET.SubElement(self.root, "channel"), "item")
        ET.SubElement(self.item, "{" + appcast.NS["s"] + "}version").text = "13"
        ET.SubElement(self.item, "{" + appcast.NS["s"] + "}shortVersionString").text = "1.3"
        self.enclosure = ET.SubElement(self.item, "enclosure", {
            "url": self.prefix + self.archive.name, "length": "7",
            "{" + appcast.NS["s"] + "}edSignature": base64.b64encode(bytes(64)).decode(),
        })

    def validate(self):
        ET.ElementTree(self.root).write(self.feed)
        return appcast.validate(self.feed, self.archive, "13", "1.3", self.prefix)

    def test_valid_contract(self):
        self.assertEqual(len(base64.b64decode(self.validate())), 64)

    def test_wrong_build(self):
        self.item.find("s:version", appcast.NS).text = "12"
        with self.assertRaises(ValueError): self.validate()

    def test_duplicate_build(self):
        self.root.find("channel").append(self.item)
        with self.assertRaises(ValueError): self.validate()

    def test_wrong_version(self):
        self.item.find("s:shortVersionString", appcast.NS).text = "1.2"
        with self.assertRaises(ValueError): self.validate()

    def test_wrong_url(self):
        self.enclosure.set("url", "http://example.invalid/evil.dmg")
        with self.assertRaises(ValueError): self.validate()

    def test_wrong_size(self):
        self.enclosure.set("length", "9")
        with self.assertRaises(ValueError): self.validate()

    def test_missing_signature(self):
        del self.enclosure.attrib["{" + appcast.NS["s"] + "}edSignature"]
        with self.assertRaises(ValueError): self.validate()

    def test_invalid_signature(self):
        self.enclosure.set("{" + appcast.NS["s"] + "}edSignature", "not base64")
        with self.assertRaises(ValueError): self.validate()


if __name__ == "__main__": unittest.main()
