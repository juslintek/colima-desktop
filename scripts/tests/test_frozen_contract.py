#!/usr/bin/env python3
"""Property test for Frozen-contract preservation — Property 6 (task 1.5).

Feature: cross-platform-live-verification

This harness asserts design **Property 6 (Frozen-contract preservation)**:

    For any integrated state of the proto, the declared RPC set contains exactly
    31 ColimaService and 34 DockerService RPCs (65 total) with unchanged names and
    field numbers, EXCEPT for the approved pre-v1 additive scope fields recorded in
    INTENT_LEDGER.md (Update->ProfileRequest; PruneRequest.profile; host/wsl2 on
    RenameRequest/TagRequest/SearchRequest/NetworkContainerRequest).

    Validates: Requirements 2.1

It is fully self-contained: it ships a hardcoded **golden frozen baseline** (the 65 RPC
signatures split by service, plus every message's field->number map), an independent proto
parser, a proto serializer that round-trips through the parser (and can permute order +
inject formatting noise), and a `check_frozen_contract` function that compares a parsed
proto snapshot to the golden baseline and returns categorized violations.

The baseline is typed independently from the v1.1 contract (CONTRACT.md + the
`2026-07-18T20:25Z`/`20:39Z` contract-integration ledger entries), so "the checker accepts
the real proto" is a genuine regression guard rather than a tautology: if `colima_ui.proto`
ever drifts from the frozen surface, the deterministic anchor fails loudly.

The proto is **read-only** — this harness never modifies `proto/colima_ui.proto`; all mutated
snapshots are generated in memory and serialized to strings.

Three correctness properties are asserted over >=100 randomized iterations each, all tagged
`Feature: cross-platform-live-verification, Property 6`:

  * Property 6a — permutation / reformat invariance
      A proto whose RPC / message / field declaration order is permuted (and whose comments
      and whitespace are perturbed) but whose RPC set and field numbers are unchanged is
      ACCEPTED (zero violations) and still declares 65 RPCs.

  * Property 6b — single-mutation rejection
      A proto with one randomized invariant-violating mutation (add / rename / remove / move
      an RPC, or renumber / swap / remove / add a field) is REJECTED, and the rejection cites
      the violation category matching the mutation (not merely "some violation").

  * Property 6c — compound-mutation rejection
      A proto with a sequence of 1..3 violating mutations (optionally also permuted) is still
      REJECTED — permutation never masks a real contract break, and mutations do not cancel.

Runnable directly (writes a summary log + JSON to /tmp and exits nonzero on any failure):

    python3 scripts/tests/test_frozen_contract.py               # 200 iters/property
    python3 scripts/tests/test_frozen_contract.py --iters 300 --seed 42

and under pytest (the test_* functions assert zero property failures, >=100 iters).

It NEVER modifies `proto/colima_ui.proto`. If the real proto fails the baseline anchor, that
is surfaced as a counterexample (a real contract-drift finding), never silently patched.
"""

from __future__ import annotations

import argparse
import copy
import json
import os
import random
import re
import sys
import time
import traceback
from pathlib import Path

# --------------------------------------------------------------------------- #
# Locations
# --------------------------------------------------------------------------- #
REPO_ROOT = Path(__file__).resolve().parents[2]
PROTO_PATH = REPO_ROOT / "proto" / "colima_ui.proto"

LOG_PATH = Path(os.environ.get("FROZEN_LOG", "/tmp/frozen_contract_pbt.log"))
SUMMARY_PATH = Path(os.environ.get("FROZEN_SUMMARY", "/tmp/frozen_contract_pbt_summary.json"))

_LOG_FH = None


def log(msg: str) -> None:
    """Print to stdout and (if open) to the /tmp log, flushed, so a backgrounded run can be
    observed by reading the file back."""
    line = str(msg)
    print(line, flush=True)
    global _LOG_FH
    if _LOG_FH is not None:
        _LOG_FH.write(line + "\n")
        _LOG_FH.flush()


# --------------------------------------------------------------------------- #
# Golden frozen baseline (v1.1) — typed independently from CONTRACT.md + proto.
#
# FROZEN_RPCS: service -> { rpc_name: (request_type, response_type, server_stream) }
# FROZEN_FIELDS: message -> { field_name: field_number }
#
# The v1.1 approved additive scope fields are BAKED IN here (they are the accepted
# current state): Update's request is ProfileRequest; PruneRequest has profile=2;
# Rename/Tag/Search/NetworkContainer requests carry host/wsl2. See APPROVED_ADDITIVE.
# --------------------------------------------------------------------------- #
EXPECTED_COLIMA_RPCS = 31
EXPECTED_DOCKER_RPCS = 34
EXPECTED_TOTAL_RPCS = EXPECTED_COLIMA_RPCS + EXPECTED_DOCKER_RPCS  # 65

