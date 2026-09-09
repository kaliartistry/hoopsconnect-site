const accountDeletionWireIntegerCases = <Map<String, Object>>[
  {'name': 'integerLiteral', 'json': '1', 'accepted': true, 'normalized': 1},
  {'name': 'decimalInteger', 'json': '1.0', 'accepted': true, 'normalized': 1},
  {'name': 'exponentInteger', 'json': '1e0', 'accepted': true, 'normalized': 1},
  {'name': 'negativeZero', 'json': '-0.0', 'accepted': true, 'normalized': 0},
  {
    'name': 'positiveSafeBoundary',
    'json': '9007199254740991',
    'accepted': true,
    'normalized': 9007199254740991,
  },
  {
    'name': 'negativeSafeBoundary',
    'json': '-9007199254740991',
    'accepted': true,
    'normalized': -9007199254740991,
  },
  {'name': 'fraction', 'json': '1.5', 'accepted': false},
  {'name': 'positiveOutOfRange', 'json': '9007199254740992', 'accepted': false},
  {
    'name': 'negativeOutOfRange',
    'json': '-9007199254740992',
    'accepted': false,
  },
  {'name': 'numericString', 'json': '"1"', 'accepted': false},
];
