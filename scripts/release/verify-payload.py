#!/usr/bin/env python3
"""Audit the current offline app, optionally comparing an exported/installed copy."""
import argparse, hashlib, json, plistlib, stat, struct
from pathlib import Path
SIGNATURE_NAMES = {'CodeDirectory', 'CodeRequirements', 'CodeResources', 'CodeSignature'}
def require(condition, message):
    if not condition:
        raise ValueError(message)

def digest(path, algorithm='sha256'):
    h = hashlib.sha256() if algorithm == 'sha256' else hashlib.sha1()
    if algorithm == 'git-blob-sha1':
        h.update(('blob ' + str(path.stat().st_size) + '\0').encode())
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(4 * 1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()

def normalized_executable(path):
    data = path.read_bytes()
    magic, cpu, _, _, count, command_bytes, _, _ = struct.unpack_from('<IiiIIIII', data)
    require(magic == 0xfeedfacf and cpu == 0x100000c, 'Expected thin arm64 Mach-O')
    offset, signatures, linkedit = 32, [], []
    for _ in range(count):
        command, size = struct.unpack_from('<II', data, offset)
        require(size >= 8 and offset + size <= 32 + command_bytes, 'Invalid load command')
        if command == 0x1d:
            require(size == 16, 'Unexpected LC_CODE_SIGNATURE size')
            signatures.append((offset, *struct.unpack_from('<II', data, offset + 8)))
        if command == 0x19 and data[offset + 8:offset + 24].rstrip(b'\0') == b'__LINKEDIT':
            linkedit.append(offset)
        offset += size
    require(offset == 32 + command_bytes and len(signatures) == len(linkedit) == 1,
            'Expected exactly one signature and __LINKEDIT segment')
    command, signature_offset, signature_size = signatures[0]
    segment = linkedit[0]
    vm_size, file_offset, file_size = struct.unpack_from('<QQQ', data, segment + 32)
    require(signature_offset >= offset and signature_offset % 16 == 0 and signature_size > 0,
            'Invalid signature offset/size')
    require(signature_offset + signature_size == len(data), 'Signature must be exactly at EOF')
    require(file_offset <= signature_offset and file_offset + file_size == len(data),
            '__LINKEDIT does not end with the signature')
    require(vm_size == (file_size + 16383) // 16384 * 16384, 'Unexpected __LINKEDIT VM alignment')
    normalized = bytearray(data[:signature_offset])
    struct.pack_into('<I', normalized, command + 12, 0)
    struct.pack_into('<Q', normalized, segment + 32, 0)
    struct.pack_into('<Q', normalized, segment + 48, 0)
    return {
        'sha256': hashlib.sha256(data).hexdigest(),
        'normalized_sha256': hashlib.sha256(normalized).hexdigest(),
        'architecture': 'arm64', 'signature_offset': signature_offset,
        'signature_bytes': signature_size, 'linkedit_vm_size': vm_size,
        'linkedit_file_size': file_size,
    }, data

def inventory(app):
    files, signature_files = {}, []
    for path in app.rglob('*'):
        require(not path.is_symlink(), 'Unexpected symlink: ' + str(path.relative_to(app)))
        if not path.is_file():
            continue
        name = str(path.relative_to(app))
        if path.parent.name == '_CodeSignature' and path.name in SIGNATURE_NAMES:
            signature_files.append(name)
        elif name == 'Contents/CodeResources':
            # Apple Security's copyStapledTicketInBundle reads this exact ticket location.
            require(path.read_bytes().startswith(b's8ch'), 'Unexpected stapled-ticket header')
            signature_files.append(name)
        else:
            files[name] = path
    return files, sorted(signature_files)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("app", type=Path)
    parser.add_argument("report", type=Path)
    parser.add_argument("--archive", type=Path)
    parser.add_argument("--reference", type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    app = args.app.resolve()
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    source_info = plistlib.loads((root / "Tess/Info.plist").read_bytes())
    for key in ["CFBundleVersion", "CFBundleShortVersionString"]:
        require(info[key] == source_info[key], "Incorrect " + key)
    require(info["CFBundleIdentifier"] == "life.baode.tess", "Incorrect Bundle ID")
    require(info["LSMinimumSystemVersion"] == "26.0", "Incorrect system requirement")
    actual, signatures = inventory(app)
    require(args.archive or args.reference, "Provide --reference for the initial audit or --archive for comparison")
    reference = (args.archive or args.reference).resolve()
    expected, _ = inventory(reference)
    require(set(actual) == set(expected), "Payload inventory differs: " + repr(set(actual)^set(expected)))
    code, binary = normalized_executable(app / "Contents/MacOS/Tess")
    if args.archive:
        archive_code, _ = normalized_executable(reference / "Contents/MacOS/Tess")
        require(code["normalized_sha256"] == archive_code["normalized_sha256"], "Code differs beyond signing fields")
        require(info == plistlib.loads((reference / "Contents/Info.plist").read_bytes()), "App metadata differs")
    report = {"app": str(app), "version": info["CFBundleShortVersionString"], "build": info["CFBundleVersion"],
              "bundle_id": info["CFBundleIdentifier"], "executable": code, "signature_files": signatures,
              "comparison_reference": str(reference), "files": []}
    for name,path in sorted(actual.items()):
        if name != "Contents/MacOS/Tess" and (args.archive or name.startswith("Contents/Resources/")):
            require(digest(path) == digest(expected[name]), "Resource differs: " + name)
        report["files"].append({"path":name,"size":path.stat().st_size,"sha256":digest(path)})
    resources = app / "Contents/Resources"
    for path in (root / "Tess/Resources").iterdir():
        if path.is_file():
            require(digest(resources/path.name) == digest(path), "Source resource differs: " + path.name)
    model = resources / "BaseSpeechModel.tessmodel"
    baseline = json.loads((root / "scripts/release/base-model-receipt.json").read_text())
    require(json.loads((model/".tess-verified.json").read_text()) == baseline, "Model receipt differs")
    require({p.name for p in model.iterdir()} == {f["path"] for f in baseline["files"]} | {".tess-verified.json"}, "Model inventory differs")
    for f in baseline["files"]:
        p=model/f["path"]
        require(p.stat().st_size == f["size"], "Model size differs")
        algorithm="sha256" if len(f["digest"]) == 64 else "git-blob-sha1"
        require(digest(p,algorithm) == f["digest"], "Model digest differs: " + f["path"])
        require(p.stat().st_mode & stat.S_IROTH, "Model not readable")
    markers=["--smoke-test", "--hud-preview", "--asr-benchmark", "TESS_DATA_DIRECTORY", "TessTargetCheck", "TessFnEvent", "WechatGuardDiagnostic"]
    require(not any(m.encode() in binary for m in markers), "Internal diagnostic entry point found")
    report.update(result="passed", offline_model={"repository":baseline["repository"], "revision":baseline["revision"], "bytes":sum(f["size"] for f in baseline["files"]), "all_digests_verified":True},
                  known_internal_markers_absent=markers, payload_scope="Exact reviewed resource inventory; signatures, notarization, Gatekeeper and human use checked separately")
    args.report.write_text(json.dumps(report,ensure_ascii=False,indent=2)+"\n")
    print(json.dumps({k:report[k] for k in ["result","version","build","bundle_id","offline_model"]}))

if __name__ == "__main__":
    main()