FROZEN_RPCS: dict[str, dict[str, tuple[str, str, bool]]] = {
    "ColimaService": {
        "Start": ("StartRequest", "ProgressEvent", True),
        "Stop": ("StopRequest", "StatusResponse", False),
        "Restart": ("RestartRequest", "ProgressEvent", True),
        "Delete": ("DeleteRequest", "StatusResponse", False),
        "Status": ("StatusRequest", "VMStatus", False),
        "Version": ("Empty", "VersionResponse", False),
        "Update": ("ProfileRequest", "StatusResponse", False),          # v1.1 additive scope
        "Prune": ("PruneRequest", "StatusResponse", False),
        "SSHConfig": ("ProfileRequest", "SSHConfigResponse", False),
        "ListProfiles": ("Empty", "ProfileList", False),
        "ListMachines": ("Empty", "MachineList", False),
        "CreateProfile": ("CreateProfileRequest", "StatusResponse", False),
        "DeleteProfile": ("DeleteProfileRequest", "StatusResponse", False),
        "CloneProfile": ("CloneProfileRequest", "StatusResponse", False),
        "GetConfig": ("ProfileRequest", "ColimaConfig", False),
        "SetConfig": ("SetConfigRequest", "StatusResponse", False),
        "GetTemplate": ("Empty", "ColimaConfig", False),
        "SetTemplate": ("ColimaConfig", "StatusResponse", False),
        "KubernetesStart": ("ProfileRequest", "StatusResponse", False),
        "KubernetesStop": ("ProfileRequest", "StatusResponse", False),
        "KubernetesReset": ("ProfileRequest", "StatusResponse", False),
        "KubernetesExec": ("KubeExecRequest", "KubeExecResponse", False),
        "ModelSetup": ("ModelRequest", "ProgressEvent", True),
        "ModelRun": ("ModelRunRequest", "ProgressEvent", True),
        "ModelServe": ("ModelServeRequest", "StatusResponse", False),
        "ModelStop": ("ProfileRequest", "StatusResponse", False),
        "SwitchRuntime": ("SwitchRuntimeRequest", "StatusResponse", False),
        "UpdateRuntime": ("ProfileRequest", "StatusResponse", False),
        "VMStats": ("ProfileRequest", "VMStatsEvent", True),
        "ProcessList": ("ProfileRequest", "ProcessListResponse", False),
        "KillProcess": ("KillProcessRequest", "StatusResponse", False),
    },
    "DockerService": {
        "ListContainers": ("DockerScope", "JsonResponse", False),
        "ContainerAction": ("ContainerActionRequest", "StatusResponse", False),
        "CreateContainer": ("CreateContainerRequest", "JsonResponse", False),
        "RenameContainer": ("RenameRequest", "StatusResponse", False),         # v1.1 host/wsl2
        "ContainerLogs": ("IdRequest", "JsonResponse", False),
        "InspectContainer": ("IdRequest", "JsonResponse", False),
        "ContainerTop": ("IdRequest", "JsonResponse", False),
        "ContainerStats": ("IdRequest", "JsonResponse", False),
        "ContainerChanges": ("IdRequest", "JsonResponse", False),
        "PruneContainers": ("DockerScope", "JsonResponse", False),
        "ListImages": ("DockerScope", "JsonResponse", False),
        "PullImage": ("NameRequest", "ProgressEvent", True),
        "RemoveImage": ("IdRequest", "StatusResponse", False),
        "InspectImage": ("NameRequest", "JsonResponse", False),
        "ImageHistory": ("NameRequest", "JsonResponse", False),
        "TagImage": ("TagRequest", "StatusResponse", False),                   # v1.1 host/wsl2
        "PushImage": ("NameRequest", "ProgressEvent", True),
        "SearchImages": ("SearchRequest", "JsonResponse", False),              # v1.1 host/wsl2
        "PruneImages": ("DockerScope", "JsonResponse", False),
        "ListVolumes": ("DockerScope", "JsonResponse", False),
        "CreateVolume": ("NameRequest", "JsonResponse", False),
        "RemoveVolume": ("NameRequest", "StatusResponse", False),
        "InspectVolume": ("NameRequest", "JsonResponse", False),
        "PruneVolumes": ("DockerScope", "JsonResponse", False),
        "ListNetworks": ("DockerScope", "JsonResponse", False),
        "CreateNetwork": ("NameRequest", "JsonResponse", False),
        "RemoveNetwork": ("IdRequest", "StatusResponse", False),
        "InspectNetwork": ("IdRequest", "JsonResponse", False),
        "ConnectNetwork": ("NetworkContainerRequest", "StatusResponse", False),      # v1.1 host/wsl2
        "DisconnectNetwork": ("NetworkContainerRequest", "StatusResponse", False),   # v1.1 host/wsl2
        "PruneNetworks": ("DockerScope", "JsonResponse", False),
        "StreamEvents": ("DockerScope", "JsonResponse", True),
        "StreamLogs": ("IdRequest", "JsonResponse", True),
        "StreamStats": ("IdRequest", "JsonResponse", True),
    },
}

