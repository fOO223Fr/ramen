# SPDX-FileCopyrightText: The RamenDR authors
# SPDX-License-Identifier: Apache-2.0

import json
from . import kubectl


def list_osd_blocklist(cluster):
    """
    List osd block list.
    """
    try:
        out = tool(cluster, "ceph", "--format=json", "osd", "blocklist", "ls")
    except Exception:
        return []

    # We get invalid json from some Ceph versions:
    #
    #   \n[{"addr": "...", "until": "..."}][]
    #   or multiple concatenated arrays, or empty output
    #
    out = out.strip()
    if not out:
        return []
    if out.endswith("[]"):
        out = out[:-2]
    # Ceph may output invalid JSON (concatenated arrays, trailing []). Parse only
    # the first complete JSON value to avoid "Extra data" JSONDecodeError.
    try:
        obj, _ = json.JSONDecoder().raw_decode(out)
        return obj if isinstance(obj, list) else []
    except json.JSONDecodeError:
        return []


def clear_osd_blocklist(cluster):
    """
    Clear ceph osd blocklist.
    """
    tool(cluster, "ceph", "osd", "blocklist", "clear")


def set_config(cluster, who, option, value):
    """
    See https://docs.ceph.com/en/latest/rados/configuration/ceph-conf/#commands
    """
    tool(cluster, "ceph", "config", "set", who, option, value)


def rm_config(cluster, who, option):
    """
    See https://docs.ceph.com/en/latest/rados/configuration/ceph-conf/#commands
    """
    tool(cluster, "ceph", "config", "rm", who, option)


def tool(cluster, *args):
    return kubectl.exec(
        "deploy/rook-ceph-tools",
        "--namespace=rook-ceph",
        "--",
        *args,
        context=cluster,
    )
