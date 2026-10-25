#!/usr/bin/env python3
"""Validate Apple's string tables before testing or packaging Sandy."""

import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
QUOTED = r'"(?:[^"\\]|\\.)*"'
TOKEN = re.compile(
    rf'\s+|/\*.*?\*/|//[^\n]*|(?P<entry>(?P<key>{QUOTED})\s*=\s*(?P<value>{QUOTED})\s*;)',
    re.DOTALL,
)
# A translation may move numbered arguments, but their types must stay intact.
FORMAT = re.compile(r'%(?:(\d+)\$)?[-+ #0]*(?:\d+)?(?:\.\d+)?(hh|ll|[hljztL])?([@diuoxXfFeEgGaAcCsSp])|%%')


def arguments(text):
    result = {}
    next_index = 1
    for match in FORMAT.finditer(text):
        if match.group() == '%%':
            continue
        position, length, kind = match.groups()
        index = int(position) if position else next_index
        if not position:
            next_index += 1
        signature = (index, (length or '') + kind)
        result[signature] = result.get(signature, 0) + 1
    return result


def read_table(path):
    subprocess.run(['plutil', '-lint', str(path)], check=True, capture_output=True)
    text = path.read_text(encoding='utf-8')
    values = {}
    offset = 0
    while offset < len(text):
        match = TOKEN.match(text, offset)
        if not match:
            raise ValueError(f'{path.relative_to(ROOT)}: invalid entry near character {offset}')
        offset = match.end()
        if not match.group('entry'):
            continue
        key = json.loads(match.group('key'))
        value = json.loads(match.group('value'))
        if key in values:
            raise ValueError(f'{path.relative_to(ROOT)}: duplicate key {key!r}')
        if not value.strip():
            raise ValueError(f'{path.relative_to(ROOT)}: empty translation for {key!r}')
        values[key] = value
    return values


def main():
    folders = sorted((ROOT / 'Resources').glob('*.lproj'))
    expected_languages = {'en', 'ru', 'kk', 'de', 'fr', 'es', 'zh-Hans', 'ja'}
    if expected_languages != {folder.stem for folder in folders}:
        raise ValueError('Language folders do not match the supported languages')
    for table in ('Localizable.strings', 'InfoPlist.strings'):
        source = read_table(ROOT / 'Resources' / 'en.lproj' / table)
        if table == 'Localizable.strings':
            calls = re.compile(rf'\b(?:localized|Text|Button|TextField|Picker)\(\s*({QUOTED})')
            used = set()
            for path in (ROOT / 'Sources').rglob('*.swift'):
                for match in calls.finditer(path.read_text(encoding='utf-8')):
                    literal = match.group(1)
                    if '\\(' in literal:
                        continue
                    key = json.loads(literal)
                    if any(character.isalpha() for character in key):
                        used.add(key)
            if used - source.keys():
                raise ValueError(f'Interface strings missing from English table: {sorted(used - source.keys())}')
        for folder in folders:
            translated = read_table(folder / table)
            missing = source.keys() - translated.keys()
            extra = translated.keys() - source.keys()
            if missing or extra:
                raise ValueError(f'{folder.name}/{table}: missing={sorted(missing)}, extra={sorted(extra)}')
            for key, value in translated.items():
                if arguments(value) != arguments(source[key]):
                    raise ValueError(f'{folder.name}/{table}: format arguments differ for {key!r}')
        print(f'{table}: {len(source)} keys verified in {len(folders)} languages')


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f'Localization check failed: {error}', file=sys.stderr)
        sys.exit(1)