FROZEN_FIELDS: dict[str, dict[str, int]] = {
    "Empty": {},
    "StatusResponse": {"success": 1, "message": 2, "error": 3},
    "ProgressEvent": {"stage": 1, "message": 2, "progress": 3, "done": 4, "error": 5},
    "ProfileRequest": {"profile": 1},
    "StartRequest": {"profile": 1, "config": 2},
    "StopRequest": {"profile": 1, "force": 2},
    "RestartRequest": {"profile": 1},
    "DeleteRequest": {"profile": 1, "data": 2, "force": 3},
    "StatusRequest": {"profile": 1, "extended": 2},
    "VMStatus": {
        "running": 1, "display_name": 2, "driver": 3, "arch": 4, "runtime": 5,
        "mount_type": 6, "ip_address": 7, "docker_socket": 8, "kubernetes": 9,
        "cpu": 10, "memory": 11, "disk": 12, "version": 13,
    },
    "VersionResponse": {"version": 1, "revision": 2},
    "PruneRequest": {"all": 1, "profile": 2},  # profile=2 is the v1.1 additive scope field
    "SSHConfigResponse": {"config": 1, "host": 2, "port": 3, "user": 4, "identity_file": 5},
    "ProfileList": {"profiles": 1},
    "ProfileInfo": {
        "name": 1, "status": 2, "arch": 3, "cpus": 4, "memory": 5, "disk": 6,
        "runtime": 7, "ip_address": 8,
    },
    "CreateProfileRequest": {"name": 1, "config": 2},
    "DeleteProfileRequest": {"name": 1, "data": 2, "force": 3},
    "CloneProfileRequest": {"source": 1, "destination": 2},
    "MachineList": {"machines": 1},
    "MachineInfo": {
        "name": 1, "status": 2, "arch": 3, "cpus": 4, "memory": 5, "disk": 6,
        "os": 7, "dir": 8,
    },
    "ColimaConfig": {
        "cpu": 1, "memory": 2, "disk": 3, "root_disk": 4, "arch": 5, "vm_type": 6,
        "cpu_type": 7, "rosetta": 8, "nested_virtualization": 9, "hostname": 10,
        "disk_image": 11, "binfmt": 12, "port_forwarder": 13, "runtime": 14,
        "auto_activate": 15, "model_runner": 16, "mount_type": 17, "mount_inotify": 18,
        "forward_agent": 19, "ssh_config": 20, "ssh_port": 21, "network": 22,
        "kubernetes": 23, "docker": 24, "mounts": 25, "provision": 26, "env": 27,
    },
    "NetworkConfig": {
        "address": 1, "mode": 2, "interface": 3, "dns": 4, "dns_hosts": 5,
        "gateway_address": 6, "host_addresses": 7, "preferred_route": 8,
    },
    "KubernetesConfig": {"enabled": 1, "version": 2, "k3s_args": 3, "port": 4},
    "Mount": {"location": 1, "mount_point": 2, "writable": 3},
    "Provision": {"mode": 1, "script": 2},
    "SetConfigRequest": {"profile": 1, "config": 2},
    "KubeExecRequest": {"profile": 1, "command": 2},
    "KubeExecResponse": {"output": 1, "error": 2, "exit_code": 3},
    "ModelRequest": {"profile": 1, "runner": 2},
    "ModelRunRequest": {"profile": 1, "model": 2, "runner": 3, "prompt": 4},
    "ModelServeRequest": {"profile": 1, "model": 2, "runner": 3, "port": 4},
    "SwitchRuntimeRequest": {"profile": 1, "runtime": 2},
    "VMStatsEvent": {
        "cpu_percent": 1, "memory_used": 2, "memory_total": 3, "disk_used": 4,
        "disk_total": 5, "timestamp": 6,
    },
    "ProcessListResponse": {"processes": 1},
    "ProcessInfo": {
        "pid": 1, "user": 2, "cpu_percent": 3, "memory_percent": 4, "command": 5,
        "container": 6,
    },
    "KillProcessRequest": {"profile": 1, "pid": 2, "signal": 3},
    "DockerScope": {"profile": 1, "all": 2, "host": 3, "wsl2": 4},  # host/wsl2 pre-existing here
    "JsonResponse": {"json": 1, "error": 2},
    "IdRequest": {"id": 1, "profile": 2, "host": 3, "wsl2": 4},
    "NameRequest": {"name": 1, "profile": 2, "host": 3, "wsl2": 4},
    "ContainerActionRequest": {"id": 1, "action": 2, "profile": 3, "host": 4, "wsl2": 5},
    "CreateContainerRequest": {"name": 1, "image": 2, "profile": 3, "host": 4, "wsl2": 5},
    "RenameRequest": {"id": 1, "new_name": 2, "profile": 3, "host": 4, "wsl2": 5},   # v1.1 host/wsl2
    "TagRequest": {"name": 1, "repo": 2, "tag": 3, "profile": 4, "host": 5, "wsl2": 6},  # v1.1
    "SearchRequest": {"term": 1, "profile": 2, "host": 3, "wsl2": 4},                # v1.1 host/wsl2
    "NetworkContainerRequest": {
        "network_id": 1, "container_id": 2, "profile": 3, "host": 4, "wsl2": 5,      # v1.1 host/wsl2
    },
}

# The approved pre-v1 additive scope corrections the task calls out explicitly. Each is a
# claim about the frozen v1.1 shape that the deterministic anchor asserts against the REAL
# proto (Update's request type, and the exact numbers of the added scope fields).
APPROVED_ADDITIVE_RPC_REQUEST = {("ColimaService", "Update"): "ProfileRequest"}
APPROVED_ADDITIVE_FIELDS = {
    ("PruneRequest", "profile"): 2,
    ("RenameRequest", "host"): 4, ("RenameRequest", "wsl2"): 5,
    ("TagRequest", "host"): 5, ("TagRequest", "wsl2"): 6,
    ("SearchRequest", "host"): 3, ("SearchRequest", "wsl2"): 4,
    ("NetworkContainerRequest", "host"): 4, ("NetworkContainerRequest", "wsl2"): 5,
}


# --------------------------------------------------------------------------- #
# Proto parser (self-contained; RPC set + message field numbers)
# --------------------------------------------------------------------------- #
_SERVICE_RE = re.compile(r"^\s*service\s+(\w+)\s*\{")
_RPC_RE = re.compile(
    r"^\s*rpc\s+(\w+)\s*\(\s*(\w+)\s*\)\s*returns\s*\(\s*(stream\s+)?(\w+)\s*\)"
)
_MSG_OPEN_RE = re.compile(r"^\s*message\s+(\w+)\s*\{\s*(\})?\s*$")
# type = optional repeated/optional qualifier + (map<...> | dotted identifier)
_FIELD_RE = re.compile(
    r"^\s*((?:(?:repeated|optional)\s+)?(?:map\s*<[^>]+>|[A-Za-z_][\w.]*))\s+"
    r"([A-Za-z_]\w*)\s*=\s*(\d+)\s*;"
)


