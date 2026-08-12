# Complete example

Every input the module takes, installing three real solutions that between them cover each shape the
module handles:

| Solution | Why it is here |
| --- | --- |
| Microsoft Defender XDR | 374 content templates at roughly 1.9 MB, and the only one shipping a data connector, so it exercises the largest payload and the `solutions_with_ui_only_connectors` output |
| Sentinel SOAR Essentials | 26 templates of playbooks and workbooks, no connector |
| SOC Handbook | 13 workbook templates, published by the community rather than Microsoft, so its publisher prefix differs |

`expected_version` is set explicitly to `null` rather than pinned: a real pin would go stale and break
this example's CI run the day Microsoft ships an update. Pin it in a real estate, where being told
about the change is the entire point.
