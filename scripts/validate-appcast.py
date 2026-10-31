#!/usr/bin/env python3
"""Validate the release contract; cryptographic verification uses Sparkle separately."""
import base64
import pathlib
import sys
import xml.etree.ElementTree as ET

NS = {"s": "http://www.andymatuschak.org/xml-namespaces/sparkle"}


def validate(feed, archive, build, version, prefix):
    root = ET.parse(feed).getroot()
    items = root.findall("./channel/item")
    matches = [i for i in items if i.findtext("s:version", namespaces=NS) == build]
    if len(matches) != 1:
        raise ValueError("Appcast musí obsahovat právě jeden záznam aktuálního buildu.")
    item = matches[0]
    if item.findtext("s:shortVersionString", namespaces=NS) != version:
        raise ValueError("Nesouhlasí verze v appcastu.")
    enclosure = item.find("enclosure")
    if enclosure is None or enclosure.get("url") != prefix + archive.name:
        raise ValueError("Nesouhlasí URL instalačního souboru.")
    if int(enclosure.get("length", "0")) != archive.stat().st_size:
        raise ValueError("Nesouhlasí délka instalačního souboru.")
    signature = enclosure.get("{" + NS["s"] + "}edSignature", "")
    if len(base64.b64decode(signature, validate=True)) != 64:
        raise ValueError("Chybí Ed25519 podpis instalačního souboru.")
    return signature


if __name__ == "__main__":
    try:
        print(validate(pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]), *sys.argv[3:6]))
    except (ValueError, OSError, ET.ParseError, IndexError) as error:
        sys.exit(f"Neplatný appcast: {error}")