def parse_contract(text: str) -> dict:
    """Parse proto text into {'services': {svc: {rpc: (req, resp, stream)}},
    'messages': {msg: {field_name: number}}}.

    A linear state machine assigns rpc lines to the open `service X { ... }` block and
    field lines to the open `message Y { ... }` block; a lone `}` closes the current block.
    `message Empty {}` (open+close on one line) yields an empty field map.
    """
    services: dict[str, dict[str, tuple[str, str, bool]]] = {}
    messages: dict[str, dict[str, int]] = {}
    ctx: tuple[str, str] | None = None
    for line in text.splitlines():
        if ctx is None:
            svc = _SERVICE_RE.match(line)
            if svc:
                ctx = ("service", svc.group(1))
                services.setdefault(svc.group(1), {})
                continue
            msg = _MSG_OPEN_RE.match(line)
            if msg:
                name = msg.group(1)
                messages.setdefault(name, {})
                if msg.group(2) != "}":  # block stays open (multi-line message)
                    ctx = ("message", name)
                continue
            continue
        kind, name = ctx
        if line.strip() == "}":
            ctx = None
            continue
        if kind == "service":
            rpc = _RPC_RE.match(line)
            if rpc:
                services[name][rpc.group(1)] = (rpc.group(2), rpc.group(4), bool(rpc.group(3)))
        else:  # message
            fld = _FIELD_RE.match(line)
            if fld:
                messages[name][fld.group(2)] = int(fld.group(3))
    return {"services": services, "messages": messages}


def parse_model(text: str) -> dict:
    """Parse proto text into an ORDER-PRESERVING, field-typed model for mutation/serialization:

        {'services':  [[svc_name, [[rpc, req, resp, stream], ...]], ...],
         'messages':  [[msg_name, [[ftype, fname, fnum], ...]], ...]}

    Lists (not tuples) so mutators can edit in place; declaration order is preserved so a
    round-trip serialize->parse reproduces the source contract exactly.
    """
    services: list = []
    messages: list = []
    svc_index: dict[str, list] = {}
    msg_index: dict[str, list] = {}
    ctx: tuple[str, str] | None = None
    for line in text.splitlines():
        if ctx is None:
            svc = _SERVICE_RE.match(line)
            if svc:
                name = svc.group(1)
                if name not in svc_index:
                    entry = [name, []]
                    svc_index[name] = entry
                    services.append(entry)
                ctx = ("service", name)
                continue
            msg = _MSG_OPEN_RE.match(line)
            if msg:
                name = msg.group(1)
                if name not in msg_index:
                    entry = [name, []]
                    msg_index[name] = entry
                    messages.append(entry)
                if msg.group(2) != "}":
                    ctx = ("message", name)
                continue
            continue
        kind, name = ctx
        if line.strip() == "}":
            ctx = None
            continue
        if kind == "service":
            rpc = _RPC_RE.match(line)
            if rpc:
                svc_index[name][1].append(
                    [rpc.group(1), rpc.group(2), rpc.group(4), bool(rpc.group(3))]
                )
        else:
            fld = _FIELD_RE.match(line)
            if fld:
                ftype = re.sub(r"\s+", " ", fld.group(1).strip())
                msg_index[name][1].append([ftype, fld.group(2), int(fld.group(3))])
    return {"services": services, "messages": messages}


def serialize_model(model: dict, rng: random.Random | None = None, *,
                    permute: bool = False, noise: bool = False) -> str:
    """Serialize a parse_model() model back to proto text that parse_contract/parse_model
    can re-parse. When permute is set (with an rng), the order of services, RPCs, messages,
    and fields is shuffled — field NUMBERS stay attached to their names, so a permuted proto
    is semantically identical. When noise is set, comments and indentation are perturbed.
    """
    lines = [
        'syntax = "proto3";',
        "",
        "package colimaui;",
        "",
        'option go_package = "github.com/colima-desktop/daemon/proto";',
        "",
    ]

    services = [[s[0], list(s[1])] for s in model["services"]]
    messages = [[m[0], list(m[1])] for m in model["messages"]]
    if permute and rng is not None:
        rng.shuffle(services)
        rng.shuffle(messages)

    for svc_name, rpcs in services:
        rpcs = list(rpcs)
        if permute and rng is not None:
            rng.shuffle(rpcs)
        lines.append("service %s {" % svc_name)
        for name, req, resp, stream in rpcs:
            if noise and rng is not None and rng.random() < 0.25:
                lines.append("  // rpc %s" % name)
            indent = "    " if (noise and rng is not None and rng.random() < 0.25) else "  "
            stream_kw = "stream " if stream else ""
            lines.append("%srpc %s(%s) returns (%s%s);" % (indent, name, req, stream_kw, resp))
        lines.append("}")
        lines.append("")

    for msg_name, fields in messages:
        fields = list(fields)
        if permute and rng is not None:
            rng.shuffle(fields)
        if not fields:
            lines.append("message %s {}" % msg_name)
            lines.append("")
            continue
        lines.append("message %s {" % msg_name)
        for ftype, fname, fnum in fields:
            if noise and rng is not None and rng.random() < 0.2:
                lines.append("  // field %s" % fname)
            lines.append("  %s %s = %d;" % (ftype, fname, fnum))
        lines.append("}")
        lines.append("")

    return "\n".join(lines) + "\n"


