#!/usr/bin/env python3
"""Run synthetic performance workloads; never opens or edits real calendars."""
import argparse
import json
from pathlib import Path
import re
import statistics
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser()
parser.add_argument('--source-root',type=Path,default=repo)
parser.add_argument('--baseline',action='store_true',help='Use the reference linear weather lookup for the pre-audit source snapshot')
args = parser.parse_args()
source_names = re.findall(r'Sources/[^ ]+\.swift',(repo/'test.sh').read_text())
source_files = [args.source_root/name for name in source_names if (args.source_root/name).exists()]
with tempfile.TemporaryDirectory(prefix='sunshine-benchmark-') as directory:
    executable = Path(directory)/'Benchmark'
    command = ['swiftc','-parse-as-library','-swift-version','5','-target','arm64-apple-macos14.0','-module-cache-path',str(Path(tempfile.gettempdir())/'sunshine-perf-module-cache')]
    if not args.baseline:
        command += ['-D','PERF_AFTER']
    command += [str(path) for path in source_files]
    command += [str(repo/'Tests/Performance/AuditBenchmark.swift'),'-o',str(executable)]
    for framework in ['SwiftUI','AppKit','EventKit','CoreLocation','MapKit']:
        command += ['-framework',framework]
    subprocess.run(command,check=True)
    runs = []
    for _ in range(3):
        output = subprocess.run([str(executable)],check=True,capture_output=True,text=True).stdout
        runs.append({line.split(': ')[0]:float(line.split(': ')[1].removesuffix(' ms')) for line in output.splitlines()})
    print(json.dumps({key:statistics.median(run[key] for run in runs) for key in runs[0]},indent=2))
