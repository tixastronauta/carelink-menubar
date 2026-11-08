"""Synthetic regressions for the observed Flex timestamp schema."""
import unittest
from datetime import datetime, timezone
from carelink_proto.model import normalize

class FlexTimestampTests(unittest.TestCase):
    def sample(self, stamp="2026-07-01T13:00:00", zone="Europe/Lisbon"):
        return {"patientData": {"clientTimeZoneName": zone, "bgUnits": "MGDL",
            "lastSG": {"sg": 120, "timestamp": stamp},
            "activeInsulin": {"amount": 0.5},
            "sgs": [{"sg": 0, "kind": "SG", "version": 1},
                    {"sg": 120, "timestamp": stamp}]}}

    def test_explicit_zone_converts_local_timestamp(self):
        data = normalize(self.sample(), datetime(2026,7,1,12,tzinfo=timezone.utc))
        self.assertEqual(data["timestamp"], "2026-07-01T12:00:00+00:00")
        self.assertEqual(len(data["history"]), 1)
        self.assertFalse(data["stale"])
        self.assertIsNone(data["active_insulin_timestamp"])

    def test_winter_offset(self):
        data = normalize(self.sample("2026-10-28T13:00:00"))
        self.assertEqual(data["timestamp"], "2026-10-28T13:00:00+00:00")

    def test_unknown_zone_does_not_guess(self):
        data = normalize(self.sample(zone="unknown"))
        self.assertIsNone(data["timestamp"])
        self.assertEqual(data["history"], [])

    def test_dst_ambiguous_and_nonexistent_local_times_rejected(self):
        for stamp in ("2026-10-25T01:30:00", "2026-03-29T01:30:00"):
            data = normalize(self.sample(stamp))
            self.assertIsNone(data["timestamp"])
            self.assertEqual(data["history"], [])