# --------------------------------------------------------------------------- #
# The checker: compare a parsed snapshot to the golden frozen baseline
# --------------------------------------------------------------------------- #
def check_frozen_contract(snapshot: dict) -> list[str]:
    """Return a sorted list of violation strings; an empty list means ACCEPTED.

    Enforces the frozen v1.1 surface:
      * each service's RPC set == baseline (missing / extra / count), and each shared RPC's
        (request, response, server_stream) signature matches (catches Update->ProfileRequest
        reversions and rename/retarget);
      * an extra service is rejected (each of its RPCs is reported);
      * total RPC count == 65;
      * every baseline message is present and its field->number map matches EXACTLY — a
        renumbered field (`field-number`), a dropped field (`field-missing`), or an
        unapproved added field (`field-extra`) is a violation. The approved additive scope
        fields are part of the baseline, so the real proto is accepted.

    Extra messages absent from the baseline are out of scope (they do not change the frozen
    RPC surface) and are not reported.
    """
    violations: list[str] = []
    services = snapshot["services"]
    messages = snapshot["messages"]

    # ---- Per-service RPC set, signatures, counts ----
    for svc, frozen in FROZEN_RPCS.items():
        got = services.get(svc, {})
        if len(got) != len(frozen):
            violations.append("rpc-count:%s expected=%d got=%d" % (svc, len(frozen), len(got)))
        for name, sig in frozen.items():
            if name not in got:
                violations.append("rpc-missing:%s.%s" % (svc, name))
            elif tuple(got[name]) != tuple(sig):
                violations.append(
                    "rpc-signature:%s.%s expected=%r got=%r" % (svc, name, sig, got[name])
                )
        for name in got:
            if name not in frozen:
                violations.append("rpc-extra:%s.%s" % (svc, name))

    # extra services (not in the frozen contract at all)
    for svc, got in services.items():
        if svc not in FROZEN_RPCS:
            for name in got:
                violations.append("rpc-extra:%s.%s" % (svc, name))

    # total RPC count across all declared services
    total = sum(len(v) for v in services.values())
    if total != EXPECTED_TOTAL_RPCS:
        violations.append("rpc-total expected=%d got=%d" % (EXPECTED_TOTAL_RPCS, total))

    # ---- Per-message field numbers (exact) ----
    for msg, frozen_fields in FROZEN_FIELDS.items():
        got = messages.get(msg)
        if got is None:
            violations.append("message-missing:%s" % msg)
            continue
        for fname, fnum in frozen_fields.items():
            if fname not in got:
                violations.append("field-missing:%s.%s" % (msg, fname))
            elif got[fname] != fnum:
                violations.append(
                    "field-number:%s.%s expected=%d got=%d" % (msg, fname, fnum, got[fname])
                )
        for fname in got:
            if fname not in frozen_fields:
                violations.append("field-extra:%s.%s" % (msg, fname))

    return sorted(violations)


def check_proto_text(text: str) -> list[str]:
    """Parse proto text and return frozen-contract violations (empty list = accepted)."""
    return check_frozen_contract(parse_contract(text))


# --------------------------------------------------------------------------- #
# Mutators (each returns the violation-category substring it is expected to trigger)
# --------------------------------------------------------------------------- #
def _nonempty_services(model):
    return [s for s in model["services"] if s[1]]


def _messages_with_fields(model):
    return [m for m in model["messages"] if m[1]]


def mut_add_rpc(model, rng):
    svc = rng.choice(model["services"])
    existing = {r[0] for r in svc[1]}
    name = "Injected%d" % rng.randint(0, 1_000_000)
    while name in existing:
        name += "X"
    svc[1].append([name, "Empty", "StatusResponse", False])
    return "rpc-extra:%s.%s" % (svc[0], name)


def mut_remove_rpc(model, rng):
    svc = rng.choice(_nonempty_services(model))
    removed = svc[1].pop(rng.randrange(len(svc[1])))
    return "rpc-missing:%s.%s" % (svc[0], removed[0])


def mut_rename_rpc(model, rng):
    svc = rng.choice(_nonempty_services(model))
    entry = rng.choice(svc[1])
    old = entry[0]
    entry[0] = "%sRenamed%d" % (old, rng.randint(0, 9999))
    return "rpc-missing:%s.%s" % (svc[0], old)  # old name disappears from the service


def mut_move_rpc(model, rng):
    src = rng.choice(_nonempty_services(model))
    others = [s for s in model["services"] if s[0] != src[0]]
    if not others:
        return mut_add_rpc(model, rng)
    dst = rng.choice(others)
    entry = src[1].pop(rng.randrange(len(src[1])))
    dst[1].append(entry)
    return "rpc-missing:%s.%s" % (src[0], entry[0])  # source service loses it


def mut_renumber_field(model, rng):
    msg = rng.choice(_messages_with_fields(model))
    field = rng.choice(msg[1])
    used = {f[2] for f in msg[1]}
    field[2] = max(used) + rng.randint(1, 50)  # guaranteed unused and != old
    return "field-number:%s.%s" % (msg[0], field[1])


def mut_swap_field_numbers(model, rng):
    candidates = [m for m in model["messages"] if len(m[1]) >= 2]
    if not candidates:
        return mut_renumber_field(model, rng)
    msg = rng.choice(candidates)
    a, b = rng.sample(msg[1], 2)
    a[2], b[2] = b[2], a[2]  # both numbers now disagree with the baseline
    return "field-number:%s." % msg[0]


def mut_remove_field(model, rng):
    msg = rng.choice(_messages_with_fields(model))
    removed = msg[1].pop(rng.randrange(len(msg[1])))
    return "field-missing:%s.%s" % (msg[0], removed[1])


