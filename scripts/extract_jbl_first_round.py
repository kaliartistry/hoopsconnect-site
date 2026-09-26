#!/usr/bin/env python3
"""Read Kurt's original XLS without modifying it; emit a local JSON import.

Requires xlrd 2.0.2 for legacy BIFF .xls (the XLSX artifact reader cannot read it).
No network, Firebase, or spreadsheet writes are performed.
"""
import argparse
import collections
import hashlib
import json
import re
from pathlib import Path

import xlrd

TEAM_MAP = {
    'RAPTORS': ('rae-town-raptors', 'Rae Town Raptors', 'raptors'),
    "WIZZARDS'25": ('tivoli-wizards', 'Tivoli Wizards', 'tivoli'),
    "WARRIORS'25": ('mbbgc-warriors', 'MBBGC Warriors', 'warriors'),
    "SLAYERS'25": ('st-georges-slayers', 'St George’s Slayers', 'slayers'),
    'FLAMES': ('portmore-flames', 'Portmore Flames', 'flames'),
    "EAGLES'25": ('upper-room-eagles', 'Upper Room Eagles', 'eagles'),
    "REBELS'25": ('uwi-running-rebels', 'UWI Running Rebels', 'rebels'),
    "CELTICS'25": ('central-celtics', 'Central Celtics', 'celtics'),
    "KNIGHTS'25": ('urban-knights', 'Urban Knights', 'knights'),
    "SPARTANS'25": ('spanish-town-spartans', 'Spanish Town Spartans', 'spartans'),
}
HEADERS = ['Player', '', 'Team', '', 'G', 'Min', 'Pts', 'PPG', '2PM',
           '2P%', '3PM', '3P%', 'FTM', 'FT%', 'FG%', 'Reb', 'Ast', 'Blk', 'Stl']
FIELDS = {4: 'gamesPlayed', 6: 'points', 8: 'twoMade', 10: 'threeMade',
          12: 'ftMade', 15: 'rebounds', 16: 'assists', 17: 'blocks', 18: 'steals'}


def extract(source):
    book = xlrd.open_workbook(source)
    if book.sheet_names() != ['Recovered_Sheet1']:
        raise ValueError('Unexpected source sheets; review before import.')
    sheet = book.sheet_by_index(0)
    if sheet.row_values(7) != HEADERS or sheet.ncols != 19:
        raise ValueError('Unexpected headers; review before import.')
    as_of = xlrd.xldate_as_datetime(sheet.cell_value(3, 0), book.datemode).date().isoformat()
    players, source_totals, annotations = [], None, []
    for row_index in range(8, sheet.nrows):
        row = sheet.row_values(row_index)
        if not any(row):
            continue
        if str(row[0]).strip() == 'TOTALS':
            source_totals = {field: int(str(row[c]).replace(',', ''))
                             for c, field in FIELDS.items() if c != 4}
            continue
        source_name, source_team = str(row[0]).strip(), str(row[2]).strip()
        if source_team not in TEAM_MAP:
            raise ValueError(f'Unmapped team at row {row_index + 1}: {source_team}')
        team_id, team_name, _ = TEAM_MAP[source_team]
        # Preserve original spelling/case; isolate unexplained source markers.
        display_name = re.sub(r'\s*\*+\s*$', '', source_name).strip()
        if display_name != source_name:
            annotations.append({'row': row_index + 1, 'sourceName': source_name,
                                'displayName': display_name, 'markerMeaning': None})
        slug = re.sub(r'[^a-z0-9]+', '-', display_name.lower()).strip('-')
        values = {field: int(str(row[c]).replace(',', '')) for c, field in FIELDS.items()}
        if values['gamesPlayed'] <= 0 or min(values.values()) < 0:
            raise ValueError(f'Invalid count at row {row_index + 1}')
        if values['points'] != 2 * values['twoMade'] + 3 * values['threeMade'] + values['ftMade']:
            raise ValueError(f'Scoring mismatch at row {row_index + 1}')
        players.append({
            'playerId': f'jbl-2025-{team_id}-{slug}', 'displayName': display_name,
            'teamId': team_id, 'teamName': team_name, 'divisionId': 'jbl-2025-first-round',
            **values, 'sourcePpg': float(row[7]),
            'sourcePercentages': {HEADERS[c]: float(row[c]) for c in [9, 11, 13, 14]},
            'sourceMinutes': row[5], 'sourceRow': row_index + 1,
            'sourceName': source_name, 'sourceTeam': source_team,
        })
    ids = [p['playerId'] for p in players]
    if len(ids) != len(set(ids)):
        raise ValueError('Duplicate player identity; manual mapping required.')
    totals = {field: sum(p[field] for p in players) for c, field in FIELDS.items() if c != 4}
    if totals != source_totals:
        raise ValueError(f'Totals do not reconcile: {totals} vs {source_totals}')
    return {
        'schemaVersion': 1, 'leagueName': 'Jamaica Basketball League',
        'shortName': 'JBL', 'seasonLabel': '2025 Season', 'asOf': as_of,
        'source': {'fileName': Path(source).name, 'sheet': sheet.name,
                   'sha256': hashlib.sha256(Path(source).read_bytes()).hexdigest()},
        'teams': [{'teamId': tid, 'name': name, 'divisionId': 'jbl-2025-first-round',
                   'logoUrl': f'asset:assets/images/jbl_{logo}.png', 'sourceTeam': source_team}
                  for source_team, (tid, name, logo) in TEAM_MAP.items()],
        'players': players, 'totals': totals, 'annotations': annotations,
        'teamPlayerCounts': dict(collections.Counter(p['teamId'] for p in players)),
        'unavailable': ['Individual game results, dates and period scores',
                        'Wins, losses, points against and official standings',
                        'Shooting attempts, fouls and turnovers',
                        'Jersey numbers, positions and current player registrations',
                        'Reliable minutes (all source values are zero)',
                        'Official leaderboard qualification rule'],
    }


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('source')
    args = parser.parse_args()
    print(json.dumps(extract(args.source), ensure_ascii=False, indent=2))