def mut_add_field(model, rng):
    msg = rng.choice(model["messages"])
    used = {f[2] for f in msg[1]}
    fnum = (max(used) + rng.randint(1, 50)) if used else rng.randint(1, 50)
    name = "injected_%d" % rng.randint(0, 1_000_000)
    while any(f[1] == name for f in msg[1]):
        name += "x"
    msg[1].append(["string", name, fnum])
    return "field-extra:%s.%s" % (msg[0], name)


MUTATORS = [
    ("add_rpc", mut_add_rpc),
    ("remove_rpc", mut_remove_rpc),
    ("rename_rpc", mut_rename_rpc),
    ("move_rpc", mut_move_rpc),
    ("renumber_field", mut_renumber_field),
    ("swap_field_numbers", mut_swap_field_numbers),
    ("remove_field", mut_remove_field),
    ("add_field", mut_add_field),
]


# --------------------------------------------------------------------------- #
# Real proto model (parsed once at import; the golden anchor for permute/mutate)
# --------------------------------------------------------------------------- #
def _load_real_model():
    text = PROTO_PATH.read_text(encoding="utf-8")
    return text, parse_model(text)


REAL_PROTO_TEXT, BASE_MODEL = _load_real_model()


# --------------------------------------------------------------------------- #
# Result accumulator
# --------------------------------------------------------------------------- #
class PropResult:
    def __init__(self, name):
        self.name = name
        self.ran = 0
        self.passed = 0
        self.failures = []  # list of counterexample dicts

    @property
    def failed(self):
        return len(self.failures)

    def record_pass(self):
        self.ran += 1
        self.passed += 1

    def record_fail(self, detail):
        self.ran += 1
        self.failures.append(detail)
        if len(self.failures) <= 5:
            log("  [COUNTEREXAMPLE] %s" % json.dumps(detail)[:600])


def _short_tb():
    return traceback.format_exc().strip().splitlines()[-1]


# --------------------------------------------------------------------------- #
# Property 6a — permutation / reformat invariance -> accepted
# --------------------------------------------------------------------------- #
def run_property_permutation(seed_rng, iters):
    r = PropResult("Property 6a (permutation/reformat invariance -> accepted)")
    for _ in range(iters):
        iseed = seed_rng.randrange(2 ** 63)
        rng = random.Random(iseed)
        try:
            text = serialize_model(BASE_MODEL, rng, permute=True, noise=True)
            snap = parse_contract(text)

            total = sum(len(v) for v in snap["services"].values())
            assert total == EXPECTED_TOTAL_RPCS, "permuted proto has %d RPCs (want 65)" % total
            assert len(snap["services"].get("ColimaService", {})) == EXPECTED_COLIMA_RPCS, \
                "permuted ColimaService count wrong"
            assert len(snap["services"].get("DockerService", {})) == EXPECTED_DOCKER_RPCS, \
                "permuted DockerService count wrong"

            violations = check_frozen_contract(snap)
            assert violations == [], "permutation wrongly REJECTED: %r" % violations[:8]
            r.record_pass()
        except Exception as e:
            r.record_fail({"iter_seed": iseed, "error": repr(e), "where": _short_tb()})
    return r


# --------------------------------------------------------------------------- #
# Property 6b — single violating mutation -> rejected for the matching reason
# --------------------------------------------------------------------------- #
def run_property_single_mutation(seed_rng, iters):
    r = PropResult("Property 6b (single violating mutation -> rejected)")
    for _ in range(iters):
        iseed = seed_rng.randrange(2 ** 63)
        rng = random.Random(iseed)
        mname = None
        try:
            model = copy.deepcopy(BASE_MODEL)
            mname, mfn = rng.choice(MUTATORS)
            expected = mfn(model, rng)

            # optionally permute + add noise so rejection is not order-dependent
            text = serialize_model(model, rng, permute=rng.random() < 0.5, noise=True)
            violations = check_proto_text(text)

            assert violations, "mutation %s was ACCEPTED (should be rejected)" % mname
            assert any(expected in v for v in violations), (
                "mutation %s rejected for the WRONG reason; expected substring %r not in %r"
                % (mname, expected, violations[:12])
            )
            r.record_pass()
        except Exception as e:
            r.record_fail(
                {"iter_seed": iseed, "mutation": mname, "error": repr(e), "where": _short_tb()}
            )
    return r


# --------------------------------------------------------------------------- #
# Property 6c — compound (1..3) violating mutations -> still rejected
# --------------------------------------------------------------------------- #
def run_property_compound_mutation(seed_rng, iters):
    r = PropResult("Property 6c (compound violating mutations -> rejected)")
    for _ in range(iters):
        iseed = seed_rng.randrange(2 ** 63)
        rng = random.Random(iseed)
        applied = []
        try:
            model = copy.deepcopy(BASE_MODEL)
            k = rng.randint(1, 3)
            expected_subs = []
            for _ in range(k):
                mname, mfn = rng.choice(MUTATORS)
                expected_subs.append(mfn(model, rng))
                applied.append(mname)

            text = serialize_model(model, rng, permute=rng.random() < 0.5, noise=True)
            violations = check_proto_text(text)

            assert violations, "compound mutations %r were ACCEPTED" % applied
            # at least one applied mutation's category must be cited (mutations can overlap,
            # e.g. remove_field then add_field on the same message, so we require >=1 match)
            assert any(any(sub in v for v in violations) for sub in expected_subs), (
                "compound %r rejected but none of %r appear in %r"
                % (applied, expected_subs, violations[:12])
            )
            r.record_pass()
        except Exception as e:
            r.record_fail(
                {"iter_seed": iseed, "mutations": applied, "error": repr(e), "where": _short_tb()}
            )
    return r


# --------------------------------------------------------------------------- #
# Deterministic checks (hand-verified) + real-proto anchor
# --------------------------------------------------------------------------- #
def run_deterministic_checks():
    """Fixed, hand-verified cases. Returns list of (name, ok, detail)."""
    results = []

    def check(name, fn):
        try:
            fn()
            results.append((name, True, "ok"))
        except Exception as e:
            results.append((name, False, "%r | %s" % (e, _short_tb())))

    # ---- Baseline internal consistency ----
    def baseline_counts():
        assert len(FROZEN_RPCS["ColimaService"]) == EXPECTED_COLIMA_RPCS, \
            "baseline ColimaService has %d" % len(FROZEN_RPCS["ColimaService"])
        assert len(FROZEN_RPCS["DockerService"]) == EXPECTED_DOCKER_RPCS, \
            "baseline DockerService has %d" % len(FROZEN_RPCS["DockerService"])
        total = sum(len(v) for v in FROZEN_RPCS.values())
        assert total == EXPECTED_TOTAL_RPCS, "baseline total %d" % total

    check("baseline declares exactly 31 + 34 = 65 RPCs", baseline_counts)

    # ---- Real proto parses to 31 + 34 = 65 ----
    def real_counts():
        snap = parse_contract(REAL_PROTO_TEXT)
        c = len(snap["services"].get("ColimaService", {}))
        d = len(snap["services"].get("DockerService", {}))
        assert c == EXPECTED_COLIMA_RPCS, "real ColimaService parsed %d (want 31)" % c
        assert d == EXPECTED_DOCKER_RPCS, "real DockerService parsed %d (want 34)" % d
        assert c + d == EXPECTED_TOTAL_RPCS

    check("real proto parses to 31 ColimaService + 34 DockerService", real_counts)

    # ---- Real proto is ACCEPTED by the checker (regression anchor) ----
    def real_accepted():
        violations = check_proto_text(REAL_PROTO_TEXT)
        assert violations == [], "real proto REJECTED by frozen checker: %r" % violations[:20]

    check("real proto is accepted (zero violations vs golden baseline)", real_accepted)

    # ---- Approved additive scope fields present with exact numbers in the REAL proto ----
    def additive_present():
        snap = parse_contract(REAL_PROTO_TEXT)
        # Update -> ProfileRequest
        for (svc, rpc), req in APPROVED_ADDITIVE_RPC_REQUEST.items():
            got = snap["services"][svc][rpc]
            assert got[0] == req, "%s.%s request is %r, want %r" % (svc, rpc, got[0], req)
        # PruneRequest.profile / host+wsl2 on Rename/Tag/Search/NetworkContainer
        for (msg, field), num in APPROVED_ADDITIVE_FIELDS.items():
            assert snap["messages"][msg][field] == num, \
                "%s.%s = %r, want %d" % (msg, field, snap["messages"][msg].get(field), num)
        # PruneRequest.all must remain field 1 (unchanged existing field number)
        assert snap["messages"]["PruneRequest"]["all"] == 1, "PruneRequest.all must stay 1"

    check("approved additive scope fields present with exact numbers (Update/Prune/host/wsl2)",
          additive_present)

    # ---- serialize -> parse round-trip is accepted; counts preserved ----
    def roundtrip_accepted():
        text = serialize_model(BASE_MODEL)  # canonical, no permute/noise
        snap = parse_contract(text)
        assert len(snap["services"]["ColimaService"]) == 31
        assert len(snap["services"]["DockerService"]) == 34
        assert check_frozen_contract(snap) == [], "round-trip proto rejected"

    check("serialize(model) round-trips through the parser and is accepted", roundtrip_accepted)

    # ---- Permutation (fixed seeds) is accepted ----
    def permutation_accepted():
        for seed in (1, 7, 4242):
            rng = random.Random(seed)
            snap = parse_contract(serialize_model(BASE_MODEL, rng, permute=True, noise=True))
            assert check_frozen_contract(snap) == [], "permuted proto rejected (seed=%d)" % seed
            assert sum(len(v) for v in snap["services"].values()) == 65

    check("permuted-order-but-same-set proto is accepted", permutation_accepted)

    # ---- A parser fidelity spot-check (ColimaConfig has 27 fields; env=27) ----
    def parser_fidelity():
        snap = parse_contract(REAL_PROTO_TEXT)
        cc = snap["messages"]["ColimaConfig"]
        assert len(cc) == 27, "ColimaConfig parsed %d fields (want 27)" % len(cc)
        assert cc["env"] == 27 and cc["docker"] == 24, "map<> field numbers misparsed"
        assert snap["messages"]["Empty"] == {}, "Empty should have no fields"

    check("parser fidelity: ColimaConfig map<> fields + Empty{} parsed correctly",
          parser_fidelity)

    # ---- One hand-crafted rejection per mutator kind ----
    def each_mutator_rejects():
        for mname, mfn in MUTATORS:
            model = copy.deepcopy(BASE_MODEL)
            rng = random.Random(hash(mname) & 0xFFFFFFFF)
            expected = mfn(model, rng)
            violations = check_proto_text(serialize_model(model))
            assert violations, "mutator %s produced an accepted proto" % mname
            assert any(expected in v for v in violations), \
                "mutator %s: expected %r not in %r" % (mname, expected, violations[:12])

    check("every mutator kind yields a rejection with the matching reason", each_mutator_rejects)

    # ---- Move RPC across services keeps total 65 but breaks per-service counts ----
    def move_rpc_detected_despite_total_65():
        model = copy.deepcopy(BASE_MODEL)
        colima = next(s for s in model["services"] if s[0] == "ColimaService")
        docker = next(s for s in model["services"] if s[0] == "DockerService")
        moved = colima[1].pop(0)          # move the first ColimaService RPC to DockerService
        docker[1].append(moved)
        snap = parse_contract(serialize_model(model))
        total = sum(len(v) for v in snap["services"].values())
        assert total == 65, "sanity: total should still be 65, got %d" % total
        violations = check_frozen_contract(snap)
        assert any(v.startswith("rpc-count:") for v in violations), \
            "moved RPC not caught by per-service count: %r" % violations[:12]
        assert any(v.startswith("rpc-missing:ColimaService.") for v in violations)
        assert any(v.startswith("rpc-extra:DockerService.") for v in violations)

    check("cross-service RPC move caught even though total stays 65",
          move_rpc_detected_despite_total_65)

    return results


# --------------------------------------------------------------------------- #
# Orchestration
# --------------------------------------------------------------------------- #
def run_all(iters, seed):
    global _LOG_FH
    _LOG_FH = open(LOG_PATH, "w")
    log("START frozen-contract PBT  seed=%d iters=%d  proto=%s" % (seed, iters, PROTO_PATH))
    log("Feature: cross-platform-live-verification (Property 6)")
    log("baseline: %d ColimaService + %d DockerService = %d RPCs, %d frozen messages"
        % (len(FROZEN_RPCS["ColimaService"]), len(FROZEN_RPCS["DockerService"]),
           EXPECTED_TOTAL_RPCS, len(FROZEN_FIELDS)))

    if not PROTO_PATH.exists():
        log("FATAL: proto not found at %s" % PROTO_PATH)
        return 1

    det = run_deterministic_checks()
    det_failed = [d for d in det if not d[1]]
    for name, ok, detail in det:
        log("  [det] %-62s %s%s" % (name, "OK" if ok else "FAIL",
                                    "" if ok else "  (%s)" % detail))
    log("Deterministic checks: %d/%d passed" % (len(det) - len(det_failed), len(det)))

    seed_rng = random.Random(seed)
    results = [
        run_property_permutation(seed_rng, iters),
        run_property_single_mutation(seed_rng, iters),
        run_property_compound_mutation(seed_rng, iters),
    ]
    for r in results:
        log("  %-56s ran=%d passed=%d failed=%d" % (r.name, r.ran, r.passed, r.failed))

    total_failed = len(det_failed) + sum(r.failed for r in results)
    summary = {
        "seed": seed,
        "iters_per_property": iters,
        "deterministic": {"total": len(det), "failed": len(det_failed),
                          "failures": [d[0] for d in det_failed]},
        "properties": [
            {"name": r.name, "ran": r.ran, "passed": r.passed, "failed": r.failed,
             "counterexamples": r.failures[:5]}
            for r in results
        ],
        "overall": "PASS" if total_failed == 0 else "FAIL",
    }
    with open(SUMMARY_PATH, "w") as fh:
        json.dump(summary, fh, indent=2)
    log("DONE overall=%s total_failures=%d  summary=%s"
        % (summary["overall"], total_failed, SUMMARY_PATH))
    _LOG_FH.close()
    return 0 if total_failed == 0 else 1


# --------------------------------------------------------------------------- #
# pytest entry points (min 100 iterations enforced)
# --------------------------------------------------------------------------- #
_PYTEST_ITERS = int(os.environ.get("FROZEN_ITERS", "200"))
_PYTEST_SEED = int(os.environ.get("FROZEN_SEED", "6006"))


def test_property_6a_permutation_invariance_accepted():
    """Feature: cross-platform-live-verification, Property 6."""
    r = run_property_permutation(random.Random(_PYTEST_SEED), _PYTEST_ITERS)
    assert r.ran >= 100, "must run >=100 iterations, ran %d" % r.ran
    assert r.failed == 0, "permutation-invariance counterexamples: %r" % r.failures[:5]


def test_property_6b_single_mutation_rejected():
    """Feature: cross-platform-live-verification, Property 6."""
    r = run_property_single_mutation(random.Random(_PYTEST_SEED + 1), _PYTEST_ITERS)
    assert r.ran >= 100, "must run >=100 iterations, ran %d" % r.ran
    assert r.failed == 0, "single-mutation counterexamples: %r" % r.failures[:5]


def test_property_6c_compound_mutation_rejected():
    """Feature: cross-platform-live-verification, Property 6."""
    r = run_property_compound_mutation(random.Random(_PYTEST_SEED + 2), _PYTEST_ITERS)
    assert r.ran >= 100, "must run >=100 iterations, ran %d" % r.ran
    assert r.failed == 0, "compound-mutation counterexamples: %r" % r.failures[:5]


def test_deterministic_edge_cases():
    det = run_deterministic_checks()
    failed = [(d[0], d[2]) for d in det if not d[1]]
    assert not failed, "deterministic edge case failures: %r" % failed


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def main():
    ap = argparse.ArgumentParser(description="Property test for frozen-contract preservation (Property 6).")
    ap.add_argument("--iters", type=int, default=200,
                    help="randomized iterations per property (min 100 enforced)")
    ap.add_argument("--seed", type=int,
                    default=int(os.environ.get("FROZEN_SEED", str(int(time.time())))))
    args = ap.parse_args()
    iters = max(100, args.iters)
    sys.exit(run_all(iters, args.seed))


if __name__ == "__main__":
    main()
